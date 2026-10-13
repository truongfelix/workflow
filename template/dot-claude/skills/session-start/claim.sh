#!/usr/bin/env bash
#
# claim.sh — claim a BACKLOG item when an agent starts working on it: add its `claimed:` line, which names the
# agent, its session, its branch and its machine, and push it, so other sessions see it (notes/item-format.md,
# Claims).
#
# Two sessions must not work on the same item. The claim is a commit on the default branch of the repo that holds
# BACKLOG.md, built on the tip of its remote and pushed there: the push is the lock. When another session pushed
# first, the push is refused; the script reads the item again from the new tip, and either claims it there or says
# who has it. It never touches the working tree, the index or the branch checked out, so a session can claim from
# any branch or worktree; the default branch checked out here is fast-forwarded afterwards when it can be, so the
# session sees the claim it made, or the one that refused it.
# The claim commit is made by git's plumbing: pre-commit hooks do not run for it, pre-push hooks do.
#
# Generic (from the workflow repo): upgrade this file from there; never put project data in it.
#
# Usage: bash .claude/skills/session-start/claim.sh <B-id> <branch> [<agent>@<session>] [--from <agent>@<session>]
#   branch          the branch the work goes on: the fact behind the claim, which the ground truth follows
#   agent@session   who works on it: the session by the name other sessions message it by (ListAgents: "This
#                   session is <name>"); default: claude@<the project folder's name>
#   --from          take over the claim of that agent@session (a session going on with the work of the one before
#                   it): the line is replaced only while the remote still has that claim
#   The remote and the default branch: the entry of .claude/ground-truth.conf for the project root, else origin and
#   its HEAD (main, master).
#   The machine: where the branch's commits are until they are pushed. CLAIM_MACHINE when set, else "cloud" in a
#   Claude Code cloud session (CLAUDE_CODE_REMOTE=true), else this machine's name (uname -n, up to its first dot).
# Exit 0 = the claim is on the remote: the item is yours (or was already). Exit 1 = refused: another session
# claimed it first (or holds it, for --from another one), or the item is not open on the remote (push a new item before claiming it). Exit 2 = nothing was
# claimed: a usage error, no remote, a push that failed for another reason, an unreadable BACKLOG.md (UNKNOWN).

set -uo pipefail

usage() { echo "usage: $0 <B-id> <branch> [<agent>@<session>] [--from <agent>@<session>]" >&2; exit 2; }
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$DIR/../../.." && pwd)
from="" args=()
while [ $# -gt 0 ]; do
  case $1 in
    --from) [ $# -ge 2 ] || usage; from=$2; shift 2 ;;
    -*) usage ;;
    *) args+=("$1"); shift ;;
  esac
