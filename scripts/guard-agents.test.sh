#!/usr/bin/env bash
# Tests for guard-agents.sh. Run directly or through scripts/validate.rb.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
guard="$here/guard-agents.sh"
fail=0
count=0

# expect <allow|deny> <agent or ""> <tool> <command or "">
expect() {
  local want="$1" agent="$2" tool="$3" cmd="$4" out got
  out="$(jq -n --arg a "$agent" --arg t "$tool" --arg c "$cmd" '
    {hook_event_name: "PreToolUse", tool_name: $t,
     tool_input: (if $t == "Bash" then {command: $c} else {file_path: "x"} end)}
    + (if $a == "" then {} else {agent_type: $a} end)' | bash "$guard")"
  if printf '%s' "$out" | grep -q '"permissionDecision": *"deny"'; then got=deny; else got=allow; fi
  count=$((count + 1))
  if [ "$got" != "$want" ]; then
    fail=$((fail + 1))
    printf 'FAIL: want %s, got %s: agent=%s tool=%s cmd=%s\n' "$want" "$got" "${agent:-<main>}" "$tool" "$cmd"
  fi
}

# The main session and the writer are not restricted.
expect allow "" Write ""
expect allow "" Bash "rm -rf build"
expect allow implementer Edit ""
expect allow dev-engine:implementer Bash "npm test"

# Read-only agents may not edit, with or without the plugin prefix.
expect deny correctness-reviewer Write ""
expect deny dev-engine:security-reviewer Edit ""
expect deny doc-reviewer NotebookEdit ""
expect deny researcher Write ""
expect deny cross-repo-navigator Edit ""
expect deny ui-researcher Write ""
expect deny dev-engine:ui-reviewer Edit ""
expect deny prior-art-researcher Write ""
expect deny ui-reviewer Bash "python3 contrast.py"

# Read-only commands pass.
expect allow correctness-reviewer Bash "git diff main...HEAD"
expect allow test-reviewer Bash "git diff main...HEAD | head -50"
expect allow maintainability-reviewer Bash "cd src && rg TODO"
expect allow researcher Bash "find . -name '*.rb' -type f"
expect allow dev-engine:researcher Bash "git log --oneline -20; git status"
expect allow doc-reviewer Bash "git branch --show-current"
expect allow security-reviewer Bash "cat package.json | jq .dependencies"

# Anything that writes, runs other programs or leaves the allowlist is denied.
expect deny correctness-reviewer Bash "rm -rf x"
expect deny correctness-reviewer Bash "git push"
expect deny correctness-reviewer Bash "git commit -am x"
expect deny correctness-reviewer Bash "git checkout ."
expect deny correctness-reviewer Bash "cat a > b"
expect deny correctness-reviewer Bash "git diff --output=x"
expect deny correctness-reviewer Bash "find . -name x -delete"
expect deny correctness-reviewer Bash "find . -exec rm {} +"
expect deny correctness-reviewer Bash 'echo $(rm x)'
expect deny correctness-reviewer Bash 'echo `rm x`'
expect deny correctness-reviewer Bash "ls; rm x"
expect deny correctness-reviewer Bash "git log & rm x"
expect deny correctness-reviewer Bash "ls && npm install"
expect deny correctness-reviewer Bash "rg --pre ./x foo"
expect deny correctness-reviewer Bash "FOO=1 ls"
expect deny researcher Bash "sed -i s/a/b/ f"
expect deny researcher Bash "curl https://example.com"

if [ "$fail" -gt 0 ]; then
  printf '%d of %d guard tests failed\n' "$fail" "$count"
  exit 1
fi
printf 'guard-agents: %d tests passed\n' "$count"
