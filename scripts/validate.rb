#!/usr/bin/env ruby
# frozen_string_literal: true

# Checks the plugin as one system: the engine spec, profiles, workflows,
# skills, agents, hooks, ledger and docs must agree with each other.
# Exits 1 and lists every problem if they do not.
#
#   ruby scripts/validate.rb

require 'yaml'
require 'json'
require 'date'
require 'set'

ROOT = File.expand_path('..', __dir__)
ERRORS = []

def err(file, msg)
  ERRORS << "#{file}: #{msg}"
end

def path(rel)
  File.join(ROOT, rel)
end

def load_yaml(rel)
  YAML.safe_load(File.read(path(rel)), permitted_classes: [Date])
rescue Errno::ENOENT
  err(rel, 'file is missing')
  nil
rescue Psych::Exception => e
  err(rel, "invalid YAML: #{e.message}")
  nil
end

def frontmatter(rel)
  m = File.read(path(rel)).match(/\A---\n(.*?)\n---\n/m)
  return nil unless m

  YAML.safe_load(m[1], permitted_classes: [Date])
rescue Psych::Exception => e
  err(rel, "invalid frontmatter: #{e.message}")
  nil
end

def names_in(dir, pattern)
  Dir.glob(File.join(ROOT, dir, pattern)).sort.map { |f| f.sub("#{ROOT}/", '') }
end

# --- engine ---------------------------------------------------------------

engine = load_yaml('engine/engine.yaml') || {}
STEP_TYPES = engine['step_types'] || {}
MODELS = engine['models'] || []
COMMANDS = engine['commands'] || []
FORGES = engine['forges'] || []
VCS_ACTIONS = engine['vcs_actions'] || {}
COMMON = engine['common_fields'] || { 'required' => [], 'optional' => [] }

expected_types = %w[instruct agents check gate artifact vcs workflow loop]
unless STEP_TYPES.keys.sort == expected_types.sort
  err('engine/engine.yaml', "step_types must be exactly: #{expected_types.join(', ')}")
end
%w[statuses failure rules run_log].each do |key|
  err('engine/engine.yaml', "missing section `#{key}`") unless engine[key].is_a?(Hash)
end

# --- templates ------------------------------------------------------------

TEMPLATES = {}
names_in('engine/templates', '*.md').each do |rel|
  name = File.basename(rel, '.md')
  fm = frontmatter(rel)
  if fm.nil?
    err(rel, 'missing frontmatter')
    next
  end
  err(rel, "frontmatter `template` must be `#{name}`") unless fm['template'] == name
  max = fm['max_lines']
  if max.is_a?(Integer)
    lines = File.read(path(rel)).lines.size
    err(rel, "is #{lines} lines, over its own max_lines of #{max}") if lines > max
  else
    err(rel, 'frontmatter `max_lines` must be a number')
  end
  err(rel, 'templates hold no code: remove the code fence') if File.read(path(rel)).include?('```')
  TEMPLATES[name] = fm
end
err('engine/templates', 'no templates found') if TEMPLATES.empty?

# --- profiles -------------------------------------------------------------

profiles = (load_yaml('engine/profiles.yaml') || {})['profiles']
unless profiles.is_a?(Hash) && !profiles.empty?
  err('engine/profiles.yaml', 'needs at least one profile under `profiles`')
  profiles = {}
end
profiles.each do |name, prof|
  where = "engine/profiles.yaml (#{name})"
  match = prof['match']
  if !match.is_a?(Hash) || (match.keys - %w[remote files]).any? || match.empty?
    err(where, '`match` needs `remote`, `files` or both, and nothing else')
  elsif match['remote']
    begin
      Regexp.new(match['remote'])
    rescue RegexpError => e
      err(where, "match.remote is not a valid regex: #{e.message}")
    end
  end
  err(where, 'missing `base_branch`') unless prof['base_branch'].is_a?(String)
  err(where, "`forge` must be one of: #{FORGES.join(', ')}") unless FORGES.include?(prof['forge'])
  cmds = prof['commands']
  unless cmds.is_a?(Hash)
    err(where, 'missing `commands`')
    next
  end
  (COMMANDS - cmds.keys).each { |k| err(where, "commands.#{k} is missing (use null if it does not apply)") }
  (cmds.keys - COMMANDS).each { |k| err(where, "commands.#{k} is not a key the engine knows") }
  (prof.keys - %w[description match base_branch forge commands commit_hook workspace]).each do |k|
    err(where, "`#{k}` is not a field of a profile")
  end
  if prof.key?('commit_hook')
    hook = prof['commit_hook']
    if hook.is_a?(Array)
      (hook - COMMANDS).each { |k| err(where, "commit_hook names `#{k}`, which is not a command key") }
    else
      err(where, '`commit_hook` must be a list of command keys')
    end
  end
  if prof.key?('workspace')
    ws = prof['workspace']
    if ws.is_a?(Hash) && (ws.keys - %w[create remove path]).empty? && %w[create remove path].all? { |k| ws[k].is_a?(String) }
      %w[create remove path].each { |k| err(where, "workspace.#{k} must use {name}") unless ws[k].include?('{name}') }
    else
      err(where, '`workspace` needs `create`, `remove` and `path`, and nothing else')
    end
  end
