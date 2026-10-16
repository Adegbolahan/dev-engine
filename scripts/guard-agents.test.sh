#!/usr/bin/env bash
# Tests for guard-agents.sh. Run directly or through scripts/validate.rb.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
guard="$here/guard-agents.sh"
fail=0
count=0

# A home that exists nowhere, so the protected directory is a known path.
export HOME=/guard-test-home

# expect <allow|deny> <agent or ""> <tool> <command or ""> [file path, default x]
expect() {
  local want="$1" agent="$2" tool="$3" cmd="$4" fp="${5:-x}" out got
  out="$(jq -n --arg a "$agent" --arg t "$tool" --arg c "$cmd" --arg f "$fp" '
    {hook_event_name: "PreToolUse", tool_name: $t, cwd: "/work/repo",
     tool_input: (if $t == "Bash" then {command: $c} else {file_path: $f} end)}
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

# The implementer may write in the repo but not in ~/.config/dev-engine.
expect allow implementer Edit "" /work/repo/src/app.rb
expect allow dev-engine:implementer Write "" src/app.rb
expect deny implementer Edit "" "$HOME/.config/dev-engine/trusted.yaml"
expect deny dev-engine:implementer Write "" "~/.config/dev-engine/runs/x/y.yaml"
expect deny implementer MultiEdit "" "$HOME/.config/dev-engine/../dev-engine/trusted.yaml"
expect deny implementer NotebookEdit "" "$HOME/.config/dev-engine/n.ipynb"
expect deny implementer Edit "" "../../guard-test-home/.config/Dev-Engine/trusted.yaml"
expect deny implementer Bash "rm -rf ~/.config/dev-engine/runs"
expect deny implementer Bash "echo x >> $HOME/.config/dev-engine/trusted.yaml"
expect allow implementer Bash "npm test"
expect allow "" Edit "" "$HOME/.config/dev-engine/trusted.yaml"
expect allow "" Bash "ls ~/.config/dev-engine"

# The plugin's own CLI rewrites trust and snapshots without naming the
# directory, so the implementer may not run those commands. Reads stay allowed.
expect deny implementer Bash "ruby /p/scripts/config.rb trust /work/repo"
expect deny dev-engine:implementer Bash "ruby \"\${CLAUDE_PLUGIN_ROOT}/scripts/config.rb\" snapshot /work/repo 20261015-0001-x-y"
expect deny implementer Bash "ruby config.rb snapshot-rm 20261015-0001-x-y"
expect deny implementer Bash "cd /p && ruby 'scripts/config.rb' 'trust' ."
expect deny implementer Bash "ruby scripts/config.rb trust"
expect allow implementer Bash "ruby /p/scripts/config.rb trusted /work/repo"
expect allow implementer Bash "ruby /p/scripts/config.rb check /work/repo"
expect allow implementer Bash "ruby /p/scripts/config.rb snapshot-dir 20261015-0001-x-y"
expect allow "" Bash "ruby /p/scripts/config.rb trust /work/repo"

# Every subagent is kept out of the directory, not only the implementer.
expect deny some-other-agent Write "" "$HOME/.config/dev-engine/trusted.yaml"
expect deny dev-engine:general-purpose Bash "rm -rf ~/.config/dev-engine"
expect deny some-other-agent Bash "ruby config.rb trust ."
expect allow some-other-agent Bash "npm test"
expect deny researcher Write "" "$HOME/.config/dev-engine/trusted.yaml"

# A glob character in a path is a name, and a symlink to a protected file is the
# protected file. These need a real home with real entries.
real_home="$(mktemp -d)"
real_home="$(cd -P "$real_home" && pwd -P)"
mkdir -p "$real_home/.config/dev-engine" "$real_home/a" "$real_home/b"
: >"$real_home/.config/dev-engine/trusted.yaml"
ln -s "$real_home/.config/dev-engine/trusted.yaml" "$real_home/link-abs"
ln -s ".config/dev-engine/trusted.yaml" "$real_home/link-rel"
ln -s "$real_home/link-abs" "$real_home/link-chain"
ln -s "$real_home/.config/dev-engine/new.yaml" "$real_home/link-dangling"
ln -s "$real_home/a/f.txt" "$real_home/link-ok"
saved_home="$HOME"
saved_pwd="$PWD"
export HOME="$real_home"
cd "$real_home"
expect deny implementer Edit "" "$HOME/*/../.config/dev-engine/trusted.yaml"
expect deny implementer Write "" "$HOME/?/../.config/dev-engine/trusted.yaml"
expect deny implementer Write "" "$HOME/link-abs"
expect deny implementer Write "" "$HOME/link-rel"
expect deny implementer Write "" "$HOME/link-chain"
expect deny implementer Write "" "$HOME/link-dangling"
expect allow implementer Write "" "$HOME/link-ok"
expect allow implementer Write "" "$HOME/a/f.txt"
cd "$saved_pwd"
export HOME="$saved_home"
rm -rf "$real_home"

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
expect deny dev-engine:skeptic Edit ""
expect deny skeptic Bash "rm -f src/app.rb"

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
