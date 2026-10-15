#!/usr/bin/env bash
# Checks this machine has what the plugin needs, and says where the user
# ledger is. A missing ledger is not a failure: one repo needs none.

root="$(cd "$(dirname "$0")/.." && pwd)"
missing=0

need() { # need <command> <why>
  if command -v "$1" >/dev/null 2>&1; then
    printf 'ok       %-8s %s\n' "$1" "$(command -v "$1")"
  else
    printf 'MISSING  %-8s %s\n' "$1" "$2"
    missing=$((missing + 1))
  fi
}

want() { # want <command> <why>
  if command -v "$1" >/dev/null 2>&1; then
    printf 'ok       %-8s %s\n' "$1" "$(command -v "$1")"
  else
    printf 'optional %-8s %s\n' "$1" "$2"
  fi
}

need git "every workflow uses it"
need jq "the read-only guard parses hook input with it"
need ruby "the validator and the session-start note need it"
need claude "the plugin runs in Claude Code"
want gh "needed to open merge requests in profiles with forge: github"
want glab "needed to open merge requests in profiles with forge: gitlab"

if [ -x "$root/scripts/guard-agents.sh" ]; then
  printf 'ok       %-8s %s\n' "guard" "scripts/guard-agents.sh is executable"
else
  printf 'MISSING  %-8s %s\n' "guard" "scripts/guard-agents.sh is not executable"
  missing=$((missing + 1))
fi

ledger="${DEV_ENGINE_LEDGER:-$HOME/.config/dev-engine/ledger.yaml}"
if [ -f "$ledger" ]; then
  printf 'ok       %-8s %s\n' "ledger" "$ledger"
else
  printf 'optional %-8s %s\n' "ledger" "$ledger does not exist; /dev init creates it"
fi

if [ "$missing" -gt 0 ]; then
  printf '\n%d required item(s) missing.\n' "$missing"
  exit 1
fi
printf '\nAll required items present.\n'