done
[ ${#args[@]} -ge 2 ] && [ ${#args[@]} -le 3 ] || usage
id=${args[0]} branch=${args[1]} who=${args[2]:-claude@$(basename "$ROOT")}
[[ $id =~ ^B-[1-9][0-9]*$ ]] || { echo "not a BACKLOG id: $id (B-<n>)" >&2; usage; }
[[ $branch =~ ^[^[:space:]]+$ ]] || { echo "a branch name has no space: $branch" >&2; usage; }
[[ $who =~ ^[^[:space:]@]+@[^[:space:]@]+$ ]] || { echo "not <agent>@<session>: $who" >&2; usage; }
[ -z "$from" ] || [[ $from =~ ^[^[:space:]@]+@[^[:space:]@]+$ ]] || { echo "not <agent>@<session>: $from" >&2; usage; }
machine=${CLAIM_MACHINE:-}
[ -z "$machine" ] && [ "${CLAUDE_CODE_REMOTE:-}" = true ] && machine=cloud
[ -z "$machine" ] && machine=$(uname -n 2>/dev/null) && machine=${machine%%.*}
machine=${machine//[[:space:]]/-}
line="claimed: $who on $branch at ${machine:-unknown}"

fail() { echo "UNKNOWN: $*; nothing claimed"; exit 2; }
cd "$ROOT" || fail "cannot reach the project root"
top=$(git rev-parse --show-toplevel 2>/dev/null) || fail "$ROOT is not a git checkout: a claim is pushed, so other sessions see it"
path="$(git rev-parse --show-prefix)BACKLOG.md" # BACKLOG.md's path in its repo

remote=origin def=""
REPOS=()
# shellcheck source=/dev/null
[ -f .claude/ground-truth.conf ] && . ./.claude/ground-truth.conf
for spec in ${REPOS[@]+"${REPOS[@]}"}; do
  IFS='|' read -r _ d r b _ <<<"$spec"
  case $d in /*) p=$d ;; *) p="$ROOT/$d" ;; esac
  if [ "$p" -ef "$ROOT" ]; then remote=${r:-origin} def=$b; break; fi
done
cd "$top" || fail "cannot reach $top" # plumbing takes paths from the top of the repo
git remote get-url "$remote" >/dev/null 2>&1 || fail "no remote '$remote': other sessions see a claim only once it is pushed"
git fetch -q "$remote" || fail "git fetch $remote failed"
if [ -z "$def" ]; then
  def=$(git symbolic-ref -q --short "refs/remotes/$remote/HEAD")
  def=${def#"$remote"/}
fi
for d in "$def" main master; do
  [ -n "$d" ] && git rev-parse -q --verify "refs/remotes/$remote/$d" >/dev/null && { def=$d; break; }
done
base="$remote/$def"
git rev-parse -q --verify "refs/remotes/$base" >/dev/null || fail "'$remote' has no default branch yet"

T=$(mktemp -d "${TMPDIR:-/tmp}/claim.XXXXXX") || fail "mktemp failed"
tab=$(printf '\t')
idx="$(git rev-parse --absolute-git-dir)/claim-index.$$" # a path in git's own spelling (C:/... on Windows)
trap 'rm -rf "$T" "$idx"' EXIT

# The item as the remote has it: one record of `items.sh list`, its line and its claim.
item_on() { # <commit>: sets title, ln, state, cur; returns 1 when the item is not open there
  local rec n f kv
  title="" ln="" state="" cur=""
  git show "$1:$path" >"$T/BACKLOG.md" 2>/dev/null || return 1
  rec=$("${BASH:-bash}" "$DIR/items.sh" list "$T/BACKLOG.md" 2>"$T/err" | grep "^I$tab" |
    while IFS= read -r r; do [ "$(printf '%s\n' "$r" | cut -f4)" = "$id" ] && printf '%s\n' "$r"; done)
  grep -q UNKNOWN "$T/err" && fail "items.sh could not read $base:$path: $(cat "$T/err")"
  [ -n "$rec" ] || return 1
  n=$(printf '%s\n' "$rec" | wc -l | tr -d ' ')
  [ "$n" = 1 ] || fail "$id is given twice in $base:$path: fix the ids first (items.sh check)"
  ln=$(printf '%s\n' "$rec" | cut -f3) state=$(printf '%s\n' "$rec" | cut -f5) title=$(printf '%s\n' "$rec" | cut -f8)
  # The fields are one string, each `key: value` line escaped as \n; a claim names no backslash. Read in bash, not
  # awk: the text holds emoji, which macOS awk cannot read in the C locale.
  f=$(printf '%s\n' "$rec" | cut -f9)
  while [ -n "$f" ]; do
    kv=${f%%\\n*}
    if [ "$kv" = "$f" ]; then f=""; else f=${f#*\\n}; fi
    case $kv in "claimed: "*) cur=${kv#claimed: } ;; esac
  done
}

# Fast-forward the default branch checked out here, when nothing local stands in the way.
sync_here() { # <commit>
  local here
  here=$(git symbolic-ref -q --short HEAD)
  if [ "$here" != "$def" ]; then
    echo "  $here is checked out here: the claim is on $base"
  elif [ "$(git rev-parse HEAD)" = "$1" ]; then
    echo "  BACKLOG.md here shows it"
  elif ! git merge-base --is-ancestor HEAD "$1"; then
    echo "  $def here has commits $base does not: \`git pull --rebase\` brings the claim here"
  elif git merge -q --ff-only "$1" >/dev/null 2>&1; then
    echo "  $def here is fast-forwarded: BACKLOG.md shows it"
  else
    echo "  $def here is behind $base (BACKLOG.md has changes not committed): pull once they are committed"
  fi
}

for attempt in 1 2 3 4 5; do
  tip=$(git rev-parse "refs/remotes/$base")
  if ! item_on "$tip"; then
    msg="REFUSED: $id is not an open item on $base"
    grep -q "^### .* $id " "$ROOT/BACKLOG.md" 2>/dev/null && msg="$msg: it is only here; push it first, then claim it"
    echo "$msg"
    exit 1
  fi
  over=""
  if [ -n "$cur" ]; then
    if [ "${cur%% on *}" = "$who" ]; then
      echo "$id $title: already claimed, by $cur ($base)"
      sync_here "$tip"
      exit 0
    fi
    if [ -n "$from" ] && [ "${cur%% on *}" = "$from" ]; then
      over=$from
    else
      echo "REFUSED: $id $title is claimed by $cur ($base)${from:+, not by $from}: pick another item"
      sync_here "$tip"
      exit 1
    fi
  fi
  if [ "$state" = waiting ]; then
    echo "REFUSED: $id $title waits for its trigger (⏸️): make it 🔲 first, when the trigger came"
    exit 1
  fi

  # The claim commit: the remote's BACKLOG.md with the line under the item's heading (or in place of the claim taken
  # over: the first `claimed:` line after the heading, in its fields), on the remote's tip.
  at=$((ln + 1)) skip=0 msg="claim $id"
  if [ -n "$over" ]; then
    at=$((ln + $(tail -n +"$((ln + 1))" "$T/BACKLOG.md" | grep -n -m 1 '^claimed: ' | cut -d: -f1))) skip=1
    msg="claim $id, taken over from $over"
  fi
  cr=$(sed -n "${ln}p" "$T/BACKLOG.md" | tr -cd '\r') # a repo that stores CRLF keeps it
  { head -n "$((at - 1))" "$T/BACKLOG.md" && printf '%s%s\n' "$line" "$cr" && tail -n +"$((at + skip))" "$T/BACKLOG.md"; } \
    >"$T/new" || fail "the new BACKLOG.md could not be written"
  mode=$(git ls-tree "$tip" -- "$path" | cut -d' ' -f1)
  blob=$(git hash-object -w --no-filters "$T/new") &&
    GIT_INDEX_FILE=$idx git read-tree "$tip" &&
    GIT_INDEX_FILE=$idx git update-index --cacheinfo "$mode,$blob,$path" &&
    tree=$(GIT_INDEX_FILE=$idx git write-tree) &&
    commit=$(git commit-tree "$tree" -p "$tip" -m "$msg") || fail "the claim commit could not be made"

  if out=$(git push -q "$remote" "$commit:refs/heads/$def" 2>&1); then
    git update-ref "refs/remotes/$base" "$commit" "$tip" 2>/dev/null
    echo "CLAIMED: $id $title, by ${line#claimed: }${over:+, taken over from $over} ($base, $(git rev-parse --short "$commit"))"
    sync_here "$commit"
    exit 0
  fi
  # Refused: either another session pushed first (the remote moved: read the item again), or the push failed.
  git fetch -q "$remote" || fail "git push $remote failed, then git fetch: $out"
  [ "$(git rev-parse "refs/remotes/$base")" = "$tip" ] && fail "git push $remote failed: $out"
done
fail "$base kept moving: $attempt attempts"
