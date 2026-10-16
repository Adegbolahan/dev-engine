# frozen_string_literal: true

# Where a person's dev-engine data lives, and what it must look like. The
# plugin ships none of it: each repo keeps its own profile, and the ledger
# sits in the person's config directory. Every script finds both through here.
#
#   require_relative 'config'
#   DevEngineConfig.profile_path(repo)   <repo>/.claude/dev-engine.yaml
#   DevEngineConfig.ledger_path          $DEV_ENGINE_LEDGER or ~/.config/dev-engine/ledger.yaml
#   DevEngineConfig.trust_path           ~/.config/dev-engine/trusted.yaml
#   DevEngineConfig.trusted?(repo)       true if the person approved this repo's profile as it is now
#   DevEngineConfig.trust!(repo)         record the profile as it is now as approved
#   DevEngineConfig.snapshot_dir(id, name)  ~/.config/dev-engine/runs/<run-id>[/<name>], outside every repo
#   DevEngineConfig.snapshot!(repo, id)  copy the approved profile and listed skills into that run's snapshot
#   DevEngineConfig.snapshot_rm!(id)     remove that run's snapshot directory
#   DevEngineConfig.profile_errors(...)  and ledger_errors(...): schema problems, as messages
#
# From a shell: `ruby config.rb trusted <repo>` (exit 0 if trusted),
# `ruby config.rb trust <repo>` (record the profile's current digest) and
# `ruby config.rb snapshot <repo> <run-id>` (copy the trusted profile and
# listed skills into the run's snapshot, under the profile's `name`; refuses
# if the repo is not trusted), `ruby config.rb snapshot-dir <run-id> [<name>]`
# (print the path), `ruby config.rb snapshot-rm <run-id>` (remove the run's
# snapshot directory) and `ruby config.rb check <repo>` (schema-check a
# repo's profile alone; exit 1 and list the problems if it has any). The
# snapshot commands take ids, never paths: the path is built here and must
# stay inside ~/.config/dev-engine/runs.

require 'yaml'
require 'date'
require 'set'
require 'digest'
require 'fileutils'
require 'tmpdir'

