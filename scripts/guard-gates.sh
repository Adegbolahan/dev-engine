#!/usr/bin/env bash
# PreToolUse hook. While a run is unfinished in a repo, denies the shell
# commands that leave the machine (git push, opening or merging a merge
# request) unless that run's log records the gate that allows them as approved.
#
# Outside a run it allows everything: it enforces a run's gates, not a policy
# on every push. A workflow with no step that pushes cannot push at all.
#
# The log it reads is written by the session, so this is a tripwire against a
# skipped gate, not protection against a session that falsifies its own log.
#
# Reads the hook JSON on stdin. Prints a deny decision, or nothing to allow.
# Any unexpected error allows: a broken guard must never block a session.

root="$(cd "$(dirname "$0")/.." && pwd)"
command -v ruby >/dev/null 2>&1 || exit 0

ruby -rjson -ryaml -e '
root = ARGV[0]
begin
  input = JSON.parse($stdin.read)
  exit 0 unless input["tool_name"] == "Bash"
  cmd = input.dig("tool_input", "command").to_s
  cwd = input["cwd"].to_s
  cwd = Dir.pwd if cwd.empty?

  push_re = /(?:\A|[\s(])git(?:\s+-[cC]\s+\S+|\s+--[\w-]+(?:=\S+)?)*\s+push(?:\s|\z)/
  mr_re = /(?:\A|[\s(])(?:gh\s+pr|glab\s+mr)\s+(?:create|merge)(?:\s|\z)/
  kinds = []
  dirs = [cwd]
  cmd.split(/&&|\|\||[;|\n]/).each do |seg|
    if seg =~ push_re && seg !~ /--dry-run/
      kinds << "push"
      seg.scan(/\s-C\s+(\S+)/) { |m| dirs << m[0] }
    end
    kinds << "merge_request" if seg =~ mr_re
    dirs << Regexp.last_match(1) if seg =~ /\A\s*cd\s+(\S+)/
  end
  kinds.uniq!
  exit 0 if kinds.empty?

  name = JSON.parse(File.read(File.join(root, ".claude-plugin/plugin.json")))["name"].to_s
  exit 0 if name.empty?

  actions = { "push" => %w[push push_base], "merge_request" => %w[merge_request] }
  gates_for = lambda do |workflow, kind, seen|
    return [] if seen.include?(workflow)
    seen << workflow
    file = File.join(root, "workflows", "#{workflow}.yaml")
    return [] unless File.exist?(file)
    walk = lambda do |steps|
      Array(steps).flat_map do |s|
        found = []
        found << s["gate"].to_s if s["type"] == "vcs" && actions[kind].include?(s["action"])
        found += gates_for.call(s["run"].to_s, kind, seen) if s["type"] == "workflow"
        found + walk.call(s["steps"])
      end
    end
    walk.call((YAML.safe_load(File.read(file)) || {})["steps"])
  end

  approved = lambda do |v|
    v = v["answer"] || v["decision"] || v["status"] if v.is_a?(Hash)
    v.to_s.strip =~ /\Aapprov/i
  end

  deny = lambda do |reason|
    puts JSON.generate("hookSpecificOutput" => { "hookEventName" => "PreToolUse",
                                                 "permissionDecision" => "deny",
                                                 "permissionDecisionReason" => "#{name}: #{reason}" })
    exit 0
  end

  repos = dirs.map do |d|
    d = File.expand_path(d.delete_prefix("\"").delete_suffix("\"").sub(/\A~/, Dir.home), cwd)
    next unless File.directory?(d)
    top = IO.popen(["git", "-C", d, "rev-parse", "--show-toplevel"], err: File::NULL, &:read).to_s.strip
    top.empty? ? nil : top
  end.compact.uniq

  # A run that spans repos leaves a pointer in each other repo: a small file
  # whose `primary` names the real log. Follow it; a pointer whose log is gone
  # is stale and restricts nothing.
  resolve = lambda do |file|
    data = (YAML.safe_load(File.read(file)) rescue :unreadable)
    return [file, data] unless data.is_a?(Hash) && data["primary"]
    primary = File.expand_path(data["primary"].to_s, File.dirname(file))
    return nil unless File.exist?(primary)
    [primary, (YAML.safe_load(File.read(primary)) rescue :unreadable)]
  end

  repos.each do |repo|
    # Every checkout of this repo counts: a run started in one worktree still
    # governs a push made from another.
    trees = IO.popen(["git", "-C", repo, "worktree", "list", "--porcelain"], err: File::NULL, &:read).to_s
              .scan(/^worktree (.+)$/).flatten
    trees = [repo] if trees.empty?
    files = trees.flat_map { |t| Dir.glob(File.join(t, ".#{name}", "runs", "*.yaml")) }.sort_by { |f| File.mtime(f) }.reverse
    found = files.map { |f| resolve.call(f) }.compact.find do |(_, data)|
      data == :unreadable || %w[running waiting].include?(data["status"].to_s)
    end
    next unless found
    log, run = found
    id = File.basename(log, ".yaml")
    deny.call("run #{id} is unfinished here and its log cannot be read (#{log}). Fix or abort the run before this command.") unless run.is_a?(Hash)
    kinds.each do |kind|
      what = kind == "push" ? "push" : "open or merge a merge request"
      needed = gates_for.call(run["workflow"].to_s, kind, []).reject(&:empty?).uniq
      if needed.empty?
        deny.call("run #{id} is unfinished here, and the `#{run["workflow"]}` workflow has no step that may #{what}. Finish or abort the run first (set `status: aborted` in #{log}).")
      end
      recorded = run["gates"].is_a?(Hash) ? run["gates"] : {}
      missing = needed.reject { |g| approved.call(recorded[g]) }
      unless missing.empty?
        deny.call("run #{id} may not #{what} yet: gate `#{missing.join("`, `")}` is not recorded as approved in #{log}. Ask the person at that gate and record their answer first.")
      end
    end
  end
rescue SystemExit
  raise
rescue StandardError
  exit 0
end
' "$root"
exit 0
