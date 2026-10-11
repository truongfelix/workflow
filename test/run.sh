#!/usr/bin/env bash
#
# run.sh — test bin/adopt.sh and ground-truth.sh on a throwaway workspace: a docs repo at the root, a code repo with
# a remote, a worktree, a branch on no remote, a branch kept local by rule, uncommitted work. CI runs it on Linux,
# macOS (/bin/bash 3.2) and Windows (Git Bash, CRLF checkout).
#
# Usage: bash test/run.sh      Exit 0 = every check passed.

set -u
WF=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SH=${BASH:-bash} # run the scripts with the bash running this test
T=$(mktemp -d "${TMPDIR:-/tmp}/workflow-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

failures=0
check() { # <what> <command...>
  if "${@:2}"; then echo "ok    $1"; else echo "FAIL  $1"; failures=$((failures + 1)); fi
}
has() { grep -qF -- "$2" "$1"; }                                # <file> <text>
lacks() { ! grep -qF -- "$2" "$1"; }                             # <file> <text>
lf_only() { [ "$(tr -cd '\r' <"$1" | wc -c | tr -d ' ')" = 0 ]; } # <file>
git_q() { git "$@" >/dev/null 2>&1; }

echo "bash $BASH_VERSION, $(uname -s), $(git --version)"

# A Windows checkout must still give bash LF scripts (.gitattributes).
for f in bin/adopt.sh template/.claude/skills/session-start/ground-truth.sh template/.claude/ground-truth.conf; do
  check "$f has LF line endings" lf_only "$WF/$f"
done

# The workspace: ws/ is the docs repo, ws/api a code repo, ws/api-feat its worktree.
cd "$T" || exit 1
git_q init --bare remote-api.git && git_q init --bare remote-docs.git
mkdir ws && cd ws || exit 1
git_q init && git symbolic-ref HEAD refs/heads/main && git remote add origin "$T/remote-docs.git"
git_q clone "$T/remote-api.git" api && cd api || exit 1
git symbolic-ref HEAD refs/heads/main
git_q commit --allow-empty -m first && git_q push origin main && git remote set-head origin main
git_q commit --allow-empty -m "on main, not pushed"
git_q worktree add ../api-feat -b feat
(cd ../api-feat && git_q commit --allow-empty -m feat && git_q push origin feat &&
  git_q commit --allow-empty -m "feat, not pushed" && echo x >dirty.txt)
git_q checkout -b spike && git_q commit --allow-empty -m spike && git_q checkout main
git branch keepme
cd "$T/ws" || exit 1

"$SH" "$WF/bin/adopt.sh" "$T/ws" --workspace >"$T/adopt.txt" 2>&1
check "adopt.sh exits 0" [ $? = 0 ]
check "adopt.sh installs /session-start" [ -f .claude/skills/session-start/ground-truth.sh ]
check "adopt.sh installs /handoff" [ -f .claude/skills/handoff/SKILL.md ]
check "adopt.sh installs the item format" [ -f notes/item-format.md ]
check "adopt.sh installs the workspace .gitignore" [ -f .gitignore ]
check "adopt.sh lists what is left to FILL" has "$T/adopt.txt" "CLAUDE.md:1:"
"$SH" "$WF/bin/adopt.sh" "$T/ws" --workspace >"$T/adopt2.txt" 2>&1
check "adopt.sh run again exits 0" [ $? = 0 ]
check "adopt.sh run again overwrites nothing" has "$T/adopt2.txt" "CLAUDE.md (identical)"

printf '%s\n' 'REPOS=("api|api|origin||")' 'KEEP_LOCAL="keepme"' 'UNITS=0' >.claude/ground-truth.conf
git add .gitignore CLAUDE.md BACKLOG.md questions.md notes .claude && git_q commit -m docs && git_q push -u origin main
check "the workspace .gitignore keeps the code repos out" [ -z "$(git status --porcelain --untracked-files=all)" ]
check "the workspace .gitignore tracks the item format" [ -n "$(git ls-files notes/item-format.md)" ]

GT=.claude/skills/session-start/ground-truth.sh
"$SH" "$GT" >"$T/gt.txt" 2>&1
rc=$?
sed 's/^/      | /' "$T/gt.txt"
check "ground truth exits 0" [ "$rc" = 0 ]
check "ground truth: main is ahead of its remote" has "$T/gt.txt" "    api [main]: ahead 1 / behind 0 of origin/main"
check "ground truth: worktree path, unpushed commit, uncommitted file" \
  has "$T/gt.txt" "    api-feat [feat]: ahead 1 / behind 0 of the pushed branch, 1 uncommitted"
check "ground truth: a branch on no remote" has "$T/gt.txt" "    spike: LOCAL ONLY: on no remote at all"
check "ground truth: a branch kept local by rule" has "$T/gt.txt" "    keepme: local only BY RULE, never push"
check "ground truth: the docs repo, in sync" has "$T/gt.txt" "ahead 0 / behind 0 of origin/main, 0 uncommitted"
check "ground truth: complete" has "$T/gt.txt" "GROUND TRUTH: complete"

# A probe that fails is UNKNOWN, never clean.
git -C api remote set-url origin "$T/nowhere.git"
"$SH" "$GT" >"$T/gt-broken.txt" 2>&1
check "a failed fetch exits 2" [ $? = 2 ]
check "a failed fetch says UNKNOWN" has "$T/gt-broken.txt" "UNKNOWN: git fetch origin failed"
git -C api remote set-url origin "$T/remote-api.git"

# Through a symlinked path, as with /tmp on macOS (Git Bash copies instead of linking: skip it there).
case $(uname -s) in
  MINGW* | MSYS* | CYGWIN*) ;;
  *)
    ln -s "$T/ws" "$T/link"
    "$SH" "$T/link/$GT" >"$T/gt-link.txt" 2>&1
    check "through a symlink: same worktree path" has "$T/gt-link.txt" "    api-feat [feat]:"
    check "through a symlink: the docs repo is still a repo" lacks "$T/gt-link.txt" "not a git repo"
    ;;
esac

# No systemd running (macOS, Windows, containers): background jobs are reported as not tracked, not as a failure.
if [ ! -d /run/systemd/system ]; then
  sed 's/^UNITS=0$/UNITS=1/' .claude/ground-truth.conf >"$T/conf" && cp "$T/conf" .claude/ground-truth.conf
  "$SH" "$GT" >"$T/gt-units.txt" 2>&1
  check "without systemd: exits 0" [ $? = 0 ]
  check "without systemd: says so" has "$T/gt-units.txt" "not tracked: systemd is not running here"
fi

# The timeout fallback, used when no working GNU timeout is found (stock macOS).
eval "$(sed -n '/^with_timeout()/,/^}/p' "$GT")"
TIMEOUT_CMD=""
start=$SECONDS
with_timeout 2 sleep 30
check "the timeout fallback stops a hung command (exit 124)" [ $? = 124 ]
check "the timeout fallback stops it in time" [ $((SECONDS - start)) -le 6 ]
out=$(with_timeout 5 sh -c 'echo hello; exit 3')
check "the timeout fallback passes the exit code through" [ $? = 3 ]
check "the timeout fallback passes the output through" [ "$out" = hello ]

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) FAILED"
  exit 1
fi
echo "all checks passed"