module DevEngineConfig
  PROFILE_REL = '.claude/dev-engine.yaml'
  LEDGER_ENV = 'DEV_ENGINE_LEDGER'
  LEDGER_DEFAULT = '~/.config/dev-engine/ledger.yaml'
  TRUST_DEFAULT = '~/.config/dev-engine/trusted.yaml'
  RUNS_DEFAULT = '~/.config/dev-engine/runs'
  # Shape of a run id (`run_log.run_id` in engine.yaml) and a conservative branch name.
  RUN_ID = /\A\d{8}-\d{4}-[a-z][a-z0-9]*(-[a-z0-9]+)*\z/.freeze
  BRANCH = %r{\A[A-Za-z0-9][A-Za-z0-9._/-]{0,99}\z}.freeze
  PROFILE_KEYS = %w[name description base_branch forge commands commit_hook workspace skills publish lessons].freeze
  EDGE_KINDS = %w[depends_on calls publishes_to deploys_to shares_schema_with].freeze
  NAME = /\A[a-z][a-z0-9]*(-[a-z0-9]+)*\z/.freeze

  module_function

  def ledger_path
    env = ENV[LEDGER_ENV].to_s
    File.expand_path(env.empty? ? LEDGER_DEFAULT : env)
  end

  def profile_path(repo)
    File.join(repo, PROFILE_REL)
  end

  # The person's record of which repos' profiles they approved: repo path to
  # the SHA-256 of the profile file's contents. User-level, never in a repo.
  def trust_path
    File.expand_path(TRUST_DEFAULT)
  end

  # `path` with its existing part resolved through symlinks.
  def real_prefix(path)
    rest = []
    cur = File.expand_path(path)
    until File.exist?(cur)
      rest.unshift(File.basename(cur))
      cur = File.dirname(cur)
    end
    File.join(File.realpath(cur), *rest)
  end

  # Where a run's snapshots live: one directory per run, outside every repo,
  # and with a name, the directory of that repo's copy. The run id and name
  # are checked here, and the path is refused if resolving symlinks would take
  # it out of the runs directory.
  def snapshot_dir(run_id, name = nil)
    raise TypeError, "run id `#{run_id}` is not a run id" unless run_id.is_a?(String) && run_id.match?(RUN_ID)
    raise TypeError, "`#{name}` is not a repo name" unless name.nil? || (name.is_a?(String) && name.match?(NAME))

    root = File.expand_path(RUNS_DEFAULT)
    root_real = File.join(real_prefix(File.dirname(root)), File.basename(root))
    path = File.join(root, run_id)
    path = File.join(path, name) if name
    unless real_prefix(root) == root_real && real_prefix(path).start_with?("#{root_real}/")
      raise TypeError, "#{path} would leave #{root}"
    end

    path
  end

  # The repo's profile as a parsed value, or nil if it is not valid YAML.
  def parse_profile(repo)
    YAML.safe_load(File.binread(profile_path(repo)), permitted_classes: [Date])
  rescue Psych::Exception
    nil
  end

  # The profile's path relative to the repo, then the relative path of each
  # skill it lists under `skills`, in list order; nil if a listed skill is
  # missing or a name is not a skill name. Digest and snapshot both use it,
  # so a snapshot holds exactly the files an approval covered.
  def profile_files(repo)
    prof = parse_profile(repo)
    skills = prof.is_a?(Hash) ? prof['skills'] : nil
    files = [PROFILE_REL]
    return files unless skills.is_a?(Array)

    skills.each do |s|
      return nil unless s.is_a?(String) && s =~ NAME

      rel = ".claude/skills/#{s}/SKILL.md"
      return nil unless File.file?(File.join(repo, rel))

      files << rel
    end
    files
  end

  # SHA-256 over the profile's bytes, then, for each skill the profile lists
  # under `skills`, in list order, that skill's path and bytes. A listed skill
  # that is missing, or a name that is not a skill name, makes it nil, so the
  # repo is untrusted. Repo stack skills are instructions the run loads, so
  # approval has to cover them as well as the profile's commands.
  def profile_digest(path)
    repo = File.dirname(File.dirname(path))
    files = profile_files(repo)
    return nil if files.nil?

    digest = Digest::SHA256.new
    digest << File.binread(path)
    files.drop(1).each { |rel| digest << "\0#{rel}\0" << File.binread(File.join(repo, rel)) }
    digest.hexdigest
  end

  def trust_key(repo)
    File.realpath(repo)
  rescue SystemCallError
    File.expand_path(repo)
  end

  def trust_records
    rec = YAML.safe_load(File.read(trust_path))
    rec.is_a?(Hash) ? rec : {}
  rescue SystemCallError, Psych::Exception
    {}
  end

  # True only if the profile file and every skill it lists are byte-for-byte
  # what was approved.
  def trusted?(repo)
    path = profile_path(repo)
    return false unless File.file?(path)

    digest = profile_digest(path)
    !digest.nil? && trust_records[trust_key(repo)] == digest
  rescue SystemCallError
    false
  end

  # Record the profile's current contents as approved. Holds a lock while it
  # reads and rewrites the file, and replaces it in one rename, so two
  # sessions cannot lose each other's approvals. Raises rather than replace a
  # trust file it cannot read, which would drop every other approval.
  def trust!(repo)
    FileUtils.mkdir_p(File.dirname(trust_path))
    File.open("#{trust_path}.lock", File::RDWR | File::CREAT, 0o600) do |lock|
      lock.flock(File::LOCK_EX)
      records = File.exist?(trust_path) ? YAML.safe_load(File.read(trust_path)) : {}
      records ||= {}
      raise TypeError, "#{trust_path} is not a mapping; fix or remove it" unless records.is_a?(Hash)

      digest = profile_digest(profile_path(repo))
      raise TypeError, 'a skill the profile lists is missing; fix the profile first' if digest.nil?

      records[trust_key(repo)] = digest
      tmp = "#{trust_path}.#{Process.pid}.tmp"
      File.write(tmp, YAML.dump(records))
      File.rename(tmp, trust_path)
    end
  end

  # Copy the profile and each listed skill of a trusted repo into the run's
  # snapshot, <runs>/<run-id>/<profile name>, with the same relative layout.
  # Refuses an untrusted repo. It copies into a fresh sibling directory and
  # checks that the copy digests to the approved value, so the snapshot is
  # exactly what was approved even if the tree changes while copying; only
  # then does it replace any earlier snapshot of that repo, by rename. On a
  # failure it removes the directory it made and nothing else.
  def snapshot!(repo, run_id)
    raise TypeError, "#{repo} is not trusted; trust it first" unless trusted?(repo)

    files = profile_files(repo)
    raise TypeError, 'a skill the profile lists is missing; fix the profile first' if files.nil?

    prof = parse_profile(repo)
    raise TypeError, 'the profile has no `name`' unless prof.is_a?(Hash) && prof['name']

    dest = snapshot_dir(run_id, prof['name'])
    run_dir = File.dirname(dest)
    FileUtils.mkdir_p(run_dir)
    snapshot_dir(run_id, prof['name']) # again, now that the run directory exists
    tmp = Dir.mktmpdir(".#{prof['name']}.", run_dir)
    old = nil
    begin
      files.each do |rel|
        FileUtils.mkdir_p(File.dirname(File.join(tmp, rel)))
        FileUtils.cp(File.join(repo, rel), File.join(tmp, rel))
      end
      unless profile_digest(profile_path(tmp)) == trust_records[trust_key(repo)]
        raise TypeError, "#{repo} changed while it was copied; nothing kept"
      end

      if File.exist?(dest) || File.symlink?(dest)
        old = "#{tmp}.old"
        File.rename(dest, old)
      end
      begin
        File.rename(tmp, dest)
      rescue SystemCallError
        # Clear `old` first, so a failed restore leaves it for the person to recover.
        saved = old
        old = nil
        File.rename(saved, dest) if saved
        raise
      end
      dest
    ensure
      FileUtils.rm_rf(tmp)
      FileUtils.rm_rf(old) if old
    end
  end

  # Remove one run's snapshot directory, and nothing outside it.
  def snapshot_rm!(run_id)
    FileUtils.rm_rf(snapshot_dir(run_id))
  end

  # The top of the git repo holding dir, or nil outside one.
  def repo_root(dir = Dir.pwd)
    top = IO.popen(['git', '-C', dir, 'rev-parse', '--show-toplevel'], err: File::NULL, &:read).to_s.strip
    top.empty? ? nil : top
  rescue SystemCallError
    nil
  end

  # Raises Errno::ENOENT or Psych::Exception; callers decide what each means.
  def load(path)
    YAML.safe_load(File.read(path), permitted_classes: [Date])
  end

  # Problems with one profile, as messages without the file name. With `repo`,
  # each name under `skills` must be a skill in that repo's .claude/skills/.
  def profile_errors(prof, commands, forges, publish_modes, repo: nil)
    return ['must be a mapping of profile fields'] unless prof.is_a?(Hash)

    errors = []
    errors << '`name` must be kebab-case, for example my-service' unless prof['name'].is_a?(String) && prof['name'] =~ NAME
    errors << 'missing `base_branch`' unless prof['base_branch'].is_a?(String)
    errors << "`forge` must be one of: #{forges.join(', ')}" unless forges.include?(prof['forge'])
    (prof.keys - PROFILE_KEYS).each { |k| errors << "`#{k}` is not a field of a profile" }
    cmds = prof['commands']
    if cmds.is_a?(Hash)
      (commands - cmds.keys).each { |k| errors << "commands.#{k} is missing (use null if it does not apply)" }
      (cmds.keys - commands).each { |k| errors << "commands.#{k} is not a key the engine knows" }
    else
      errors << 'missing `commands`'
    end
    if prof.key?('commit_hook')
      hook = prof['commit_hook']
      if hook.is_a?(Array)
        (hook - commands).each { |k| errors << "commit_hook names `#{k}`, which is not a command key" }
      else
        errors << '`commit_hook` must be a list of command keys'
      end
    end
    if prof.key?('workspace')
      ws = prof['workspace']
      if ws.is_a?(Hash) && (ws.keys - %w[create remove path]).empty? && %w[create remove path].all? { |k| ws[k].is_a?(String) }
        %w[create remove path].each { |k| errors << "workspace.#{k} must use {name}" unless ws[k].include?('{name}') }
      else
        errors << '`workspace` needs `create`, `remove` and `path`, and nothing else'
      end
    end
    if prof.key?('skills')
      skills = prof['skills']
      if skills.is_a?(Array) && skills.all? { |s| s.is_a?(String) && s =~ NAME }
        skills.each do |s|
          next unless repo && !File.file?(File.join(repo, '.claude', 'skills', s, 'SKILL.md'))

          errors << "skills names `#{s}`, which has no .claude/skills/#{s}/SKILL.md in the repo"
        end
      else
        errors << '`skills` must be a list of kebab-case skill names'
      end
    end
    if prof.key?('publish') && !publish_modes.include?(prof['publish'])
      errors << "`publish` must be one of: #{publish_modes.join(', ')}"
    end
    if prof.key?('lessons')
      problem = lessons_path_problem(prof['lessons'])
      errors << "`lessons` #{problem}" if problem
    end
    errors
  end

  # Why a `lessons` path is refused, or nil. It must be exactly `../<file>`:
  # one file beside the repo, outside it, so a run never writes into the
  # repo's hooks, CI, settings or this engine's data after publishing.
  def lessons_path_problem(path)
    unless path.is_a?(String) && path.match?(%r{\A\.\./[^/]+\z})
      return 'must be `../<file>`, a single file beside the repo (not inside it, not deeper)'
    end

    name = path.delete_prefix('../')
    return 'must not name a hidden file' if name.start_with?('.')
    return 'must end in .md or .txt' unless name.match?(/\.(md|txt)\z/i)

    nil
  end

  # Problems with the ledger, as messages without the file name.
  def ledger_errors(ledger)
    return ['must be a mapping with `surveyed`, `repos`, `packages`, `environments` and `edges`'] unless ledger.is_a?(Hash)

    errors = []
    errors << 'missing `surveyed` date' unless ledger['surveyed']
    ids = Set.new
    { 'repos' => 'repo', 'packages' => 'package', 'environments' => 'env' }.each do |section, kind|
      unless ledger[section].is_a?(Array)
        errors << "`#{section}` must be a list (it may be empty)"
        next
      end
      ledger[section].each do |node|
        id = node.is_a?(Hash) ? node['id'].to_s : ''
        errors << "#{section}: id `#{id}` must start with `#{kind}:`" unless id.start_with?("#{kind}:")
        errors << "duplicate id `#{id}`" unless ids.add?(id)
      end
    end
    Array(ledger['packages']).each do |pkg|
      next unless pkg.is_a?(Hash)

      errors << "package `#{pkg['id']}` names repo `#{pkg['repo']}`, which is not in the ledger" unless ids.include?(pkg['repo'].to_s)
    end
    if ledger['edges'].is_a?(Array)
      ledger['edges'].each do |edge|
        edge = {} unless edge.is_a?(Hash)
        %w[from to].each do |side|
          errors << "edge #{side} `#{edge[side]}` is not a node in the ledger" unless ids.include?(edge[side].to_s)
        end
        errors << "edge kind `#{edge['kind']}` must be one of: #{EDGE_KINDS.join(', ')}" unless EDGE_KINDS.include?(edge['kind'])
        errors << "edge #{edge['from']} -> #{edge['to']} has no `evidence`" unless edge['evidence']
      end
    else
      errors << '`edges` must be a list (it may be empty)'
    end
    errors
  end

  # Names of the ledger's repos, without the `repo:` prefix.
  def ledger_repo_names(ledger)
    return [] unless ledger.is_a?(Hash)

    Array(ledger['repos']).select { |r| r.is_a?(Hash) }.map { |r| r['id'].to_s.sub(/\Arepo:/, '') }
  end
