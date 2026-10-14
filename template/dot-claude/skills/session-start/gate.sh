#!/usr/bin/env bash
#
# gate.sh — run a repo's gate, keep a receipt of each commit that passed it, and read a commit's CI on GitHub.
#
# A receipt says that a commit, with nothing uncommitted, passed the gate on this machine. It is a file in the
# clone's git directory (gate-receipts/<commit>), shared by its worktrees, never tracked and never pushed: another
# clone runs the gate again. Untracked files are not counted as uncommitted: a build leaves some, and the owner drops
# working files into the tree. A failed run leaves a record beside the receipts (gate-failures/<commit>), which the
# board shows; a later pass on that commit removes it, and a failure never removes a receipt. In the repo at the project
# root, a receipt also holds for the later commits that change only the docs (lib.sh, receipt_of): when docs and code
# share one repo, a handoff or a claim does not call for the gate again.
#
# How the code is checked before a merge (.claude/ground-truth.conf, set by /checks): by a gate (GATES, each repo's
# command), by GitHub CI (GITHUB_CI), both, or nothing yet. The rules the project keeps (GATE_RULES, or a repo's own in REPO_RULES) read the receipts
# and the CI: with "receipt", the pre-push hook refuses a release tag (v*) whose commit has no receipt, or no green
# CI, and refuses it too when GitHub cannot be read; with "merge", the ground truth reports a default branch whose
# last commit has none.
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
#        bash .claude/skills/session-start/gate.sh ci [<repo>] [<rev>]
#        bash .claude/skills/session-start/gate.sh hook [<repo>]
#   run       run the gate of <repo> (a name in GATES) on the commit checked out, and write its receipt if it
#             passes: in the current directory when it is a worktree of that repo, else in the repo's folder (REPOS)
#   check     is there a receipt for <rev> (default: the commit checked out, as for run)?
#   ci        the CI of <rev> (default as for check) on GitHub, for a repo of GITHUB_CI: one line, its verdict first
#             (CI green, CI red, CI running, no CI, not on GitHub), on the GitHub repo of REPOS, else of its remote
#   hook      install the pre-push hook that holds the rule "receipt" in a repo of GATES or GITHUB_CI, or update ours
#             from an earlier release; never over another hook
#   pre-push  the hook itself (gate.sh pre-push <remote> <url>, the refs pushed on stdin): while the repo's rules keep
#             "receipt", refuses a v* tag whose commit has no receipt (a repo of GATES) or no green CI (GITHUB_CI)
#   <repo> can be left out when the current directory is in a repo the command takes, or when it takes only one.
# Exit: run 0 = passed, receipt written; 1 = the gate failed, or the checkout changed while it ran: no receipt; 2 = not
#   run: uncommitted changes (a receipt is for a commit: commit them first).
#   check 0 = a receipt; 1 = none. ci 0 = CI green; 1 = any other verdict. hook 0 = installed, updated, or already there;
#   1 = another hook is there (add the lines printed). pre-push 0 = the push goes; 1 = refused. Any: 2 = a usage
#   error, or nothing could be read (UNKNOWN).

set -uo pipefail
# Each repo is found by its folder. Git runs a hook in a linked worktree with GIT_DIR set to that worktree's: left in
# place, every repo of REPOS would answer with the pushed one's git folder, and the hook would take another repo's
# rules for it (B-88). The hook runs in the pushed checkout's folder, which finds its repo by itself.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

usage() { echo "usage: $0 run [<repo>] | check [<repo>] [<rev>] | ci [<repo>] [<rev>] | hook [<repo>]" >&2; exit 2; }
fail() { echo "UNKNOWN: $*"; exit 2; }
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SELF="$DIR/gate.sh"
ROOT=$(cd "$DIR/../../.." && pwd)
# shellcheck source=lib.sh
. "$DIR/lib.sh" || { echo "UNKNOWN: no $DIR/lib.sh (upgrade the skill's scripts together)"; exit 2; }
REPOS=("$(basename "$ROOT")|.|origin||")
GATES=()
GATE_PASS=()
GITHUB_CI=()
GATE_RULES=""
REPO_RULES=()
# shellcheck source=/dev/null
[ -f "$ROOT/.claude/ground-truth.conf" ] && . "$ROOT/.claude/ground-truth.conf"

