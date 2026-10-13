# lib.sh — what ground-truth.sh, board.sh, gate.sh and claim.sh share, sourced by each: one definition, so that they
# never disagree on a machine's name, a GitHub repo, a git directory or a CI verdict.
#
# Generic (from the workflow repo): upgrade this file from there; never put project data in it.

# A probe must not hang the session. GNU `timeout` or Homebrew's `gtimeout` if it works (on Windows, System32's
# unrelated timeout.exe can come first on the PATH), else poll and kill (stock macOS).
TIMEOUT_CMD=""
for t in timeout gtimeout; do
  command -v "$t" >/dev/null && "$t" 1 true </dev/null >/dev/null 2>&1 && { TIMEOUT_CMD=$t; break; }
done
with_timeout() { # <seconds> <command...>: exit 124 when it timed out
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

machine_name() { # this machine as a claim names it: CLAIM_MACHINE when set, else "cloud" in a Claude Code cloud
  # session (CLAUDE_CODE_REMOTE=true), else its name (uname -n, up to its first dot); spaces become dashes
  local m=${CLAIM_MACHINE:-}
  [ -z "$m" ] && [ "${CLAUDE_CODE_REMOTE:-}" = true ] && m=cloud
  [ -z "$m" ] && m=$(uname -n 2>/dev/null) && m=${m%%.*}
  printf '%s\n' "${m//[[:space:]]/-}"
}

github_repo() { # <dir> <remote>: the GitHub owner/repo of that remote's URL; nothing when it is not on GitHub
  local u
  u=$(git -C "$1" remote get-url "$2" 2>/dev/null |
    sed -nE 's#^(git@|ssh://git@|https://)github\.com[:/]([^/]+/[^/]+)$#\2#p')
  printf '%s\n' "${u%.git}"
}

git_common_dir() { # <dir>: the git directory that the worktrees of its repo share, as a physical path
  local top d
  top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) && [ -n "$top" ] || return 1
  d=$(git -C "$top" rev-parse --git-common-dir 2>/dev/null) && [ -n "$d" ] || return 1
  case $d in /* | [A-Za-z]:*) ;; *) d="$top/$d" ;; esac
  (cd "$d" && pwd -P)
}

# The CI of an open PR in a few words, for `gh pr list --json number,statusCheckRollup --jq`: CI red, CI running,
# CI green, or no CI (an empty rollup is never "green"). `pr_verdict` is the PR's.
PR_CI_JQ='def pr_verdict: [ .statusCheckRollup[]?
    | if (.status // "COMPLETED") != "COMPLETED" then "PENDING" else (.conclusion // .state // "PENDING") end ]
  | if length == 0 then "no CI"
    elif any(.[]; IN("FAILURE","CANCELLED","TIMED_OUT","ERROR","ACTION_REQUIRED","STARTUP_FAILURE")) then "CI red"
    elif any(.[]; IN("PENDING","EXPECTED","QUEUED","IN_PROGRESS","")) then "CI running"
    else "CI green" end;'