end

def cli_usage
  'usage: config.rb trust [<repo>] | trusted [<repo>] | check <repo> | snapshot <repo> <run-id> | ' \
    'snapshot-dir <run-id> [<name>] | snapshot-rm <run-id>'
end

def cli_trusted(args)
  repo = args[0] || DevEngineConfig.repo_root
  abort cli_usage unless repo
  exit(DevEngineConfig.trusted?(repo) ? 0 : 1)
end

def cli_trust(args)
  repo = args[0] || DevEngineConfig.repo_root
  abort cli_usage unless repo
  abort "no profile at #{DevEngineConfig.profile_path(repo)}" unless File.file?(DevEngineConfig.profile_path(repo))
  begin
    DevEngineConfig.trust!(repo)
  rescue Psych::Exception, TypeError, SystemCallError => e
    abort "cannot record trust: #{e.message}"
  end
  puts "trusted #{DevEngineConfig.trust_key(repo)}"
end

def cli_snapshot(args)
  repo, run_id = args
  abort cli_usage unless repo && run_id
  begin
    puts "snapshot #{DevEngineConfig.snapshot!(repo, run_id)}"
  rescue TypeError, SystemCallError, Psych::Exception => e
    abort "cannot snapshot: #{e.message}"
  end
end

def cli_snapshot_rm(args)
  run_id = args[0]
  abort cli_usage unless run_id
  begin
    DevEngineConfig.snapshot_rm!(run_id)
    puts "removed #{DevEngineConfig.snapshot_dir(run_id)}"
  rescue TypeError, SystemCallError => e
    abort "cannot snapshot rm: #{e.message}"
  end
