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
#
# From a shell: `ruby config.rb trusted <repo>` (exit 0 if trusted) and
# `ruby config.rb trust <repo>` (record the profile's current digest).

require 'yaml'
require 'date'
require 'set'
require 'digest'
require 'fileutils'

module DevEngineConfig
  PROFILE_REL = '.claude/dev-engine.yaml'
  LEDGER_ENV = 'DEV_ENGINE_LEDGER'
  LEDGER_DEFAULT = '~/.config/dev-engine/ledger.yaml'
  TRUST_DEFAULT = '~/.config/dev-engine/trusted.yaml'
  # Shape of a run id (`run_log.run_id` in engine.yaml) and a conservative branch name.
  RUN_ID = /\A\d{8}-\d{4}-[a-z][a-z0-9]*(-[a-z0-9]+)*\z/.freeze
  BRANCH = %r{\A[A-Za-z0-9][A-Za-z0-9._/-]{0,99}\z}.freeze
  PROFILE_KEYS = %w[name description base_branch forge commands commit_hook workspace].freeze
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

  def profile_digest(path)
    Digest::SHA256.file(path).hexdigest
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

  # True only if the profile file exists and is byte-for-byte what was approved.
  def trusted?(repo)
    path = profile_path(repo)
    return false unless File.file?(path)

    trust_records[trust_key(repo)] == profile_digest(path)
  rescue SystemCallError
    false
  end

  # Record the profile's current contents as approved.
  def trust!(repo)
    records = trust_records.merge(trust_key(repo) => profile_digest(profile_path(repo)))
    FileUtils.mkdir_p(File.dirname(trust_path))
    File.write(trust_path, YAML.dump(records))
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

  # Problems with one profile, as messages without the file name.
  def profile_errors(prof, commands, forges)
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
    errors
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

if $PROGRAM_NAME == __FILE__
  cmd, repo = ARGV
  repo ||= DevEngineConfig.repo_root
  abort 'usage: config.rb trust|trusted [repo]' unless %w[trust trusted].include?(cmd) && repo
  if cmd == 'trusted'
    exit(DevEngineConfig.trusted?(repo) ? 0 : 1)
  else
    abort "no profile at #{DevEngineConfig.profile_path(repo)}" unless File.file?(DevEngineConfig.profile_path(repo))
    DevEngineConfig.trust!(repo)
    puts "trusted #{DevEngineConfig.trust_key(repo)}"
  end
end
