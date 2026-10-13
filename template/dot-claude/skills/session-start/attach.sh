#!/usr/bin/env bash
#
# attach.sh — attach a code repo to the project: its line in REPOS (.claude/ground-truth.conf), and a pointer in the
# repo itself, so that a session opened there finds the docs.
#
# The docs repo (the project root) holds the trackers, the handoffs and CLAUDE.md; the code repos are listed in
# REPOS, inside the root or anywhere else on the disk. A session opened in a code repo loads that repo's CLAUDE.md,
# not the root's: the pointer is a short CLAUDE.md there that says where the docs are and imports the root's
# CLAUDE.md, so its rules load too. It is kept out of the repo's commits (the repo's .git/info/exclude): it names a
# path on this machine, so it exists on this machine only, and a clone elsewhere needs this script run again. A
# repo that has a CLAUDE.md of its own gets the pointer as CLAUDE.local.md, and its CLAUDE.md is not touched.
#
# Generic (from the workflow repo): upgrade this file from there; never put project data in it.
#
# Usage: bash .claude/skills/session-start/attach.sh <name> [<path>] [--remote <r>] [--branch <b>] [--github <o/r>]
#   name     the repo's name in REPOS. Already there: only its pointer is written (a repo that has none yet).
#   path     the repo's folder (relative to the project root, or absolute); needed for a new name
#   --remote the remote that counts as "pushed" (default origin); --branch its default branch (default: read from
#            the remote); --github its GitHub owner/repo (default: from the remote's URL)
# Exit 0 = the repo is in REPOS and has its pointer. Exit 2 = nothing was done: a usage error, a path that is not a
# git checkout, a name that is taken by another folder, an unreadable config.

set -uo pipefail

usage() { echo "usage: $0 <name> [<path>] [--remote <r>] [--branch <b>] [--github <o/r>]" >&2; exit 2; }
fail() { echo "UNKNOWN: $*; nothing attached"; exit 2; }
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$DIR/../../.." && pwd -P)
CONF="$ROOT/.claude/ground-truth.conf"
MARK="<!-- workflow pointer: written by attach.sh -->"

remote=origin branch="" gh="" args=()
while [ $# -gt 0 ]; do
  case $1 in
    --remote) [ $# -ge 2 ] || usage; remote=$2; shift 2 ;;
    --branch) [ $# -ge 2 ] || usage; branch=$2; shift 2 ;;
    --github) [ $# -ge 2 ] || usage; gh=$2; shift 2 ;;
    -*) usage ;;
    *) args+=("$1"); shift ;;
  esac