end

def cli_snapshot_dir(args)
  run_id, name = args
  abort cli_usage unless run_id
  begin
    puts DevEngineConfig.snapshot_dir(run_id, name)
  rescue TypeError => e
    abort "cannot resolve: #{e.message}"
  end
end

def cli_check(args)
  repo = args[0]
  abort cli_usage unless repo
  path = DevEngineConfig.profile_path(repo)
  abort "no profile at #{path}" unless File.file?(path)
  engine = YAML.safe_load(File.read(File.expand_path('../engine/engine.yaml', __dir__)))
  begin
    prof = DevEngineConfig.load(path)
  rescue Psych::Exception => e
    abort "#{path} is not valid YAML: #{e.message}"
  end
  problems = DevEngineConfig.profile_errors(prof, engine['commands'] || [], engine['forges'] || [],
                                            engine['publish_modes'] || [], repo: repo)
  problems.each { |m| warn "#{DevEngineConfig::PROFILE_REL}: #{m}" }
  abort "#{problems.size} problem(s) in #{path}" unless problems.empty?
  puts "profile ok #{path}"
end

if $PROGRAM_NAME == __FILE__
  cmd, *args = ARGV
  case cmd
  when 'trust' then cli_trust(args)
  when 'trusted' then cli_trusted(args)
  when 'check' then cli_check(args)
  when 'snapshot' then cli_snapshot(args)
  when 'snapshot-dir' then cli_snapshot_dir(args)
  when 'snapshot-rm' then cli_snapshot_rm(args)
  else abort cli_usage
  end
end
