#!/usr/bin/env ruby
# frozen_string_literal: true

# Compares what the user ledger and each repo's profile say with the repos on
# this machine, and checks the paths the repos' stack skills cite. Prints one line per
# check and exits 1 if anything has drifted. It reads only; it never fetches
# unless asked and never changes a file.
#
#   ruby scripts/drift.rb           compare against the local checkouts
#   ruby scripts/drift.rb --fetch   run `git fetch` in each repo first
#
# It cannot check prose: a rule or a version a skill states in words is only
# as current as the last person who read it against the source.

require 'yaml'
require 'json'
require 'date'
require 'set'
require_relative 'config'

ROOT = File.expand_path('..', __dir__)
FETCH = ARGV.include?('--fetch')

$drift = 0
def ok(msg)
  puts "  ok     #{msg}"
end

def note(msg)
  puts "  note   #{msg}"
end

def drift(msg)
  $drift += 1
  puts "  DRIFT  #{msg}"
end

def git(dir, *args)
  IO.popen(['git', '-C', dir, *args], err: File::NULL, &:read).to_s.strip
end

def manifest(dir)
  file = File.join(dir, 'package.json')
  File.exist?(file) ? JSON.parse(File.read(file)) : nil
rescue JSON::ParserError
  nil
end

ENGINE = YAML.safe_load(File.read(File.join(ROOT, 'engine/engine.yaml')))

# A repo's profile; nil if it has none, false if it is broken (already drift).
# Other repos' profiles are not checked by validate.rb, so check their shape
# here before anything below reads them.
def profile_in(name, dir)
  prof = DevEngineConfig.load(DevEngineConfig.profile_path(dir))
  problems = DevEngineConfig.profile_errors(prof, ENGINE['commands'] || [], ENGINE['forges'] || [],
                                            ENGINE['publish_modes'] || [], repo: dir)
  return prof if problems.empty?

  problems.each { |p| drift("#{name}: #{DevEngineConfig::PROFILE_REL}: #{p}") }
  false
rescue Errno::ENOENT
  nil
rescue Psych::Exception => e
  drift("#{name}: #{DevEngineConfig::PROFILE_REL} is not valid YAML: #{e.message}")
  false
rescue SystemCallError => e
  drift("#{name}: #{DevEngineConfig::PROFILE_REL} cannot be read: #{e.message}")
  false
end

ledger_path = DevEngineConfig.ledger_path
ledger = begin
  DevEngineConfig.load(ledger_path) || {}
rescue Errno::ENOENT
  nil
rescue Psych::Exception, SystemCallError => e
  puts "  DRIFT  the ledger at #{ledger_path} cannot be read: #{e.message}"
  exit 1
end
unless ledger.nil? || ledger.is_a?(Hash)
  puts "  DRIFT  the ledger at #{ledger_path} is not a mapping; run validate.rb for details"
  exit 1
end

# With no ledger there is one repo to check: the current one, if set up.
have_ledger = !ledger.nil?
unless have_ledger
  note("no ledger at #{ledger_path} (set #{DevEngineConfig::LEDGER_ENV} to use another); checking only the current repo")
  here = DevEngineConfig.repo_root
  own = here && profile_in(File.basename(here), here)
  if own && !own['name'].is_a?(String)
    drift("#{File.basename(here)}: #{DevEngineConfig::PROFILE_REL} has no `name`")
    own = nil
  end
  repos = own ? [{ 'id' => "repo:#{own['name']}", 'path_hint' => here }] : []
  ledger = { 'repos' => repos }
end
repos = Array(ledger['repos'])
packages = Array(ledger['packages'])
edges = Array(ledger['edges'])

# Where each ledger repo lives on this machine.
paths = {}
repos.each do |r|
  name = r['id'].to_s.sub('repo:', '')
  dir = File.expand_path(r['path_hint'].to_s)
  paths[name] = dir if File.directory?(dir)
end