end

# --- skills ---------------------------------------------------------------

SKILLS = Set.new
names_in('skills', '*/SKILL.md').each do |rel|
  name = File.basename(File.dirname(rel))
  fm = frontmatter(rel)
  if fm.nil?
    err(rel, 'missing frontmatter')
    next
  end
  err(rel, "frontmatter `name` must be `#{name}`") unless fm['name'] == name
  err(rel, 'missing `description`') unless fm['description'].is_a?(String) && !fm['description'].empty?
  SKILLS << name
end

# --- agents ---------------------------------------------------------------

AGENTS = {}
WRITE_TOOLS = %w[Edit Write MultiEdit NotebookEdit].freeze
names_in('agents', '*.md').each do |rel|
  name = File.basename(rel, '.md')
  fm = frontmatter(rel)
  if fm.nil?
    err(rel, 'missing frontmatter')
    next
  end
  err(rel, "frontmatter `name` must be `#{name}`") unless fm['name'] == name
  err(rel, 'missing `description`') unless fm['description'].is_a?(String) && !fm['description'].empty?
  err(rel, "`model` must be one of: #{MODELS.join(', ')}") unless MODELS.include?(fm['model'])
  tools = fm['tools']
  tools = tools.split(',') if tools.is_a?(String)
  if tools.is_a?(Array) && !tools.empty?
    tools = tools.map(&:strip)
    AGENTS[name] = { read_only: (tools & WRITE_TOOLS).empty? }
  else
    err(rel, '`tools` must list the agent\'s tools; an agent without it inherits every tool')
  end
end

# --- hooks and the read-only guard ---------------------------------------

hooks_rel = 'hooks/hooks.json'
begin
  hooks = JSON.parse(File.read(path(hooks_rel)))
  commands = (hooks['hooks'] || {}).values.flatten.flat_map { |g| g['hooks'] || [] }.map { |h| h['command'].to_s }
  commands.each do |cmd|
    cmd.scan(%r{\$\{CLAUDE_PLUGIN_ROOT\}/([\w./-]+)}).flatten.each do |script|
      if !File.exist?(path(script))
        err(hooks_rel, "references #{script}, which does not exist")
      elsif !File.executable?(path(script))
        err(script, 'is not executable')
      end
    end
  end
  pre = (hooks['hooks'] || {})['PreToolUse'] || []
  guard = pre.find { |g| (g['hooks'] || []).any? { |h| h['command'].to_s.include?('guard-agents.sh') } }
  if guard
    matched = guard['matcher'].to_s.split('|')
    (%w[Edit Write Bash] - matched).each { |t| err(hooks_rel, "the guard's matcher does not cover #{t}") }
  else
    err(hooks_rel, 'no PreToolUse hook runs scripts/guard-agents.sh')
  end
rescue Errno::ENOENT
  err(hooks_rel, 'file is missing')
rescue JSON::ParserError => e
  err(hooks_rel, "invalid JSON: #{e.message}")
end

guard_rel = 'scripts/guard-agents.sh'
if File.exist?(path(guard_rel))
  listed = File.read(path(guard_rel))[/^READ_ONLY_AGENTS="([^"]*)"/, 1].to_s.split
  actual = AGENTS.select { |_, a| a[:read_only] }.keys
  (actual - listed).each { |a| err(guard_rel, "agent `#{a}` has no write tools but is not in READ_ONLY_AGENTS") }
  (listed - actual).each { |a| err(guard_rel, "READ_ONLY_AGENTS names `#{a}`, which is not a read-only agent in agents/") }
  test_rel = 'scripts/guard-agents.test.sh'
  if File.exist?(path(test_rel))
    out = `bash "#{path(test_rel)}" 2>&1`
    err(test_rel, "guard tests failed:\n#{out}") unless $?.success?
  else
    err(test_rel, 'the guard has no tests')
  end
else
  err(guard_rel, 'file is missing')
end

