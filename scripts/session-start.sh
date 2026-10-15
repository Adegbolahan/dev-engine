#!/usr/bin/env bash
# SessionStart hook. In a repo that matches a profile, prints a short note so
# the session knows /dev is set up here. Silent everywhere else, and silent on
# any error: a start-of-session note must never block a session.

root="$(cd "$(dirname "$0")/.." && pwd)"
repo="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
command -v ruby >/dev/null 2>&1 || exit 0
remote="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"

ruby -ryaml - "$root/engine/profiles.yaml" "$repo" "$remote" "$root" 2>/dev/null <<'RUBY' || true
profiles_path, repo, remote, = ARGV
profiles = (YAML.safe_load(File.read(profiles_path)) || {})['profiles'] || {}
name, profile = profiles.find do |_, p|
  m = p['match'] || {}
  next false if m.empty?
  (m['remote'].nil? || remote =~ Regexp.new(m['remote'])) &&
    (m['files'] || []).all? { |f| File.exist?(File.join(repo, f)) }
end
exit 0 unless name
commands = (profile['commands'] || {}).reject { |_, v| v.nil? }.keys.join(', ')
puts "dev-engine: this repo matches the `#{name}` profile (base branch #{profile['base_branch']}; commands: #{commands})."
if profile['workspace'].is_a?(Hash) && profile['workspace']['create']
  create = profile['workspace']['create'].to_s.gsub('{plugin}', ARGV[3].to_s)
  puts "Make code changes in an isolated workspace, not in this checkout: `#{create}` ({name} is a short name for the work, {repos} the repo directories it touches)."
end
puts 'Run `/dev-engine:dev list` for workflows, `/dev-engine:dev <workflow> <args>` to start one, `/dev-engine:dev resume` to continue a run.'
waiting = Dir.glob(File.join(repo, '.dev-engine/runs/*.yaml')).select do |f|
  %w[running waiting].include?((YAML.safe_load(File.read(f)) || {})['status']) rescue false
end
puts "Unfinished runs: #{waiting.map { |f| File.basename(f, '.yaml') }.join(', ')}." unless waiting.empty?
RUBY
exit 0
