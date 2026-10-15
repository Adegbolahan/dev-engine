#!/usr/bin/env bash
# Tests for guard-gates.sh. Run directly or through scripts/validate.rb.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
guard="$here/guard-gates.sh"
name="$(jq -r '.name' "$here/../.claude-plugin/plugin.json")"
fail=0
count=0

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
other="$tmp/other"
mkdir -p "$repo" "$other"
git -C "$repo" init -q
git -C "$other" init -q
repo="$(cd "$repo" && git rev-parse --show-toplevel)"
runs="$repo/.$name/runs"

# set_run <workflow> <status> <gates yaml, one line, or "">
set_run() {
  rm -rf "$runs"
  [ "$1" = none ] && return 0
  mkdir -p "$runs"
  printf 'run: r1\nworkflow: %s\nstatus: %s\n%s\n' "$1" "$2" "$3" >"$runs/r1.yaml"
}

# expect <allow|deny> <cwd> <tool> <command>
expect() {
  local want="$1" cwd="$2" tool="$3" cmd="$4" out got
  out="$(jq -n --arg d "$cwd" --arg t "$tool" --arg c "$cmd" \
    '{hook_event_name: "PreToolUse", tool_name: $t, cwd: $d, tool_input: {command: $c}}' | bash "$guard")"
  if printf '%s' "$out" | grep -q '"permissionDecision": *"deny"'; then got=deny; else got=allow; fi
  count=$((count + 1))
  if [ "$got" != "$want" ]; then
    fail=$((fail + 1))
    printf 'FAIL: want %s, got %s: cwd=%s tool=%s cmd=%s\n' "$want" "$got" "$cwd" "$tool" "$cmd"
  fi
}

# Outside a run nothing is restricted.
set_run none
expect allow "$repo" Bash "git push origin main"
expect allow "$repo" Bash "gh pr create --fill"

# A finished or aborted run restricts nothing.
set_run feature done ""
expect allow "$repo" Bash "git push"
set_run feature aborted ""
expect allow "$repo" Bash "git push"

# An unfinished run with no approval blocks what leaves the machine.
set_run feature running ""
expect deny "$repo" Bash "git push origin main"
expect deny "$repo" Bash "git push"
expect deny "$repo" Bash "pnpm test && git push -u origin feature/x"
expect deny "$repo" Bash "git -c core.hooksPath=/dev/null push"
expect deny "$repo" Bash "gh pr create --fill"
expect deny "$other" Bash "git -C $repo push"
expect deny "$other" Bash "cd $repo && git push"
set_run feature waiting ""
expect deny "$repo" Bash "git push"

# Commands that do not leave the machine are untouched during a run.
set_run feature running ""
expect allow "$repo" Bash "git status && git log --grep push"
expect allow "$repo" Bash "git commit -m 'push the button'"
expect allow "$repo" Bash "git push --dry-run origin main"
expect allow "$repo" Bash "git stash push -m wip"
expect allow "$repo" Edit ""
expect allow "$other" Bash "git push"

# A dry run does not excuse a real push in the same command.
expect deny "$repo" Bash "git push --dry-run; git push"

# Only an approval opens the gate, in either recorded shape.
set_run feature running "gates: {approve-publish: {answer: approve, time: '2026-01-01T00:00:00Z'}}"
expect allow "$repo" Bash "git push origin main"
set_run feature running "gates: {approve-publish: approved}"
expect allow "$repo" Bash "git push origin main"
set_run feature running "gates: {approve-publish: {answer: revise}}"
expect deny "$repo" Bash "git push origin main"
set_run feature running "gates: {approve-story: {answer: approve}, approve-plan: {answer: approve}}"
expect deny "$repo" Bash "git push origin main"

# A workflow with no push step cannot push while its run is unfinished.
set_run review running ""
expect deny "$repo" Bash "git push"

# A run started in one worktree governs a push from another worktree of the repo.
set_run none
git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$repo" worktree add -q "$tmp/tree" -b side
tree="$(cd "$tmp/tree" && git rev-parse --show-toplevel)"
mkdir -p "$tree/.$name/runs"
printf 'run: r2\nworkflow: feature\nstatus: running\n' >"$tree/.$name/runs/r2.yaml"
expect deny "$repo" Bash "git push origin main"
printf 'run: r2\nworkflow: feature\nstatus: running\ngates: {approve-publish: {answer: approve}}\n' >"$tree/.$name/runs/r2.yaml"
expect allow "$repo" Bash "git push origin main"
rm -rf "$tree/.$name"

# A pointer in another repo follows the run that spans it.
mkdir -p "$other/.$name/runs"
set_run feature running ""
printf 'run: r1\nprimary: %s\n' "$runs/r1.yaml" >"$other/.$name/runs/r1.yaml"
expect deny "$other" Bash "git push"
set_run feature running "gates: {approve-publish: {answer: approve}}"
expect allow "$other" Bash "git push"
set_run feature done ""
expect allow "$other" Bash "git push"
set_run none
expect allow "$other" Bash "git push"
rm -rf "$other/.$name"

# An unreadable log of an unfinished run blocks rather than waves through.
mkdir -p "$runs" && printf 'status: running\n  bad: [yaml\n' >"$runs/r1.yaml"
expect deny "$repo" Bash "git push"

if [ "$fail" -gt 0 ]; then
  printf '%d of %d gate-guard tests failed\n' "$fail" "$count"
  exit 1
fi
printf 'guard-gates: %d tests passed\n' "$count"