# The gate guard: wired for Bash, and its tests pass.
gates_rel = 'scripts/guard-gates.sh'
if File.exist?(path(gates_rel))
  wired = File.exist?(path(hooks_rel)) && File.read(path(hooks_rel)).include?('guard-gates.sh')
  err(hooks_rel, 'no PreToolUse hook runs scripts/guard-gates.sh') unless wired
  gates_test_rel = 'scripts/guard-gates.test.sh'
  if File.exist?(path(gates_test_rel))
    out = `bash "#{path(gates_test_rel)}" 2>&1`
    err(gates_test_rel, "gate guard tests failed:\n#{out}") unless $?.success?
  else
    err(gates_test_rel, 'the gate guard has no tests')
  end
else
  err(gates_rel, 'file is missing')
end

# --- workflows ------------------------------------------------------------

WORKFLOWS = {}
names_in('workflows', '*.yaml').each do |rel|
  wf = load_yaml(rel)
  WORKFLOWS[File.basename(rel, '.yaml')] = [rel, wf] if wf.is_a?(Hash)
end
err('workflows', 'no workflows found') if WORKFLOWS.empty?

def check_steps(rel, steps, ctx)
  unless steps.is_a?(Array) && !steps.empty?
    err(rel, '`steps` must be a non-empty list')
    return
  end
  steps.each do |step|
    unless step.is_a?(Hash) && step['id'].is_a?(String)
      err(rel, "a step has no `id`: #{step.inspect[0, 60]}")
      next
    end
    id = step['id']
    at = "#{rel} (#{id})"
    err(at, 'duplicate step id') unless ctx[:ids].add?(id)
    err(at, 'step ids use lowercase letters, digits and hyphens') unless id =~ /\A[a-z0-9][a-z0-9-]*\z/

    spec = STEP_TYPES[step['type']]
    if spec.nil?
      err(at, "unknown type `#{step['type']}`")
      next
    end
    allowed = COMMON['required'] + COMMON['optional'] + spec['required'] + spec['optional']
    (step.keys - allowed).each { |k| err(at, "`#{k}` is not a field of a #{step['type']} step") }
    (spec['required'] - step.keys).each { |k| err(at, "a #{step['type']} step needs `#{k}`") }

    if step.key?('on_fail') && !%w[stop ask continue].include?(step['on_fail'])
      err(at, '`on_fail` must be stop, ask or continue')
    end

    Array(step['skills']).each do |s|
      err(at, "loads skill `#{s}`, which the workflow does not declare") unless ctx[:skills].include?(s)
      ctx[:used_skills] << s
    end
    Array(step['inputs']).each do |i|
      err(at, "input `#{i}` is not a template in engine/templates") unless TEMPLATES.key?(i)
    end

    outward = step['outward'] == true
    case step['type']
    when 'instruct'
      if step['delegate']
        err(at, "delegates to `#{step['delegate']}`, which the workflow does not declare") unless ctx[:agents].include?(step['delegate'])
        ctx[:used_agents] << step['delegate']
      end
    when 'agents'
      spawn = Array(step['spawn'])
      err(at, '`spawn` must list at least one agent') if spawn.empty?
      spawn.each do |a|
        err(at, "spawns `#{a}`, which the workflow does not declare") unless ctx[:agents].include?(a)
        err(at, "spawns `#{a}`, which can write; an agents step is for read-only agents") if AGENTS[a] && !AGENTS[a][:read_only]
        ctx[:used_agents] << a
      end
    when 'check'
      keys = Array(step['run'])
      err(at, '`run` must list at least one command key') if keys.empty?
      (keys - COMMANDS).each { |k| err(at, "runs `#{k}`, which is not a command key in engine.yaml") }
      err(at, '`max_attempts` must be a positive number') if step.key?('max_attempts') && !(step['max_attempts'].is_a?(Integer) && step['max_attempts'].positive?)
    when 'gate'
      ctx[:gates] << id
      ctx[:revise] << [at, step['revise']] if step['revise']
    when 'artifact'
      err(at, "template `#{step['template']}` is not in engine/templates") unless TEMPLATES.key?(step['template'])
    when 'vcs'
      action = VCS_ACTIONS[step['action']]
      if action.nil?
        err(at, "`action` must be one of: #{VCS_ACTIONS.keys.join(', ')}")
      elsif action['outward'] && !outward
        err(at, "vcs #{step['action']} leaves the machine, so the step must be `outward: true`")
      end
    when 'workflow'
      ctx[:calls] << [at, step['run']]
      err(at, "runs workflow `#{step['run']}`, which does not exist") unless WORKFLOWS.key?(step['run'])
      if step['repo']
        err(at, "repo `#{step['repo']}` is not a profile") unless ctx[:profiles].key?(step['repo'])
        err(at, 'a workflow step with `repo` changes another repo, so it must be `outward: true`') unless outward
      end
    when 'loop'
      err(at, '`max` must be a positive number') unless step['max'].is_a?(Integer) && step['max'].positive?
      check_steps(rel, step['steps'], ctx)
    end

    if outward
      gate = step['gate']
      if gate.nil?
        err(at, 'is outward, so it must name its `gate`')
      elsif !ctx[:gates].include?(gate)
        err(at, "names gate `#{gate}`, which is not a gate step before it in this workflow")
      end
    elsif step.key?('gate')
      err(at, 'names a `gate` but is not `outward: true`')
    end
  end
