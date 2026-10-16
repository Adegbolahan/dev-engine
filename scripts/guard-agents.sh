#!/usr/bin/env bash
# PreToolUse hook. Keeps the read-only agents read-only: denies file edits and
# any Bash command outside the allowlist below when the call comes from one of
# them. Keeps every subagent, the implementer above all since it may write, out
# of ~/.config/dev-engine, the directory holding the trust record, ledger and
# run snapshots: denies its file edits there, any Bash command that names that
# directory, and any Bash command that runs config.rb with `trust`, `snapshot`
# or `snapshot-rm`, the plugin's own way of rewriting trust and snapshots. Calls
# from the main session (no agent_type) pass through.
#
# The Bash checks are best-effort: Bash is unbounded, so a determined command
# can build a path or a call this does not recognise. The agent prompts are the
# main control; this hook catches the plain cases. Full checking needs jq.
# Without it, the hook can only fail closed: it denies any subagent call whose
# raw input mentions `.config/dev-engine` or `config.rb`, and every call from a
# read-only agent.
#
# Reads the hook JSON on stdin. Prints a deny decision, or nothing to allow.

set -u

# Every agent in agents/ whose tools hold no Edit or Write. validate.rb checks
# that this list and the agent files agree.
READ_ONLY_AGENTS="correctness-reviewer security-reviewer test-reviewer maintainability-reviewer doc-reviewer researcher cross-repo-navigator ui-researcher prior-art-researcher ui-reviewer skeptic"

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

# Without jq the command cannot be inspected, so fail closed: every call from a
# read-only agent, and any other subagent's call that mentions the protected
# directory or config.rb. The main session and other calls are left alone.
if ! command -v jq >/dev/null 2>&1; then
  for a in $READ_ONLY_AGENTS; do
    case "$input" in
      *"\"agent_type\":\"$a\""* | *"\"agent_type\": \"$a\""* | *":$a\""*) deny "jq is missing" ;;
    esac
  done
  case "$input" in
    *'"agent_type":""'* | *'"agent_type": ""'*) ;;
    *'"agent_type":"'* | *'"agent_type": "'*)
      case "$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')" in
        *".config/dev-engine"* | *"config.rb"*) deny "jq is missing" ;;
      esac
      ;;
  esac
  exit 0
fi

agent="$(printf '%s' "$input" | jq -r '.agent_type // empty')"
agent="${agent##*:}" # plugin agents arrive as dev-engine:<name>
[ -z "$agent" ] && exit 0

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"

# The directory holding the trust record and the run snapshots.
PROTECTED="$HOME/.config/dev-engine"
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# An absolute path with `.` and `..` removed and the symlinks in its existing
# part resolved, whether or not the file exists. Does not follow a symlinked
# final component; resolve_path does.
resolve_once() {
  local p="$1" cwd="$2" rest="" base part
  local -a out=()
  case "$p" in
    "~") p="$HOME" ;;
    "~/"*) p="$HOME/${p#\~/}" ;;
  esac
  case "$p" in /*) ;; *) p="${cwd:-.}/$p" ;; esac
  local oldifs="$IFS"
  IFS=/
  set -f # a `*` in a path is a name, not a pattern
  for part in $p; do
    case "$part" in
      "" | .) ;;
      ..) [ "${#out[@]}" -gt 0 ] && unset "out[${#out[@]}-1]" ;;
      *) out+=("$part") ;;
    esac
  done
  set +f
  p="/${out[*]-}"
  IFS="$oldifs"
  while [ ! -e "$p" ] && [ ! -L "$p" ] && [ "$p" != "/" ]; do
    rest="/${p##*/}$rest"
    p="${p%/*}"
    [ -z "$p" ] && p="/"
  done
  if [ -d "$p" ]; then
    base="$(cd -P "$p" 2>/dev/null && pwd -P)" || base="$p"
  else
    base="$(cd -P "$(dirname "$p")" 2>/dev/null && pwd -P)/$(basename "$p")" || base="$p"
  fi
  printf '%s%s' "${base%/}" "$rest"
}

# resolve_once, then follow a symlinked final component (up to 16 links).
resolve_path() {
  local p n=0 target
  p="$(resolve_once "$1" "$2")"
  while [ -L "$p" ] && [ "$n" -lt 16 ]; do
    target="$(readlink "$p")" || break
    case "$target" in /*) ;; *) target="$(dirname "$p")/$target" ;; esac
    p="$(resolve_once "$target" "")"
    n=$((n + 1))
  done
  printf '%s' "$p"
}

# Every subagent, not only the implementer, stays out of PROTECTED.
prot="$(lower "$PROTECTED")"
prot_real="$(lower "$(resolve_path "$PROTECTED" "")")"
RE_CONFIG_WRITE="config\\.rb[\"']?[[:space:]]+[\"']?(trust|snapshot|snapshot-rm)([\"'[:space:];|&)]|\$)"
case "$tool" in
  Edit | Write | MultiEdit | NotebookEdit)
    fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
    cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
    if [ -n "$fp" ]; then
      res="$(lower "$(resolve_path "$fp" "$cwd")")"
      for p in "$prot" "$prot_real"; do
        case "$res" in "$p" | "$p"/*) deny "$agent may not edit $PROTECTED (the directory holding the trust record, ledger and run snapshots)." ;; esac
      done
    fi
    ;;
  Bash)
    cmd="$(lower "$(printf '%s' "$input" | jq -r '.tool_input.command // empty')")"
    case "$cmd" in
      *".config/dev-engine"*) deny "$agent's commands may not name $PROTECTED (the directory holding the trust record, ledger and run snapshots)." ;;
    esac
    if [[ "$cmd" =~ $RE_CONFIG_WRITE ]]; then
      deny "$agent's commands may not run config.rb trust, snapshot or snapshot-rm; they rewrite the trust record and run snapshots."
    fi
    ;;
esac

read_only=0
for a in $READ_ONLY_AGENTS; do
  [ "$a" = "$agent" ] && read_only=1
done
[ "$read_only" -eq 0 ] && exit 0

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
