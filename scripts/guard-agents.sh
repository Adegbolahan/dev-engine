#!/usr/bin/env bash
# PreToolUse hook. Keeps the read-only agents read-only: denies file edits and
# any Bash command outside the allowlist below when the call comes from one of
# them. Calls from the main session and from the implementer pass through.
#
# Reads the hook JSON on stdin. Prints a deny decision, or nothing to allow.

set -u

# Every agent in agents/ whose tools hold no Edit or Write. validate.rb checks
# that this list and the agent files agree.
READ_ONLY_AGENTS="correctness-reviewer security-reviewer test-reviewer maintainability-reviewer doc-reviewer researcher cross-repo-navigator ui-researcher prior-art-researcher ui-reviewer"

input="$(cat)"

deny() {
  local reason="dev-engine: $1"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg r "$reason" \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"dev-engine: denied for a read-only agent (install jq for details)"}}\n'
  fi
  exit 0
}

# Without jq the command cannot be inspected, so fail closed for the read-only
# agents and leave everything else alone.
if ! command -v jq >/dev/null 2>&1; then
  for a in $READ_ONLY_AGENTS; do
    case "$input" in
      *"\"agent_type\":\"$a\""* | *"\"agent_type\": \"$a\""* | *":$a\""*) deny "jq is missing" ;;
    esac
  done
  exit 0
fi

agent="$(printf '%s' "$input" | jq -r '.agent_type // empty')"
agent="${agent##*:}" # plugin agents arrive as dev-engine:<name>
[ -z "$agent" ] && exit 0

read_only=0
for a in $READ_ONLY_AGENTS; do
  [ "$a" = "$agent" ] && read_only=1
done
[ "$read_only" -eq 0 ] && exit 0

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"

RE_PLAIN='^(cd|ls|cat|head|tail|wc|pwd|stat|cut|tr|diff|nl|basename|dirname|echo|true|jq)([[:space:]]|$)'
RE_SEARCH='^(rg|grep)([[:space:]]|$)'
RE_SEARCH_BAD='--(pre|hostname-bin)'
RE_FIND='^find([[:space:]]|$)'
RE_FIND_BAD='-(delete|exec|execdir|ok|okdir|fprint|fprintf|fprint0|fls)([[:space:]]|$)'
RE_GIT='^git[[:space:]]+(diff|log|show|status|blame|ls-files|ls-tree|grep|rev-parse|rev-list|merge-base|cat-file|shortlog|describe)([[:space:]]|$)'
RE_GIT_BAD='--output|--open-files-in-pager|[[:space:]]-O'

segment_ok() {
  local s="$1"
  [[ "$s" =~ $RE_PLAIN ]] && return 0
  if [[ "$s" =~ $RE_SEARCH ]]; then
    [[ "$s" =~ $RE_SEARCH_BAD ]] && return 1
    return 0
  fi
  if [[ "$s" =~ $RE_FIND ]]; then
    [[ "$s" =~ $RE_FIND_BAD ]] && return 1
    return 0
  fi
  if [[ "$s" =~ $RE_GIT ]]; then
    [[ "$s" =~ $RE_GIT_BAD ]] && return 1
    return 0
  fi
  [ "$s" = "git branch --show-current" ] && return 0
  [ "$s" = "git remote -v" ] && return 0
  return 1
}

# Quoting is not parsed, so a redirect or separator inside a quoted pattern is
# also refused. That errs on the side of denying; the agent has Grep for those.
command_ok() {
  local cmd="$1" nl=$'\n' seg
  case "$cmd" in
    *'>'* | *'<'* | *'`'* | *'$('* | *"$nl"*) return 1 ;;
  esac
  cmd="${cmd//&&/$nl}"
  cmd="${cmd//||/$nl}"
  cmd="${cmd//;/$nl}"
  cmd="${cmd//|/$nl}"
  case "$cmd" in *'&'*) return 1 ;; esac
  while IFS= read -r seg; do
    seg="$(printf '%s' "$seg" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -z "$seg" ] && continue
    segment_ok "$seg" || return 1
  done <<<"$cmd"
  return 0
}

case "$tool" in
  Bash)
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
    command_ok "$cmd" || deny "$agent is read-only and this command is outside its allowlist (read-only git, ls, cat, head, tail, wc, rg, grep, find; no redirects or substitution). Use Read, Grep or Glob instead."
    ;;
  *)
    deny "$agent is read-only and may not use $tool. Report the change you would make instead."
    ;;
esac

exit 0