puts 'Repos'
repos.each do |r|
  name = r['id'].to_s.sub('repo:', '')
  dir = paths[name]
  next drift("#{name}: path_hint #{r['path_hint']} is not on this machine") unless dir

  top = git(dir, 'rev-parse', '--show-toplevel')
  next note("#{name}: #{r['path_hint']} is not a git repo, so its profile cannot be checked") if top.empty?

  git(dir, 'fetch', '--quiet') if FETCH
  profile = profile_in(name, dir)
  next if profile == false
  next drift("#{name}: in the ledger but #{r['path_hint']} has no #{DevEngineConfig::PROFILE_REL}") unless profile

  problems = []
  problems << "its profile is named `#{profile['name']}`, not `#{name}` as in the ledger" unless profile['name'] == name
  head = git(dir, 'symbolic-ref', '--short', 'refs/remotes/origin/HEAD').sub('origin/', '')
  problems << "base_branch is #{profile['base_branch']} but the remote's default is #{head}" unless head.empty? || head == profile['base_branch']

  scripts = (manifest(dir) || {})['scripts'] || {}
  (profile['commands'] || {}).each do |key, command|
    next unless command.to_s =~ /\A(?:npm|pnpm|yarn|bun)(?: run)? ([\w:.-]+)\z/

    problems << "`#{key}: #{command}` names a script that package.json does not define" unless scripts.key?(Regexp.last_match(1))
  end
  unused = %w[typecheck lint test build].select { |k| profile.dig('commands', k).nil? && scripts.key?(k) }

  problems.empty? ? ok(name) : problems.each { |p| drift("#{name}: #{p}") }
  note("#{name}: package.json has a `#{unused.join('`, `')}` script the profile leaves null") unless unused.empty?
  unless head.empty?
    behind = git(dir, 'rev-list', '--count', "HEAD..origin/#{head}").to_i
    note("#{name}: checkout is #{behind} commit(s) behind origin/#{head}; this run compared the checkout") if behind.positive?
  end
end

# Git repos nested one level inside a ledger repo that the ledger does not list.
known = paths.values.to_set
paths.each_value do |dir|
  Dir.children(dir).sort.each do |child|
    sub = File.join(dir, child)
    next unless File.directory?(sub) && File.exist?(File.join(sub, '.git')) && !known.include?(sub)

    drift("#{sub} is a git repo no ledger entry points to")
  end
end

puts 'Packages'
node_dir = {}
paths.each { |name, dir| node_dir["repo:#{name}"] = dir }
packages.each do |p|
  base = paths[p['repo'].to_s.sub('repo:', '')]
  next drift("#{p['id']}: its repo #{p['repo']} is not on this machine") unless base

  dir = File.join(base, p['path'].to_s)
  if File.directory?(dir)
    node_dir[p['id']] = dir
    ok(p['id'])
  else
    drift("#{p['id']}: path #{p['path']} does not exist in #{p['repo']}")
  end
end
# Sibling packages on disk that the ledger does not list.
packages.group_by { |p| [p['repo'], File.dirname(p['path'].to_s)] }.each do |(repo, parent), listed|
  base = paths[repo.to_s.sub('repo:', '')]
  next unless base

  parent_dir = File.expand_path(parent, base)
  next unless File.directory?(parent_dir)

  have = listed.map { |p| File.basename(p['path'].to_s) }
  Dir.children(parent_dir).sort.each do |child|
    sibling = File.join(parent_dir, child)
    # A dot-directory or another repo's checkout is not a package of this repo.
    next if child.start_with?('.') || known.include?(sibling) || File.exist?(File.join(sibling, '.git'))
    next if have.include?(child) || !File.exist?(File.join(sibling, 'package.json'))

    drift("#{File.join(parent_dir, child)} is a package the ledger does not list")
  end
end

puts 'Dependency edges'
by_npm_name = {}
packages.each do |p|
  m = node_dir[p['id']] && manifest(node_dir[p['id']])
  by_npm_name[m['name']] = p['id'] if m && m['name']
