#!/usr/bin/env bash
# One copy of this plugin per stack (a group of repos that form one system).
#
#   scripts/stack.sh new <name> <dir>   Create a copy named <name> in <dir>.
#   scripts/stack.sh update <dir>       Refresh an existing copy's core files from this one.
#
# A copy gets its own plugin name, so its command is /<name>:dev, its agents
# are <name>:<agent>, and its run state lives in .<name>/ in each repo. Two
# copies can be installed side by side without touching each other.
#
# `update` replaces only the files a stack is not meant to edit (CORE below).
# Profiles, the ledger, workflows, agents, skills, the guard's agent list,
# the doctor and the docs belong to the stack and are left alone.

set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"

CORE="commands/dev.md
engine/engine.yaml
engine/templates
hooks/hooks.json
scripts/validate.rb
scripts/session-start.sh
scripts/guard-gates.sh
scripts/guard-gates.test.sh
scripts/drift.rb
scripts/stack.sh"

die() {
  printf 'stack.sh: %s\n' "$1" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || die "jq is required"
command -v perl >/dev/null 2>&1 || die "perl is required"

plugin_name() { jq -r '.name' "$1/.claude-plugin/plugin.json"; }

# Rewrites this plugin's name to the copy's name in every text file given.
rename_in() { # rename_in <from> <to> <path>...
  local from="$1" to="$2"
  shift 2
  [ "$from" = "$to" ] && return 0
  find "$@" -type f -print0 | FROM="$from" TO="$to" xargs -0 perl -pi -e 's/\Q$ENV{FROM}\E/$ENV{TO}/g'
}

source_name="$(plugin_name "$root")"
mode="${1:-}"

case "$mode" in
  new)
    name="${2:-}"
    dir="${3:-}"
    [ -n "$name" ] && [ -n "$dir" ] || die "usage: stack.sh new <name> <dir>"
    printf '%s' "$name" | grep -Eq '^[a-z][a-z0-9]*(-[a-z0-9]+)*$' || die "name must be kebab-case, for example acme-engine"
    [ "$name" != "$source_name" ] || die "name must differ from this plugin's name ($source_name)"
    [ ! -e "$dir" ] || die "$dir already exists"

    mkdir -p "$dir"
    dir="$(cd "$dir" && pwd)"
    # Everything except local state and version control.
    (cd "$root" && find . -mindepth 1 -maxdepth 1 \
      ! -name .git ! -name .claude ! -name ".$source_name" -print0 |
      xargs -0 -I{} cp -R {} "$dir/")
    rename_in "$source_name" "$name" "$dir"

    today="$(date +%Y-%m-%d)"
    # Only the copy's own repo entry moves; other entries keep their paths.
    DIR="$dir" NAME="$name" TODAY="$today" perl -0pi -e \
      's/^surveyed:.*$/surveyed: "$ENV{TODAY}"/m; s/(- id: repo:\Q$ENV{NAME}\E\n\s*path_hint:).*/$1 $ENV{DIR}/' \
      "$dir/ledger/ledger.yaml"
    ;;

  update)
    dir="${2:-}"
    [ -n "$dir" ] || die "usage: stack.sh update <dir>"
    [ -f "$dir/.claude-plugin/plugin.json" ] || die "$dir is not a plugin copy"
    dir="$(cd "$dir" && pwd)"
    [ "$dir" != "$root" ] || die "that is this plugin"
    name="$(plugin_name "$dir")"

    printf '%s\n' "$CORE" | while IFS= read -r item; do
      rm -rf "${dir:?}/$item"
      mkdir -p "$(dirname "$dir/$item")"
      cp -R "$root/$item" "$dir/$item"
      rename_in "$source_name" "$name" "$dir/$item"
    done
    ;;

  *)
    die "usage: stack.sh new <name> <dir> | stack.sh update <dir>"
    ;;
esac

chmod +x "$dir"/scripts/*.sh "$dir"/scripts/validate.rb
if ruby "$dir/scripts/validate.rb"; then
  printf '%s: %s is ready at %s\n' "$mode" "$name" "$dir"
  if [ "$mode" = new ]; then
    printf 'Next: add your repos to engine/profiles.yaml and ledger/ledger.yaml there, then load it with\n  claude --plugin-dir %s\n' "$dir"
  fi
else
  die "the copy at $dir does not validate; see the problems above"
fi
