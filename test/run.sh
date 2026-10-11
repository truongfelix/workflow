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
for f in bin/adopt.sh template/dot-claude/skills/session-start/ground-truth.sh \
  template/dot-claude/skills/session-start/items.sh template/dot-claude/ground-truth.conf; do
  check "$f has LF line endings" lf_only "$WF/$f"
done

# Claude Code loads a CLAUDE.md, and registers .claude/skills, found in a subfolder of the session's project. Below
# the root of this repo they would be the template's or the example's, taken as rules for working on the workflow:
# they are stored as CLAUDE.template.md, CLAUDE.example.md and dot-claude/ (bin/adopt.sh restores the names).
nested=$(find "$WF" -path "$WF/.git" -prune -o \( -path "$WF/*/CLAUDE.md" -o -path "$WF/*/CLAUDE.local.md" \
  -o -path "$WF/*/.claude/skills" \) -print)
check "no CLAUDE.md or .claude/skills below the repo root" [ -z "$nested" ]

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
check "adopt.sh installs CLAUDE.md and .claude/ under their real names" \
  test -f CLAUDE.md -a -d .claude -a ! -e CLAUDE.template.md -a ! -e dot-claude
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

# The trackers' format check: the template, the example and an adopted project pass; a broken fixture fails on each
# problem, with its line.
IT=.claude/skills/session-start/items.sh
ITS="$WF/template/dot-claude/skills/session-start/items.sh"
"$SH" "$ITS" check "$WF/template/BACKLOG.md" "$WF/template/questions.md" >"$T/it.txt" 2>&1
check "items.sh: the template's trackers pass" [ $? = 0 ]
"$SH" "$ITS" check "$WF/example/BACKLOG.md" "$WF/example/questions.md" >"$T/it.txt" 2>&1
check "items.sh: the example's trackers pass" [ $? = 0 ]
LC_ALL=C "$SH" "$ITS" check "$WF/example/BACKLOG.md" "$WF/example/questions.md" >"$T/it.txt" 2>&1
check "items.sh: the example's trackers pass in the C locale" [ $? = 0 ]
(cd "$T" && "$SH" "$T/ws/$IT" check) >"$T/it.txt" 2>&1
check "items.sh: with no file, it checks the project's trackers, from any directory" [ $? = 0 ]
check "items.sh: adopt.sh makes it executable" [ -x "$T/ws/$IT" ]
"$SH" "$ITS" check "$WF/test/fixtures/broken/BACKLOG.md" "$WF/test/fixtures/broken/questions.md" \
  >"$T/it-broken.txt" 2>&1
rc=$?
sed 's/^/      | /' "$T/it-broken.txt"
check "items.sh: a broken tracker exits 2" [ "$rc" = 2 ]
for problem in 'BACKLOG.md:9: B-1: no `Done when:` line' 'BACKLOG.md:12: B-2: ⏸️ without a `waits:` line' \
  'BACKLOG.md:15: B-2 is given twice' 'BACKLOG.md:19: B-4: unknown field `owner:`' \
  'BACKLOG.md:18: B-4: ⚠ without a `repos:` line' 'BACKLOG.md:24: `### Done:`: not a state' \
  'BACKLOG.md:27: `B-05` is not a B- id' 'BACKLOG.md:33: B-6: text after the `Done when:` paragraph' \
  'BACKLOG.md:3: `next id` is B-3, not above the highest id here, B-6' 'questions.md:5: ⚠ marks a cross-repo' \
  'questions.md:10: Q-1: 🟢 without a `ruled:` line' 'questions.md:14: Q-2: `ruled:` is not a YYYY-MM-DD date' \
  'questions.md:1: no `next id: Q-<n>'; do
  check "items.sh reports ${problem#*: }" has "$T/it-broken.txt" "$problem"