in_list() { # <name> <name>...: 0 when the first is one of the others
  local n=$1 x
  shift
  for x in "$@"; do [ "$x" = "$n" ] && return 0; done
  return 1
}

[ $# -ge 1 ] || usage
cmd=$1
shift

# Each repo of REPOS: its name, folder, and GitHub repo (as set there, else from its remote's URL).
R_NAME=() R_DIR=() R_GH=()
for r in ${REPOS[@]+"${REPOS[@]}"}; do
  IFS='|' read -r n d rem _ gh <<<"$r"
  case $d in /*) ;; *) d="$ROOT/$d" ;; esac
  [ -n "$gh" ] || gh=$(github_repo "$d" "${rem:-origin}")
  R_NAME+=("$n") R_DIR+=("$d") R_GH+=("$gh")
done
repo_of() { # <name>: sets ri, its index in REPOS; 1 when REPOS has none of that name
  local i
  for i in ${R_NAME[@]+"${!R_NAME[@]}"}; do [ "${R_NAME[$i]}" = "$1" ] && { ri=$i; return 0; }; done
  return 1
}
# The repos of GATES (with their command) and of GITHUB_CI, each one of REPOS.
G_NAME=() G_CMD=() C_NAME=()
for spec in ${GATES[@]+"${GATES[@]}"}; do
  repo_of "${spec%%|*}" || fail "GATES names ${spec%%|*}, which is not a repo of REPOS in .claude/ground-truth.conf"
  G_NAME+=("${spec%%|*}") G_CMD+=("${spec#*|}")
done
for n in ${GITHUB_CI[@]+"${GITHUB_CI[@]}"}; do
  repo_of "$n" || fail "GITHUB_CI names $n, which is not a repo of REPOS in .claude/ground-truth.conf"
  C_NAME+=("$n")
done

ci_of() { # <GitHub owner/repo> <commit>: its CI on GitHub in a few words (GitHub's rollup of every check on it);
  # exit 2, with the reason, when GitHub cannot be read
  local out
  command -v gh >/dev/null 2>&1 || { echo "gh is not installed"; return 2; }
  out=$(gh api graphql -f owner="${1%%/*}" -f name="${1#*/}" -f oid="$2" -f query='query($owner: String!,
    $name: String!, $oid: GitObjectID!) { repository(owner: $owner, name: $name) { object(oid: $oid) {
    ... on Commit { statusCheckRollup { state } } } } }' \
    --jq '.data.repository.object | if . == null then "absent" else (.statusCheckRollup.state // "none") end' 2>&1) ||
    { echo "gh api failed: $(printf '%s\n' "$out" | head -n 1)"; return 2; }
  case $out in
    SUCCESS) echo "CI green" ;;
    FAILURE | ERROR) echo "CI red" ;;
    PENDING | EXPECTED) echo "CI running" ;;
    none) echo "no CI" ;;
    absent) echo "not on GitHub" ;;
    *) echo "an answer gate.sh does not know: $out"; return 2 ;;
  esac
}

