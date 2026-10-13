#!/usr/bin/env bash
#
# gate.sh — run a repo's gate, and keep a receipt of each commit that passed it.
#
# A receipt says that a commit, with nothing uncommitted, passed the gate on this machine. It is a file in the
# clone's git directory (gate-receipts/<commit>), shared by its worktrees, never tracked and never pushed: another
# clone runs the gate again. Untracked files are not counted as uncommitted: a build leaves some, and the owner drops
# working files into the tree. A failed run leaves a record beside the receipts (gate-failures/<commit>), which the
# board shows; a later pass on that commit removes it, and a failure never removes a receipt.
#
# The gate rules a project keeps (GATE_RULES in .claude/ground-truth.conf, chosen at setup) decide what reads the
# receipts: with "receipt", the pre-push hook refuses a release tag (v*) whose commit has none; with "merge", the
# ground truth reports a default branch whose last commit has none. Each repo's gate command: GATES, there too.
#
# The gate passes when its command exits 0. A command whose exit code is not its verdict (a script that exits 0
# once it has run, green or not, with stages skipped) names the line it prints when it passed: GATE_PASS, an
# extended regular expression matched against its output without colour codes. Then it passes only when it exits
# 0 and a line matches; its output still shows as it runs.
#
# Generic (from the workflow repo): upgrade this file from there; never put project data in it.
#
# Usage: bash .claude/skills/session-start/gate.sh run [<repo>]
#        bash .claude/skills/session-start/gate.sh check [<repo>] [<rev>]
#        bash .claude/skills/session-start/gate.sh hook [<repo>]
#   run       run the gate of <repo> (a name in GATES) on the commit checked out, and write its receipt if it
#             passes: in the current directory when it is a worktree of that repo, else in the repo's folder (REPOS)
#   check     is there a receipt for <rev> (default: the commit checked out, as for run)?
#   hook      install the pre-push hook that holds the rule "receipt" in that repo; never over another hook
#   pre-push  the hook itself (gate.sh pre-push <remote> <url>, the refs pushed on stdin): refuses a v* tag whose
#             commit has no receipt, while GATE_RULES keeps "receipt"
#   <repo> can be left out when the current directory is in a repo of GATES, or when GATES has one entry.
# Exit: run 0 = passed, receipt written; 1 = the gate failed, or the checkout changed while it ran: no receipt.
#   check 0 = a receipt; 1 = none. hook 0 = installed, or already there; 1 = another hook is there (add the lines
#   printed). pre-push 0 = the push goes; 1 = refused. Any: 2 = a usage error, or nothing could be read (UNKNOWN).

set -uo pipefail

usage() { echo "usage: $0 run [<repo>] | check [<repo>] [<rev>] | hook [<repo>]" >&2; exit 2; }
fail() { echo "UNKNOWN: $*"; exit 2; }
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SELF="$DIR/gate.sh"
ROOT=$(cd "$DIR/../../.." && pwd)
REPOS=("$(basename "$ROOT")|.|origin||")
GATES=()
GATE_RULES=""
# shellcheck source=/dev/null
[ -f "$ROOT/.claude/ground-truth.conf" ] && . "$ROOT/.claude/ground-truth.conf"

