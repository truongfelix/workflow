#!/usr/bin/env bash
#
# ground-truth.sh — what is TRUE right now, read from git, GitHub and the machine.
#
# notes/handoff.md, BACKLOG.md and questions.md are CLAIMS written by a past session; this script prints the FACTS
# they are checked against. /session-start runs it before reading the handoff, /handoff before writing one, so the
# reader and the writer look at the same picture.
#
# Generic (from the workflow repo): WHAT to look at lives in .claude/ground-truth.conf. Upgrade this file from the
# workflow repo; never put project data in it.
#
# Read-only, apart from `git fetch` of the remotes named in the config (so "pushed" means pushed). --no-fetch skips
# it. Exit 0 = every probe answered. Exit 2 = at least one probe failed: its section says UNKNOWN, never "clean".
#
# Usage: bash .claude/skills/session-start/ground-truth.sh [--no-fetch]

set -uo pipefail

# Physical path and the path as typed, both matched against background jobs. Paths that git prints are compared
# with `-ef` (same directory), never as strings: git spells them its own way (symlinks resolved, C:/ on Windows).
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
ROOT_TYPED=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
CONF="$ROOT/.claude/ground-truth.conf"

# Defaults, overridden by the config: the project root itself is the one repo.
REPOS=("$(basename "$ROOT")|.|origin||")
KEEP_LOCAL=""
UNITS=1
# shellcheck source=/dev/null
[ -f "$CONF" ] && . "$CONF"

FETCH=1
[ "${1:-}" = "--no-fetch" ] && FETCH=0
FAILED=0
unknown() { echo "  UNKNOWN: $*"; FAILED=$((FAILED + 1)); }

relpath() { # <path from git>: relative to ROOT when inside it, else as given
  local p=$1 suffix=""
  while :; do
    if [ "$p" -ef "$ROOT" ]; then echo "${suffix:-.}"; return; fi
    suffix="${p##*/}${suffix:+/$suffix}"
    p=${p%/*}
    # Stop at "/" or at a bare drive ("C:" is the current directory on drive C, not its root).
    case $p in */*) ;; *) break ;; esac
  done
  echo "$1"
}

# A probe must not hang the session. GNU `timeout` or Homebrew's `gtimeout` if it works (on Windows, System32's
# unrelated timeout.exe can come first on the PATH), else poll and kill (stock macOS).
TIMEOUT_CMD=""
for t in timeout gtimeout; do
  command -v "$t" >/dev/null && "$t" 1 true </dev/null >/dev/null 2>&1 && { TIMEOUT_CMD=$t; break; }
done
with_timeout() { # <seconds> <command...>
  local secs=$1 pid n=0
  shift
  if [ -n "$TIMEOUT_CMD" ]; then "$TIMEOUT_CMD" "$secs" "$@"; return; fi
  "$@" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$n" -ge $((secs * 10)) ]; then
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 0.1
    n=$((n + 1))
  done
  wait "$pid"
}

echo "GROUND TRUTH — $(date '+%Y-%m-%d %H:%M %Z')"

