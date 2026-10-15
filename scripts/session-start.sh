#!/usr/bin/env bash
# SessionStart hook. In a repo with a profile (.claude/dev-engine.yaml), prints
# a short note so the session knows /dev is set up here. Silent everywhere
# else, and silent on any error: a start-of-session note must never block a
# session.

root="$(cd "$(dirname "$0")/.." && pwd)"
repo="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
command -v ruby >/dev/null 2>&1 || exit 0

ruby -r "$root/scripts/config.rb" - "$repo" "$root" 2>/dev/null <<'RUBY' || true
repo, root = ARGV
C = DevEngineConfig
path = C.profile_path(repo)
exit 0 unless File.exist?(path)
profile = C.load(path)
exit 0 unless profile.is_a?(Hash) && profile['name']
# A repo supplies its own profile, so print nothing from it that is not
# checked against a strict pattern, and never a command string.
puts 'Run `/dev-engine:dev list` for workflows, `/dev-engine:dev <workflow> <args>` to start one, `/dev-engine:dev resume` to continue a run.'
if C.trusted?(repo)
  name = profile['name'].to_s
  exit 0 unless name =~ C::NAME
  base = profile['base_branch'].to_s
  base = 'unknown' unless base =~ C::BRANCH
  keys = YAML.safe_load(File.read(File.join(root, 'engine/engine.yaml')))['commands']
  commands = (profile['commands'].is_a?(Hash) ? profile['commands'] : {}).reject { |_, v| v.nil? }.keys & keys
  puts "dev-engine: this repo matches the `#{name}` profile (base branch #{base}; commands: #{commands.join(', ')})."
  puts 'This profile defines an isolated workspace for code changes: see .claude/dev-engine.yaml and make changes there, not in this checkout.' if profile['workspace'].is_a?(Hash)
else
  label = profile['name'].to_s =~ C::NAME ? "the `#{profile['name']}` profile" : 'a dev-engine profile'
  puts "dev-engine: this repo has #{label} (.claude/dev-engine.yaml), not yet trusted. /dev will show its commands and ask before running any."
end
waiting = Dir.glob(File.join(repo, '.dev-engine/runs/*.yaml')).select do |f|
  File.basename(f, '.yaml') =~ C::RUN_ID &&
    (%w[running waiting].include?((YAML.safe_load(File.read(f)) || {})['status']) rescue false)
end
puts "Unfinished runs: #{waiting.map { |f| File.basename(f, '.yaml') }.join(', ')}." unless waiting.empty?
RUBY
exit 0