common_dir() { # <dir>: the git directory that the worktrees of its repo share, as a physical path
  local top d
  top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) && [ -n "$top" ] || return 1
  d=$(git -C "$top" rev-parse --git-common-dir 2>/dev/null) && [ -n "$d" ] || return 1
  case $d in /* | [A-Za-z]:*) ;; *) d="$top/$d" ;; esac
  (cd "$d" && pwd -P)
}

[ $# -ge 1 ] || usage
cmd=$1
shift

# The hook runs inside the repo being pushed, so it needs no GATES entry: only the rule, and the receipts there.
if [ "$cmd" = pre-push ]; then
  case " $GATE_RULES " in *" receipt "*) ;; *) cat >/dev/null; exit 0 ;; esac
  receipts="$(common_dir .)/gate-receipts" ||
    { echo "gate.sh pre-push: not in a git checkout: push refused" >&2; exit 1; }
  refused=0
  while read -r _ lsha rref _; do
    case $rref in refs/tags/v*) ;; *) continue ;; esac
    case $lsha in *[!0]*) ;; *) continue ;; esac # all zeros: the tag is deleted
    c=$(git rev-parse -q --verify "$lsha^{commit}") || continue
    [ -f "$receipts/$c" ] && continue
    echo "REFUSED: ${rref#refs/tags/} is on $(git rev-parse --short "$c"), which has not passed the gate here" \
      "(the gate rule \"receipt\"): check it out, run gate.sh run, then push again" >&2
    refused=1
  done
  exit $refused
fi

# The repos that have a gate: their name, folder and command.
G_NAME=() G_DIR=() G_CMD=() names=""
for spec in ${GATES[@]+"${GATES[@]}"}; do
  name=${spec%%|*} gcmd=${spec#*|} gdir=""
  for r in ${REPOS[@]+"${REPOS[@]}"}; do
    IFS='|' read -r n d _ <<<"$r"
    [ "$n" = "$name" ] || continue
    case $d in /*) gdir=$d ;; *) gdir="$ROOT/$d" ;; esac
  done
  [ -n "$gdir" ] || fail "GATES names $name, which is not a repo of REPOS in .claude/ground-truth.conf"
  G_NAME+=("$name") G_DIR+=("$gdir") G_CMD+=("$gcmd") names="$names${names:+, }$name"
done
[ -n "$names" ] || fail "no gate set: GATES in .claude/ground-truth.conf names none"

pass_of() { # <name>: the pattern its output must match to pass (GATE_PASS), or nothing
  local p
  for p in ${GATE_PASS[@]+"${GATE_PASS[@]}"}; do [ "${p%%|*}" = "$1" ] && echo "${p#*|}"; done
}
here=$(common_dir "$PWD" || true)
is_gated() { # <name>: true when GATES has it
  local k
  for k in "${!G_NAME[@]}"; do [ "${G_NAME[$k]}" = "$1" ] && return 0; done
  return 1
}
pick() { # [<name>]: sets g, the index of the repo in GATES (named, else the one holding the current directory)
  local k
  g=""
  for k in "${!G_NAME[@]}"; do
    if [ -n "${1:-}" ]; then
      [ "${G_NAME[$k]}" = "$1" ] && g=$k
    elif [ -n "$here" ] && [ "$(common_dir "${G_DIR[$k]}")" = "$here" ]; then
      g=$k
    fi
  done
  [ -n "$g" ] && return
  [ -n "${1:-}" ] && fail "no gate for $1: GATES in .claude/ground-truth.conf names $names"
  [ ${#G_NAME[@]} = 1 ] && { g=0; return; }
  fail "which repo? name one of GATES: $names"
}
worktree() { # the worktree of repo g to work in: the current one when it belongs to that repo, else its folder
  if [ -n "$here" ] && [ "$(common_dir "${G_DIR[$g]}")" = "$here" ]; then git rev-parse --show-toplevel
  else echo "${G_DIR[$g]}"; fi
}

case $cmd in
  run)
    [ $# -le 1 ] || usage
    pick "${1:-}"
    wt=$(worktree)
    cd "$wt" 2>/dev/null && git rev-parse --git-dir >/dev/null 2>&1 || fail "$wt is not a git checkout"
    sha=$(git rev-parse -q --verify HEAD) || fail "$wt has no commit yet: a receipt is for a commit"
    short=$(git rev-parse --short HEAD)
    changed=$(git status --porcelain --untracked-files=no)
    if [ -n "$changed" ]; then
      echo "NOT RUN: $wt has uncommitted changes, and a receipt is for a commit: commit them first"
      printf '%s\n' "$changed" | sed 's/^/  /'
      exit 2
    fi
    pat=$(pass_of "${G_NAME[$g]}")
    echo "GATE: ${G_NAME[$g]} at $short, in $wt: ${G_CMD[$g]}${pat:+ (passes on a line matching: $pat)}"
    if [ -z "$pat" ]; then
      "${BASH:-bash}" -c "${G_CMD[$g]}"
      rc=$?
    else # shown as it runs, and kept to look for the line
      log=$(mktemp "${TMPDIR:-/tmp}/gate.XXXXXX") || fail "mktemp failed: the gate's output cannot be kept"
      "${BASH:-bash}" -c "${G_CMD[$g]}" 2>&1 | tee "$log"
      rc=${PIPESTATUS[0]}
    fi
    why=""
    if [ "$rc" != 0 ]; then
      why="exited $rc"
    elif [ -n "$pat" ]; then
      esc=$(printf '\033')
      tr -d '\r' <"$log" | sed "s/${esc}\[[0-9;]*[A-Za-z]//g" >"$log.plain" # into a file: grep -q ends a pipe early
      grep -Eq -- "$pat" "$log.plain" || why="exited 0, but printed no line matching $pat"
    fi
    [ -z "$pat" ] || rm -f "$log" "$log.plain"
    if [ -n "$why" ]; then
      failures="$(common_dir .)/gate-failures"
      { mkdir -p "$failures" &&
        printf 'commit: %s\nrepo: %s\ngate: %s\nfailed: %s\nexit: %s\nwhy: %s\nhost: %s\n' "$sha" "${G_NAME[$g]}" \
          "${G_CMD[$g]}" "$(date '+%Y-%m-%d %H:%M %Z')" "$rc" "$why" "$(hostname 2>/dev/null || uname -n)" \
          >"$failures/$sha"; } 2>/dev/null ||
        echo "  (the failure could not be recorded in $failures)"
      echo "FAILED: the gate of ${G_NAME[$g]} $why: no receipt for $short"
      exit 1
    fi
    if [ "$(git rev-parse -q --verify HEAD)" != "$sha" ] ||
      [ -n "$(git status --porcelain --untracked-files=no)" ]; then
      echo "NO RECEIPT: the gate passed, but the checkout changed while it ran (a new commit, or a file it edited):" \
        "run it again on a clean commit"
      exit 1
    fi
    receipts="$(common_dir .)/gate-receipts"
    mkdir -p "$receipts" || fail "cannot write $receipts"
    printf 'commit: %s\nrepo: %s\ngate: %s\npassed: %s\nhost: %s\n' "$sha" "${G_NAME[$g]}" "${G_CMD[$g]}" \
      "$(date '+%Y-%m-%d %H:%M %Z')" "$(hostname 2>/dev/null || uname -n)" >"$receipts/$sha" ||
      fail "cannot write $receipts/$sha"
    rm -f "$(common_dir .)/gate-failures/$sha"
    echo "RECEIPT: $short passed the gate of ${G_NAME[$g]}"
    ;;
  check)
    [ $# -le 2 ] || usage
    rev=""
    if [ $# = 2 ]; then pick "$1"; rev=$2
    elif [ $# = 1 ] && is_gated "$1"; then pick "$1"
    else pick ""; rev=${1:-}; fi
    wt=$(worktree)
    sha=$(git -C "$wt" rev-parse -q --verify "${rev:-HEAD}^{commit}") || fail "no commit ${rev:-HEAD} in $wt"
    short=$(git -C "$wt" rev-parse --short "$sha")
    receipt="$(common_dir "$wt")/gate-receipts/$sha"
    if [ -f "$receipt" ]; then
      echo "RECEIPT: $short passed the gate of ${G_NAME[$g]} on $(sed -n 's/^passed: //p' "$receipt")"
      exit 0
    fi
    echo "NO RECEIPT: $short has not passed the gate of ${G_NAME[$g]} here (gate.sh run ${G_NAME[$g]}, on it)"
    exit 1
    ;;
  hook)
    [ $# -le 1 ] || usage
    pick "${1:-}"
    wt=$(worktree)
    hooks=$(cd "$wt" 2>/dev/null && p=$(git rev-parse --git-path hooks) && mkdir -p "$p" && cd "$p" && pwd -P) ||
      fail "cannot reach the hooks of $wt"
    if [ -f "$hooks/pre-push" ]; then
      if grep -qF "gate.sh\" pre-push" "$hooks/pre-push"; then
        echo "HOOK: already in $hooks/pre-push"
        exit 0
      fi
      echo "NOT INSTALLED: $hooks/pre-push is another hook. Make it read git's input once, and pass it on:"
      echo "  input=\$(cat)"
      echo "  printf '%s\\n' \"\$input\" | bash \"$SELF\" pre-push \"\$@\" || exit 1"
      exit 1
    fi
    printf '%s\n' '#!/bin/sh' \
      '# The gate rule "receipt" (.claude/ground-truth.conf): a release tag (v*) is pushed only when its commit' \
      '# passed the gate here. Installed by gate.sh hook; delete this file to remove it.' \
      "exec bash \"$SELF\" pre-push \"\$@\"" >"$hooks/pre-push" && chmod +x "$hooks/pre-push" ||
      fail "cannot write $hooks/pre-push"
    echo "HOOK: installed in $hooks/pre-push"
    ;;
  *) usage ;;
esac