# The hook runs inside the repo being pushed: the rule, then what checks this repo (its entry in REPOS).
if [ "$cmd" = pre-push ]; then
  here=$(git_common_dir .) || {
    cat >/dev/null
    case " $GATE_RULES " in *" receipt "*) echo "gate.sh pre-push: not in a git checkout: push refused" >&2; exit 1 ;; esac
    exit 0
  }
  name="" gh=""
  for i in ${R_NAME[@]+"${!R_NAME[@]}"}; do
    [ "$(git_common_dir "${R_DIR[$i]}")" = "$here" ] && name=${R_NAME[$i]} gh=${R_GH[$i]}
  done
  # The rule is the repo's own (REPO_RULES), else the project's (GATE_RULES); a repo REPOS does not name has the latter.
  case " $(repo_rules "$name") " in *" receipt "*) ;; *) cat >/dev/null; exit 0 ;; esac
  if [ -z "$name" ]; then
    cat >/dev/null
    echo "REFUSED: this repo is not in REPOS of $ROOT/.claude/ground-truth.conf, so what checks a release tag is" \
      "unknown (the gate rule \"receipt\")" >&2
    exit 1
  fi
  gated=0 cid=0
  in_list "$name" ${G_NAME[@]+"${G_NAME[@]}"} && gated=1
  in_list "$name" ${C_NAME[@]+"${C_NAME[@]}"} && cid=1
  refused=0
  while read -r _ lsha rref _; do
    case $rref in refs/tags/v*) ;; *) continue ;; esac
    case $lsha in *[!0]*) ;; *) continue ;; esac # all zeros: the tag is deleted
    c=$(git rev-parse -q --verify "$lsha^{commit}") || continue
    tag=${rref#refs/tags/} short=$(git rev-parse --short "$c")
    if [ "$gated" = 1 ] && ! receipt_of . "$c" "$ROOT"; then
      echo "REFUSED: $tag is on $short, which has not passed the gate here (the gate rule \"receipt\"): check it" \
        "out, run gate.sh run, then push again" >&2
      refused=1
    fi
    [ "$cid" = 1 ] || continue
    if [ -z "$gh" ]; then
      echo "REFUSED: $tag: $name has no GitHub repo (REPOS, or its remote's URL), so its CI cannot be read" >&2
      refused=1
    elif ! v=$(ci_of "$gh" "$c"); then
      echo "REFUSED: $tag: the CI of $short on $gh could not be read ($v), and a tag is never pushed unchecked" >&2
      refused=1
    elif [ "$v" != "CI green" ]; then
      echo "REFUSED: $tag is on $short, whose CI on $gh is not green: $v (the gate rule \"receipt\"): push its" \
        "branch, wait for its CI to pass, then push the tag" >&2
      refused=1
    fi
  done
  exit $refused
fi

pass_of() { # <name>: the pattern its output must match to pass (GATE_PASS), or nothing
  local p
  for p in ${GATE_PASS[@]+"${GATE_PASS[@]}"}; do [ "${p%%|*}" = "$1" ] && echo "${p#*|}"; done
}
here=$(git_common_dir "$PWD" || true)
pick() { # <gate|ci|any> [<name>]: sets g, the index in REPOS of a repo of GATES, of GITHUB_CI, or of either: the one
  # named, else the one holding the current directory, else the only one
  local kind=$1 n list=GATES none="no gate set"
  local -a names
  shift
  case $kind in
    ci) list=GITHUB_CI none="no GitHub CI set" ;;
    any) list="GATES or GITHUB_CI" none="nothing checks the code" ;;
  esac
  names=()
  [ "$kind" = ci ] || names=(${G_NAME[@]+"${G_NAME[@]}"})
  if [ "$kind" != gate ]; then
    for n in ${C_NAME[@]+"${C_NAME[@]}"}; do in_list "$n" ${names[@]+"${names[@]}"} || names+=("$n"); done
  fi
  [ ${#names[@]} -gt 0 ] || fail "$none: $list in .claude/ground-truth.conf names no repo (/checks sets it)"
  g=""
  for n in "${names[@]}"; do
    repo_of "$n"
    if [ -n "${1:-}" ]; then
      [ "$n" = "$1" ] && g=$ri
    elif [ -n "$here" ] && [ "$(git_common_dir "${R_DIR[$ri]}")" = "$here" ]; then
      g=$ri
    fi
  done
  [ -n "$g" ] && return
  [ -n "${1:-}" ] && fail "$1 is not in $list in .claude/ground-truth.conf: ${names[*]}"
  [ ${#names[@]} = 1 ] && { repo_of "${names[0]}"; g=$ri; return; }
  fail "which repo? name one of $list: ${names[*]}"
}
worktree() { # the worktree of repo g to work in: the current one when it belongs to that repo, else its folder
  if [ -n "$here" ] && [ "$(git_common_dir "${R_DIR[$g]}")" = "$here" ]; then git rev-parse --show-toplevel
  else echo "${R_DIR[$g]}"; fi
}
rev_args() { # <gate|ci> [<repo>] [<rev>]: picks the repo, and sets rev (empty: the commit checked out)
  local kind=$1 named=1
  shift
  rev=""
  if [ $# = 1 ]; then
    if [ "$kind" = gate ]; then in_list "$1" ${G_NAME[@]+"${G_NAME[@]}"} || named=0
    else in_list "$1" ${C_NAME[@]+"${C_NAME[@]}"} || named=0; fi
  fi
  if [ $# = 2 ]; then pick "$kind" "$1"; rev=$2
  elif [ $# = 1 ] && [ "$named" = 1 ]; then pick "$kind" "$1"
  else pick "$kind" ""; rev=${1:-}; fi
}

case $cmd in
  run)
    [ $# -le 1 ] || usage
    pick gate "${1:-}"
    name=${R_NAME[$g]} gcmd=""
    for k in "${!G_NAME[@]}"; do [ "${G_NAME[$k]}" = "$name" ] && gcmd=${G_CMD[$k]}; done
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
    pat=$(pass_of "$name")
    echo "GATE: $name at $short, in $wt: $gcmd${pat:+ (passes on a line matching: $pat)}"
    if [ -z "$pat" ]; then
      "${BASH:-bash}" -c "$gcmd"
      rc=$?
    else # shown as it runs, and kept to look for the line
      log=$(mktemp "${TMPDIR:-/tmp}/gate.XXXXXX") || fail "mktemp failed: the gate's output cannot be kept"
      "${BASH:-bash}" -c "$gcmd" 2>&1 | tee "$log"
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
      failures="$(git_common_dir .)/gate-failures"
      { mkdir -p "$failures" &&
        printf 'commit: %s\nrepo: %s\ngate: %s\nfailed: %s\nexit: %s\nwhy: %s\nhost: %s\n' "$sha" "$name" \
          "$gcmd" "$(date '+%Y-%m-%d %H:%M %Z')" "$rc" "$why" "$(hostname 2>/dev/null || uname -n)" \
          >"$failures/$sha"; } 2>/dev/null ||
        echo "  (the failure could not be recorded in $failures)"
      echo "FAILED: the gate of $name $why: no receipt for $short"
      exit 1
    fi
    if [ "$(git rev-parse -q --verify HEAD)" != "$sha" ] ||
      [ -n "$(git status --porcelain --untracked-files=no)" ]; then
      echo "NO RECEIPT: the gate passed, but the checkout changed while it ran (a new commit, or a file it edited):" \
        "run it again on a clean commit"
      exit 1
    fi
    receipts="$(git_common_dir .)/gate-receipts"
    mkdir -p "$receipts" || fail "cannot write $receipts"
    printf 'commit: %s\nrepo: %s\ngate: %s\npassed: %s\nhost: %s\n' "$sha" "$name" "$gcmd" \
      "$(date '+%Y-%m-%d %H:%M %Z')" "$(hostname 2>/dev/null || uname -n)" >"$receipts/$sha" ||
      fail "cannot write $receipts/$sha"
    rm -f "$(git_common_dir .)/gate-failures/$sha"
    echo "RECEIPT: $short passed the gate of $name"
    ;;
  check)
    [ $# -le 2 ] || usage
    rev_args gate "$@"
    wt=$(worktree)
    sha=$(git -C "$wt" rev-parse -q --verify "${rev:-HEAD}^{commit}") || fail "no commit ${rev:-HEAD} in $wt"
    short=$(git -C "$wt" rev-parse --short "$sha")
    if receipt_of "$wt" "$sha" "$ROOT"; then
      when=$(sed -n 's/^passed: //p' "$RECEIPT")
      if [ "$RECEIPT_ON" = "$sha" ]; then echo "RECEIPT: $short passed the gate of ${R_NAME[$g]} on $when"
      else echo "RECEIPT: $short changed only the docs since $(git -C "$wt" rev-parse --short "$RECEIPT_ON"), which" \
        "passed the gate of ${R_NAME[$g]} on $when"; fi
      exit 0
    fi
    echo "NO RECEIPT: $short has not passed the gate of ${R_NAME[$g]} here (gate.sh run ${R_NAME[$g]}, on it)"
    exit 1
    ;;
  ci)
    [ $# -le 2 ] || usage
    rev_args ci "$@"
    wt=$(worktree)
    sha=$(git -C "$wt" rev-parse -q --verify "${rev:-HEAD}^{commit}") || fail "no commit ${rev:-HEAD} in $wt"
    short=$(git -C "$wt" rev-parse --short "$sha")
    gh=${R_GH[$g]}
    [ -n "$gh" ] || fail "${R_NAME[$g]} has no GitHub repo: set it in REPOS, or give it a GitHub remote"
    v=$(ci_of "$gh" "$sha") || fail "the CI of $short on $gh could not be read: $v"
    echo "$v: $short on $gh"
    [ "$v" = "CI green" ]
    ;;
  hook)
    [ $# -le 1 ] || usage
    pick any "${1:-}"
    wt=$(worktree)
    hooks=$(cd "$wt" 2>/dev/null && p=$(git rev-parse --git-path hooks) && mkdir -p "$p" && cd "$p" && pwd -P) ||
      fail "cannot reach the hooks of $wt"
    # The hook runs this script. A checkout without it (in a repo whose docs are beside the code, a branch from before
    # the workflow) lets a branch go, and refuses only a release tag, which nothing there can check.
    hook_text() {
      printf '%s\n' '#!/bin/sh' \
        '# The gate rule "receipt" (.claude/ground-truth.conf): a release tag (v*) is pushed only when its commit' \
        '# passed its checks. Installed by gate.sh hook; delete this file to remove it.' \
        "if [ -f \"$SELF\" ]; then" \
        "  exec bash \"$SELF\" pre-push \"\$@\"" \
        'fi' \
        '# This checkout has no gate.sh (a branch from before the workflow): a branch goes, a release tag waits.' \
        'while read -r _ lsha rref _; do' \
        '  case $lsha in *[!0]*) ;; *) continue ;; esac' \
        '  case $rref in refs/tags/v*)' \
        '    echo "REFUSED: ${rref#refs/tags/}: this checkout has no gate.sh (a branch from before the workflow), so" \' \
        '      "the tag cannot be checked: check out the default branch, then push it again" >&2' \
        '    exit 1 ;;' \
        '  esac' \
        'done'
    }
    verb=installed
    if [ -f "$hooks/pre-push" ]; then
      if ! grep -qF "gate.sh\" pre-push" "$hooks/pre-push"; then
        echo "NOT INSTALLED: $hooks/pre-push is another hook. Make it read git's input once, and pass it on:"
        echo "  input=\$(cat)"
        echo "  printf '%s\\n' \"\$input\" | bash \"$SELF\" pre-push \"\$@\" || exit 1"
        exit 1
      fi
      if [ "$(cat "$hooks/pre-push")" = "$(hook_text)" ]; then
        echo "HOOK: already in $hooks/pre-push"
        exit 0
      fi
      verb=updated # ours, from an earlier release
    fi
    hook_text >"$hooks/pre-push" && chmod +x "$hooks/pre-push" || fail "cannot write $hooks/pre-push"
    echo "HOOK: $verb in $hooks/pre-push"
    ;;
  *) usage ;;
esac