end

calls = {}
WORKFLOWS.each do |name, (rel, wf)|
  err(rel, "`name` must be `#{name}`") unless wf['name'] == name
  err(rel, 'missing `description`') unless wf['description'].is_a?(String)
  (wf.keys - %w[name description args skills agents steps]).each { |k| err(rel, "unknown top-level key `#{k}`") }

  declared_skills = Array(wf['skills'])
  declared_skills.each { |s| err(rel, "declares skill `#{s}`, which is not in skills/") unless SKILLS.include?(s) }

  declared_agents = []
  Array(wf['agents']).each do |a|
    unless a.is_a?(Hash) && a['name']
      err(rel, 'each entry under `agents` needs `name` and `model`')
      next
    end
    err(rel, "declares agent `#{a['name']}`, which is not in agents/") unless AGENTS.key?(a['name'])
    err(rel, "agent `#{a['name']}` needs a `model` from: #{MODELS.join(', ')}") unless MODELS.include?(a['model'])
    err(rel, "declares agent `#{a['name']}` twice") if declared_agents.include?(a['name'])
    declared_agents << a['name']
  end

  ctx = { ids: Set.new, gates: [], revise: [], calls: [], profiles: profiles,
          skills: declared_skills, agents: declared_agents,
          used_skills: Set.new, used_agents: Set.new }
  check_steps(rel, wf['steps'], ctx)

  ctx[:revise].each do |at, target|
    err(at, "`revise` names `#{target}`, which is not a step in this workflow") unless ctx[:ids].include?(target)
  end
  (declared_skills - ctx[:used_skills].to_a).each { |s| err(rel, "declares skill `#{s}` but no step loads it") }
  (declared_agents - ctx[:used_agents].to_a).each { |a| err(rel, "declares agent `#{a}` but no step uses it") }
  calls[name] = ctx[:calls].map(&:last)
end

def cycle?(name, calls, trail)
  return true if trail.include?(name)

  (calls[name] || []).any? { |n| cycle?(n, calls, trail + [name]) }
end
WORKFLOWS.each do |name, (rel, _)|
  err(rel, 'runs itself through a chain of workflow steps') if cycle?(name, calls, [])
end

# --- ledger ---------------------------------------------------------------

ledger_rel = 'ledger/ledger.yaml'
ledger = load_yaml(ledger_rel)
if ledger.is_a?(Hash)
  err(ledger_rel, 'missing `surveyed` date') unless ledger['surveyed']
  ids = Set.new
  { 'repos' => 'repo', 'packages' => 'package', 'environments' => 'env' }.each do |section, kind|
    unless ledger[section].is_a?(Array)
      err(ledger_rel, "`#{section}` must be a list (it may be empty)")
      next
    end
    ledger[section].each do |node|
      id = node.is_a?(Hash) ? node['id'].to_s : ''
      err(ledger_rel, "#{section}: id `#{id}` must start with `#{kind}:`") unless id.start_with?("#{kind}:")
      err(ledger_rel, "duplicate id `#{id}`") unless ids.add?(id)
    end
  end
  repo_ids = Array(ledger['repos']).map { |r| r['id'].to_s.sub('repo:', '') }
  (repo_ids - profiles.keys).each { |r| err(ledger_rel, "repo `#{r}` has no profile in engine/profiles.yaml") }
  (profiles.keys - repo_ids).each { |p| err(ledger_rel, "profile `#{p}` has no repo entry in the ledger") }
  Array(ledger['packages']).each do |pkg|
    err(ledger_rel, "package `#{pkg['id']}` names repo `#{pkg['repo']}`, which is not in the ledger") unless ids.include?(pkg['repo'].to_s)
  end
  if ledger['edges'].is_a?(Array)
    kinds = %w[depends_on calls publishes_to deploys_to shares_schema_with]
    ledger['edges'].each do |edge|
      %w[from to].each do |side|
        err(ledger_rel, "edge #{side} `#{edge[side]}` is not a node in the ledger") unless ids.include?(edge[side].to_s)
      end
      err(ledger_rel, "edge kind `#{edge['kind']}` must be one of: #{kinds.join(', ')}") unless kinds.include?(edge['kind'])
      err(ledger_rel, "edge #{edge['from']} -> #{edge['to']} has no `evidence`") unless edge['evidence']
    end
  else
    err(ledger_rel, '`edges` must be a list (it may be empty)')
  end