done
[ ${#args[@]} -ge 1 ] && [ ${#args[@]} -le 2 ] || usage
name=${args[0]} given=${args[1]:-}
[[ $name =~ ^[A-Za-z0-9._-]+$ ]] || { echo "a repo name has letters, digits, . _ - only: $name" >&2; usage; }
[ -f "$CONF" ] || fail "no $CONF"

REPOS=()
# shellcheck source=/dev/null
. "$CONF" || fail "$CONF does not source"
dir=""
for spec in ${REPOS[@]+"${REPOS[@]}"}; do
  IFS='|' read -r n d _ <<<"$spec"
  if [ "$n" = "$name" ]; then dir=$d; break; fi
done

new=0
if [ -n "$dir" ]; then
  if [ -n "$given" ]; then
    case $dir in /*) a=$dir ;; *) a="$ROOT/$dir" ;; esac
    case $given in /*) b=$given ;; *) b="$ROOT/$given" ;; esac
    [ "$a" -ef "$b" ] || fail "$name is already in REPOS as $dir, not $given"
  fi
else
  [ -n "$given" ] || { echo "$name is not in REPOS: give its path" >&2; usage; }
  dir=$given new=1
fi
case $dir in /*) repo=$dir ;; *) repo="$ROOT/$dir" ;; esac
[ -d "$repo" ] && git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || fail "$repo is not a git checkout"
repo=$(cd "$repo" && pwd -P)
if [ "$repo" -ef "$ROOT" ]; then
  [ "$new" = 0 ] && { echo "$name is the project root, the docs repo: it needs no pointer"; exit 0; }
  fail "$repo is the project root: the docs repo is listed already, or list it by hand"
fi

# Its line in REPOS: a REPOS+= line, the same list in bash, right after the end of the REPOS=( ... ) array (its first
# line ending in ")" from "REPOS=(" on). Lines are copied as they are.
if [ "$new" = 1 ]; then
  entry="$name|$dir|$remote|$branch|$gh"
  tmp=$(mktemp "$CONF.XXXXXX") || fail "cannot write beside $CONF"
  state=before
  while IFS= read -r line || [ -n "$line" ]; do
    printf '%s\n' "$line" >>"$tmp"
    if [ "$state" = before ]; then
      case $line in REPOS=\(*) state=in ;; esac
    fi
    if [ "$state" = in ]; then
      stripped=${line%$'\r'}
      case $stripped in
        *\)) printf 'REPOS+=("%s")\n' "$entry" >>"$tmp"; state=done ;;
      esac
    fi
  done <"$CONF"
  if [ "$state" != done ]; then rm -f "$tmp"; fail "no REPOS=( ... ) in $CONF to add to"; fi
  # Keep the file's mode, and its line endings: a CRLF config gets CRLF on the line added (a bash loop, not awk).
  if [ "$(tr -cd '\r' <"$CONF" | wc -c | tr -d ' ')" -gt 0 ]; then
    crlf=$(mktemp "$CONF.XXXXXX") || fail "cannot write beside $CONF"
    while IFS= read -r line || [ -n "$line" ]; do printf '%s\r\n' "${line%$'\r'}" >>"$crlf"; done <"$tmp"
    mv "$crlf" "$tmp"
  fi
  mv "$tmp" "$CONF" || fail "cannot write $CONF"
  echo "added to REPOS: $entry"
fi

# A repo inside the root that the root's own .gitignore does not cover would show as untracked there: exclude it
# locally (the workspace shape ignores everything but its docs already).
case $repo in
  "$ROOT"/*)
    rel=${repo#"$ROOT"/}
    if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 && ! git -C "$ROOT" check-ignore -q -- "$rel/"; then
      rexclude=$(git -C "$ROOT" rev-parse --git-path info/exclude)
      case $rexclude in /*) ;; *) rexclude="$ROOT/$rexclude" ;; esac
      mkdir -p "$(dirname "$rexclude")"
      grep -qxF "/$rel/" "$rexclude" 2>/dev/null || printf '/%s/\n' "$rel" >>"$rexclude"
      echo "excluded from the docs repo (.git/info/exclude): /$rel/"
    fi ;;
esac

# The pointer: CLAUDE.md, or CLAUDE.local.md when the repo has a CLAUDE.md that is not ours.
file=CLAUDE.md
if [ -e "$repo/CLAUDE.md" ] && ! grep -qF -- "$MARK" "$repo/CLAUDE.md"; then file=CLAUDE.local.md; fi
if [ -e "$repo/$file" ] && ! grep -qF -- "$MARK" "$repo/$file"; then
  fail "$repo/$file exists and is not a pointer: move it, then run this again (the repo is in REPOS)"
fi
# Inside the root, Claude Code loads the root's CLAUDE.md above the session's folder already: no import there (it
# would load twice). Elsewhere the import is what brings the rules.
import="@$ROOT/CLAUDE.md"
case $repo in "$ROOT"/*) import="(Inside the docs repo's folder: its CLAUDE.md loads above this one.)" ;; esac
cat >"$repo/$file" <<PTEOF
$MARK
# $name: code repo of a project whose docs are elsewhere

The trackers (BACKLOG.md, questions.md), the handoffs, the lessons and the rules for working on this project are in
the docs repo, \`$ROOT\`. Work started here follows them. Start the session there, or run \`/session-start\` from
there, before changing anything.

$import
PTEOF
exclude=$(git -C "$repo" rev-parse --git-path info/exclude)
case $exclude in /*) ;; *) exclude="$repo/$exclude" ;; esac
mkdir -p "$(dirname "$exclude")"
grep -qxF "/$file" "$exclude" 2>/dev/null || printf '/%s\n' "$file" >>"$exclude"
echo "pointer: $repo/$file (not committed: it names a path on this machine)"