done
"$SH" "$ITS" check "$T/nowhere/BACKLOG.md" >"$T/it-missing.txt" 2>&1
check "items.sh: a file it cannot read exits 2" [ $? = 2 ]
check "items.sh: a file it cannot read says UNKNOWN" has "$T/it-missing.txt" "UNKNOWN: $T/nowhere/BACKLOG.md"

# Two sessions give an id at once (notes/item-format.md, "Two sessions, same number"). The `next id` line names who
# raised it, so the second push conflicts there instead of merging two items with one id.
give_id() { # <clone> <session> <section>: a new item at the top of <section> takes `next id`, which goes up by one
  local n
  n=$(sed -n 's/^next id: B-\([0-9]*\) .*/\1/p' "$1/BACKLOG.md")
  awk -v n="$n" -v who="$2" -v sec="## $3" '
    { sub(/\r$/, "") } # a CRLF checkout (core.autocrlf, as on Windows CI)
    /^next id: / { print "next id: B-" (n + 1) " (last given to claude@" who ")"; next }
    { print }
    $0 == sec { print ""; print "### 🔲 B-" n " Added by " who; print "Done when: it is done." }
  ' "$1/BACKLOG.md" >"$T/give.tmp" && mv "$T/give.tmp" "$1/BACKLOG.md"
}
mkdir "$T/ids" && cd "$T/ids" || exit 1
git_q init --bare remote.git && git -C remote.git symbolic-ref HEAD refs/heads/main
git_q clone remote.git a
git -C a symbolic-ref HEAD refs/heads/main
printf '%s\n' '# Backlog' '' 'next id: B-2 (last given to claude@a)' '' '## api' '' '### 🔲 B-1 An old item' \
  'Done when: it is done.' '' '## web' >a/BACKLOG.md
git -C a add BACKLOG.md && git_q -C a commit -m start && git_q -C a push origin main
git_q clone remote.git b
give_id a a api && git_q -C a commit -am "B-2 by a" && git_q -C a push origin main
give_id b b web && git_q -C b commit -am "B-2 by b"
git_q -C b push origin main
check "two sessions, one number: the second push is rejected" [ $? != 0 ]
git_q -C b pull --rebase origin main
check "two sessions, one number: the rebase stops on a conflict" [ $? != 0 ]
check "two sessions, one number: the conflict is in BACKLOG.md" \
  [ "$(git -C b diff --name-only --diff-filter=U)" = BACKLOG.md ]
# Resolved as the format says: keep the remote's line, renumber the new item from it, raise it again.
git -C b show origin/main:BACKLOG.md >b/BACKLOG.md && give_id b b web
git -C b add BACKLOG.md && git_q -C b -c core.editor=true rebase --continue && git_q -C b push origin main
check "two sessions, one number: after renumbering, the push goes through" [ $? = 0 ]
"$SH" "$ITS" check b/BACKLOG.md >"$T/it-ids.txt" 2>&1
check "two sessions, one number: the result passes the format check" [ $? = 0 ]
check "two sessions, one number: they end with different ids" \
  [ "$(grep -c '^### 🔲 B-2 Added by a$' b/BACKLOG.md)$(grep -c '^### 🔲 B-3 Added by b$' b/BACKLOG.md)" = 11 ]
# The control: two sessions with the same name write the same line, which git merges silently into two items with
# one id. Only the format check sees it.
git_q clone remote.git c && git_q clone remote.git d
give_id c same api && git_q -C c commit -am "B-4 by c" && git_q -C c push origin main
give_id d same web && git_q -C d commit -am "B-4 by d"
git_q -C d pull --rebase origin main
check "the control: the same next id line merges without a conflict" [ $? = 0 ]
"$SH" "$ITS" check d/BACKLOG.md >"$T/it-dup.txt" 2>&1
check "the control: the format check exits 2" [ $? = 2 ]
check "the control: the format check names the id given twice" has "$T/it-dup.txt" "B-4 is given twice"

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) FAILED"
  exit 1
fi
echo "all checks passed"