root_listed=0
for spec in "${REPOS[@]}"; do
  IFS='|' read -r name dir remote def gh_repo <<<"$spec"
  case $dir in /*) repo=$dir ;; *) repo="$ROOT/$dir" ;; esac
  [ "$repo" -ef "$ROOT" ] && root_listed=1
  echo
  echo "== $name ($dir)"

  if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    unknown "$repo is not a git checkout"
    continue
  fi

  # The remote and its default branch. No remote at all is a finding, not a failure: nothing here is pushed.
  base=""
  if ! git -C "$repo" remote get-url "$remote" >/dev/null 2>&1; then
    echo "  ⚠ no remote '$remote': nothing in this repo is pushed anywhere"
  else
    if [ "$FETCH" = 1 ] && ! with_timeout 60 git -C "$repo" fetch --quiet --prune "$remote" 2>/dev/null; then
      unknown "git fetch $remote failed: everything below compares against a STALE $remote"
    fi
    if [ -z "$def" ]; then
      def=$(git -C "$repo" symbolic-ref -q --short "refs/remotes/$remote/HEAD" 2>/dev/null)
      def=${def#"$remote"/}
    fi
    for d in "$def" main master; do
      [ -n "$d" ] && git -C "$repo" rev-parse -q --verify "refs/remotes/$remote/$d" >/dev/null && { def=$d; break; }
    done
    if git -C "$repo" rev-parse -q --verify "refs/remotes/$remote/$def" >/dev/null 2>&1; then
      base="$remote/$def"
      echo "  $base: $(git -C "$repo" log -1 --format='%h %cd %s' --date=format:'%m-%d %H:%M' "$base")"
    else
      echo "  ⚠ '$remote' has no default branch yet: nothing is pushed"
    fi
    if [ -z "$gh_repo" ]; then
      gh_repo=$(git -C "$repo" remote get-url "$remote" | sed -nE 's#^(git@|ssh://git@|https://)github\.com[:/]([^/]+/[^/]+)$#\2#p')
      gh_repo=${gh_repo%.git}
    fi
  fi

  # A commit our remote does not hold: is it at least on another remote, or only on this disk?
  elsewhere() {
    local other
    other=$(git -C "$repo" for-each-ref --count=1 --contains "$1" --format='%(refname:short)' refs/remotes)
    if [ -n "$other" ]; then echo "not on $remote, only on $other"; else echo "LOCAL ONLY: on no remote at all"; fi
  }

  # Every worktree: where it stands against our remote, and whether it holds uncommitted work.
  wt_line() {
    local path=$1 head=$2 branch=$3 rel state dirty label
    rel=$(relpath "$path")
    if [ ! -d "$path" ]; then
      echo "    $rel: MISSING (git worktree prune?)"
      return
    fi
    dirty=$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [ -z "$head" ]; then
      state="no commit yet"
    elif [ -z "$base" ]; then
      state="nothing pushed (no remote branch to compare with)"
    elif [ -n "$branch" ] && [ "$branch" = "$def" ]; then
      state=$(git -C "$repo" rev-list --left-right --count "$head...$base" |
        awk -v b="$base" '{ if ($1==0 && $2==0) print "= " b; else printf "ahead %d / behind %d of %s\n", $1, $2, b }')
    elif [ -n "$branch" ] && git -C "$repo" rev-parse -q --verify "refs/remotes/$remote/$branch" >/dev/null; then
      state=$(git -C "$repo" rev-list --left-right --count "$branch...$remote/$branch" |
        awk '{ if ($1==0 && $2==0) print "= pushed"; else printf "ahead %d / behind %d of the pushed branch\n", $1, $2 }')
    elif git -C "$repo" merge-base --is-ancestor "$head" "$base"; then
      state="merged into $base"
    elif [ -z "$branch" ] && [ -n "$(git -C "$repo" for-each-ref --count=1 --contains "$head" "refs/remotes/$remote")" ]; then
      state="on a $remote branch"
    else
      state=$(elsewhere "$head")
    fi
    if [ -n "$branch" ]; then label="[$branch]"; else label="detached ${head:0:9}"; fi
    [ "$dirty" != 0 ] && state="$state, $dirty uncommitted"
    echo "    $rel $label: $state"
  }
  echo "  worktrees:"
  wt_path="" wt_head="" wt_branch=""
  while IFS= read -r line; do
    case $line in
      "worktree "*) wt_path=${line#worktree } wt_head="" wt_branch="" ;;
      "HEAD "*) wt_head=${line#HEAD } ;;
      "branch "*) wt_branch=${line#branch refs/heads/} ;;
      "") [ -n "$wt_path" ] && wt_line "$wt_path" "$wt_head" "$wt_branch"; wt_path="" ;;
    esac
  done < <(git -C "$repo" worktree list --porcelain; echo)

  # Branches no worktree has checked out: the work that is easiest to forget.
  checked_out=" $(git -C "$repo" worktree list --porcelain | sed -n 's|^branch refs/heads/||p' | tr '\n' ' ') "
  others=""
  while IFS= read -r b; do
    [ -z "$b" ] && continue
    case $checked_out in *" $b "*) continue ;; esac
    if [ -n "$base" ] && git -C "$repo" rev-parse -q --verify "refs/remotes/$remote/$b" >/dev/null; then
      ahead=$(git -C "$repo" rev-list --count "$remote/$b..$b")
      [ "$ahead" = 0 ] && continue
      s="$ahead commit(s) not pushed"
    elif [ -n "$base" ] && git -C "$repo" merge-base --is-ancestor "$b" "$base"; then
      continue
    else
      s="$(elsewhere "$b") (or squash-merged, then deleted)"
    fi
    case " $KEEP_LOCAL " in *" $b "*) s="local only BY RULE, never push" ;; esac
    others="$others    $b: $s"$'\n'
  done < <(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads)
  if [ -n "$others" ]; then
    echo "  branches with no worktree, not in ${base:-a remote}:"
    printf '%s' "$others"
  fi

  # Open PRs with a one-word CI verdict. An empty rollup is "no CI", never "green".
  if [ -z "$gh_repo" ]; then
    echo "  open PRs: not a GitHub repo (set gh_repo in the config to check)"
  elif ! command -v gh >/dev/null; then
    unknown "gh is not installed: open PRs and CI not checked"
  elif ! prs=$(with_timeout 60 gh pr list -R "$gh_repo" --state open --limit 30 \
    --json number,title,headRefName,isDraft,statusCheckRollup --jq '
      def verdict: [ .statusCheckRollup[]?
                     | if (.status // "COMPLETED") != "COMPLETED" then "PENDING" else (.conclusion // .state // "PENDING") end ]
        | if length == 0 then "no CI"
          elif any(.[]; IN("FAILURE","CANCELLED","TIMED_OUT","ERROR","ACTION_REQUIRED","STARTUP_FAILURE")) then "CI RED"
          elif any(.[]; IN("PENDING","EXPECTED","QUEUED","IN_PROGRESS","")) then "CI running"
          else "CI green" end;
      .[] | "    #\(.number) [\(.headRefName)]\(if .isDraft then " draft" else "" end) \(verdict): \(.title)"' 2>&1); then
    unknown "gh pr list -R $gh_repo failed: $prs"
  elif [ -z "$prs" ]; then
    echo "  open PRs ($gh_repo): none"
  else
    echo "  open PRs ($gh_repo):"
    printf '%s\n' "$prs"
  fi
done

# A multi-repo workspace keeps its docs (CLAUDE.md, trackers, notes/, .claude/) in a repo of its own at the root.
# The trackers are only safe to prune because git keeps what was deleted, so unsaved tracker edits are news too.
if [ "$root_listed" = 0 ]; then
  echo
  echo "== workspace docs (.)"
  top=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)
  if [ -z "$top" ] || ! [ "$top" -ef "$ROOT" ]; then
    echo "  ⚠ not a git repo: tracker history is lost at every rewrite (workflow README, 'Adopt in a new project', step 5)"
  else
    if [ "$FETCH" = 1 ] && git -C "$ROOT" remote get-url origin >/dev/null 2>&1; then
      with_timeout 60 git -C "$ROOT" fetch --quiet origin 2>/dev/null || unknown "git fetch origin failed (workspace docs)"
    fi
    dirty=$(git -C "$ROOT" status --porcelain | wc -l | tr -d ' ')
    last=$(git -C "$ROOT" log -1 --format='%h %cd' --date=format:'%m-%d %H:%M' 2>/dev/null)
    # for-each-ref, not `rev-parse @{upstream}`: with no commit yet, rev-parse echoes the literal "@{upstream}".
    up=$(git -C "$ROOT" for-each-ref --format='%(upstream:short)' "$(git -C "$ROOT" symbolic-ref -q HEAD)" 2>/dev/null)
    if [ -z "$last" ]; then
      echo "  no commit yet, $dirty uncommitted"
    elif [ -n "$up" ] && git -C "$ROOT" rev-parse -q --verify "$up" >/dev/null; then
      rel=$(git -C "$ROOT" rev-list --left-right --count "HEAD...$up" | awk '{ printf "ahead %d / behind %d of", $1, $2 }')
      echo "  $last: $rel $up, $dirty uncommitted"
    else
      echo "  $last: NO upstream (not pushed anywhere), $dirty uncommitted"
    fi
  fi
fi

# Background work started with `systemd-run --user` is a TRANSIENT unit; keep the ones whose working directory or
# command line names this project. Long jobs launched any other way are invisible here: launch them this way.
# /run/systemd/system exists only when systemd runs the machine; WSL and containers often have systemctl without it.
if [ "$UNITS" = 1 ]; then
  echo
  echo "== background (transient user units of this project)"
  if [ ! -d /run/systemd/system ] || ! command -v systemctl >/dev/null; then
    echo "  not tracked: systemd is not running here (UNITS=0 in the config hides this section)"
  elif ! units=$(systemctl --user list-units --type=service,timer --all --plain --no-legend 2>/dev/null | awk '{print $1}'); then
    unknown "systemctl --user list-units failed"
  else
    found=0
    for u in $units; do
      [ "$(systemctl --user show -p Transient --value "$u")" = yes ] || continue
      wd=$(systemctl --user show -p WorkingDirectory --value "$u")
      desc=$(systemctl --user show -p Description --value "$u")
      case "$wd $desc" in *"$ROOT"* | *"$ROOT_TYPED"*) ;; *) continue ;; esac
      state=$(systemctl --user show -p ActiveState --value "$u")
      case $u in
        *.timer) when="next $(systemctl --user show -p NextElapseUSecRealtime --value "$u")" ;;
        *) when=$(systemctl --user show -p StateChangeTimestamp --value "$u")
           when=${when:+since $when}; when=${when:-never started} ;;
      esac
      echo "  $u: $state, $when"
      found=1
    done
    [ "$found" = 0 ] && echo "  none"
  fi
fi

echo
if [ "$FAILED" -gt 0 ]; then
  echo "GROUND TRUTH: INCOMPLETE — $FAILED probe(s) failed, read their sections as UNKNOWN"
  exit 2
fi
echo "GROUND TRUTH: complete"