end
node_dir.sort.each do |id, dir|
  m = manifest(dir)
  next unless m

  deps = %w[dependencies devDependencies peerDependencies optionalDependencies].flat_map { |k| (m[k] || {}).keys }
  actual = deps.map { |d| by_npm_name[d] }.compact.uniq.reject { |t| t == id }.sort
  listed = edges.select { |e| e['from'] == id && e['kind'] == 'depends_on' && e['to'].to_s.start_with?('package:') }
                .map { |e| e['to'] }.uniq.sort
  (actual - listed).each { |t| drift("#{id} depends on #{t} in package.json, but the ledger has no such edge") }
  (listed - actual).each { |t| drift("the ledger says #{id} depends on #{t}, but package.json does not") }
  ok("#{id} (#{actual.size})") if actual == listed
end

puts 'Edge evidence'
missing = edges.reject do |e|
  profile, rel = e['evidence'].to_s.split(':', 2)
  paths[profile] && rel && File.exist?(File.join(paths[profile], rel))
end
missing.each { |e| drift("#{e['from']} -> #{e['to']}: evidence #{e['evidence']} does not exist") }
ok("#{edges.size} edges, every evidence path exists") if missing.empty?

puts 'Paths cited by skills and workflows'
search_roots = paths.values + [ROOT]
cited = Hash.new { |h, k| h[k] = [] }
# A skill may cite its own bundled files (references/, scripts/) relative to its directory.
cited_from = Hash.new { |h, k| h[k] = [] }
# Each repo's own stack skills, which describe that repo's files, and the
# workflows. The plugin's skills are generic: a path they cite is a
# convention for any repo, not a claim that some repo has it.
sources = Dir.glob(File.join(ROOT, 'workflows/*.yaml'))
paths.each_value { |dir| sources += Dir.glob(File.join(dir, '.claude/skills/*/SKILL.md')) }
sources.uniq.sort.each do |file|
  workflow = file.end_with?('.yaml')
  File.read(file).scan(/`([^`\s]+)`/).flatten.each do |token|
    # A workflow also names files its steps create; only the guides it tells a run to read must exist.
    next if workflow && token !~ %r{skills/[^/]+/SKILL\.md\z}
    next if token =~ /[<>*$:{}|=()\[\]]/ || token.start_with?('-', '@', '/', 'http')
    next unless token.include?('/') && token =~ /[A-Za-z]/
    # A cited path is anything that names a file with an extension, or a directory with a trailing slash.
    next unless token.end_with?('/') || File.basename(token) =~ /\.[A-Za-z0-9]+\z/

    key = token.sub(%r{\A(\.\./|\./)+}, '').chomp('/')
    cited[key] << File.basename(File.dirname(file)) + '/' + File.basename(file)
    cited_from[key] << File.dirname(file) unless workflow
  end
end
suffix_index = nil
unfound = cited.keys.sort.reject do |token|
  next true if search_roots.any? { |r| File.exist?(File.join(r, token)) }
  next true if cited_from[token].any? { |dir| File.exist?(File.join(dir, token)) }

  suffix_index ||= paths.values.flat_map do |dir|
    files = git(dir, 'ls-files').split("\n")
    files + files.flat_map { |f| parts = f.split('/'); (1...parts.size).map { |i| parts[0, i].join('/') } }
  end.to_set
  suffix_index.any? { |p| p == token || p.end_with?("/#{token}") }
end
unfound.each { |t| drift("`#{t}` (cited in #{cited[t].uniq.join(', ')}) was not found in any repo") }
ok("#{cited.size} cited paths, all found") if unfound.empty?

puts 'Survey'
surveyed = Date.parse(ledger['surveyed'].to_s) rescue nil
if !have_ledger
  note("no ledger at #{ledger_path}, so there is no survey date")
elsif surveyed
  age = (Date.today - surveyed).to_i
  note("the ledger was surveyed #{age} day(s) ago (#{surveyed}); set `surveyed` after re-checking it") if age > 30
  ok("ledger surveyed #{surveyed}") if age <= 30
else
  drift('the ledger has no readable `surveyed` date')
end

puts
if $drift.zero?
  puts "#{File.basename(ROOT)}: no drift found. Prose rules and versions stated in skills are not checked."
else
  puts "#{File.basename(ROOT)}: #{$drift} drift finding(s)."
  exit 1
end