end

# --- docs -----------------------------------------------------------------

names_in('docs/how-to', '*.md').each do |rel|
  fm = frontmatter(rel)
  sources = fm && fm['sources']
  unless sources.is_a?(Array) && !sources.empty?
    err(rel, 'a how-to guide lists the files it summarises under `sources` in its frontmatter')
    next
  end
  sources.each { |s| err(rel, "source `#{s}` does not exist") unless File.exist?(path(s)) }
end

if File.exist?(path('README.md'))
  readme = File.read(path('README.md'))
  WORKFLOWS.each_key { |w| err('README.md', "does not mention the `#{w}` workflow") unless readme.include?("`#{w}`") }
  AGENTS.each_key { |a| err('README.md', "does not mention the `#{a}` agent") unless readme.include?("`#{a}`") }
  SKILLS.each { |s| err('README.md', "does not mention the `#{s}` skill") unless readme.include?("`#{s}`") }
else
  err('README.md', 'file is missing')
end

# --- one name, one state directory, one set of scripts -------------------

plugin_name = begin
  JSON.parse(File.read(path('.claude-plugin/plugin.json')))['name'].to_s
rescue Errno::ENOENT, JSON::ParserError
  err('.claude-plugin/plugin.json', 'missing or invalid')
  ''
end

# Run state lives in .<plugin name>/ so copies of the plugin do not collide.
%w[commands/dev.md engine/engine.yaml scripts/session-start.sh README.md].each do |rel|
  next unless File.exist?(path(rel))

  File.read(path(rel)).scan(%r{(?<![\w/~])\.([a-z][a-z0-9-]*)/(?:runs|specs)\b}).flatten.uniq.each do |dir|
    err(rel, "keeps run state in `.#{dir}/`, but the plugin is named `#{plugin_name}`") unless dir == plugin_name
  end
end

scripts = names_in('scripts', '*')
if File.exist?(path('README.md'))
  scripts.each { |s| err('README.md', "does not mention `#{s}`") unless readme.include?("`#{s}`") }
end
own_lint = profiles.dig(plugin_name, 'commands', 'lint').to_s
unless profiles[plugin_name].nil?
  scripts.grep(/\.sh\z/).each do |s|
    err("engine/profiles.yaml (#{plugin_name})", "commands.lint does not check #{s}") unless own_lint.include?(s)
  end
end

stack_rel = 'scripts/stack.sh'
if File.exist?(path(stack_rel))
  core = File.read(path(stack_rel))[/^CORE="(.*?)"/m, 1].to_s.split
  err(stack_rel, 'CORE is empty') if core.empty?
  core.each { |c| err(stack_rel, "CORE lists #{c}, which does not exist") unless File.exist?(path(c)) }
end

command_rel = 'commands/dev.md'
if File.exist?(path(command_rel))
  command = File.read(path(command_rel))
  STEP_TYPES.each_key { |t| err(command_rel, "does not say how to run a `#{t}` step") unless command.include?("**#{t}**") }
  hint = (frontmatter(command_rel) || {})['argument-hint'].to_s
  %w[list init doctor drift resume].each do |mode|
    err(command_rel, "argument-hint does not offer `#{mode}`") unless hint.include?(mode)
    err(command_rel, "does not say what `#{mode}` does") unless command =~ /^- \*\*[^:\n]*`#{mode}\b/
    err('README.md', "does not list `/dev #{mode}`") if File.exist?(path('README.md')) && !readme.include?("`/dev #{mode}")
  end
else
  err(command_rel, 'file is missing')
end

# --- result ---------------------------------------------------------------

if ERRORS.empty?
  puts "dev-engine: valid (#{WORKFLOWS.size} workflows, #{AGENTS.size} agents, #{SKILLS.size} skills, " \
       "#{profiles.size} profiles, #{TEMPLATES.size} templates)"
else
  puts ERRORS
  puts "\n#{ERRORS.size} problem(s)"
  exit 1
end
