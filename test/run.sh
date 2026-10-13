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
  template/dot-claude/skills/session-start/items.sh template/dot-claude/skills/session-start/board.sh \
  template/dot-claude/skills/session-start/claim.sh template/dot-claude/ground-truth.conf; do
  check "$f has LF line endings" lf_only "$WF/$f"
done

# Claude Code loads a CLAUDE.md, and registers .claude/skills, found in a subfolder of the session's project. Below
# the root of this repo they would be the template's or the example's, taken as rules for working on the workflow:
# they are stored as CLAUDE.template.md, CLAUDE.example.md and dot-claude/ (bin/adopt.sh restores the names).
nested=$(find "$WF" -path "$WF/.git" -prune -o \( -path "$WF/*/CLAUDE.md" -o -path "$WF/*/CLAUDE.local.md" \
  -o -path "$WF/*/.claude/skills" \) -print)
check "no CLAUDE.md or .claude/skills below the repo root" [ -z "$nested" ]

# What Claude does alone: one table in CLAUDE.md, the only place where a skill learns whether to ask first. The
# template's rows all ask first until the owner chooses; the example has the same rows; a row a skill names exists.
rows() { # <CLAUDE.md>: the table's rows, "| <step> | <answer> |"
  sed -n '/^## What Claude does alone/,/^## /p' "$1" | tr -d '\r' | grep '^| ' | grep -v '^| Step | Here |$'
}
steps() { rows "$1" | sed 's/^| \(.*\) | [^|]* |$/\1/'; } # <CLAUDE.md>: the steps alone
CT="$WF/template/CLAUDE.template.md" CE="$WF/example/CLAUDE.example.md"
SKILLS=("$WF/template/dot-claude/skills/session-start/SKILL.md" "$WF/template/dot-claude/skills/handoff/SKILL.md")
check "the template's table has its rows" [ "$(rows "$CT" | wc -l | tr -d ' ')" -ge 10 ]
check "the template's table asks first on every row" [ -z "$(rows "$CT" | grep -v '| ask first |$')" ]
check "the example's table answers each row with ask first or do, then tell" \
  [ -z "$(rows "$CE" | grep -v -e '| ask first |$' -e '| do, then tell |$')" ]
check "the example's table has the template's rows" [ "$(steps "$CE")" = "$(steps "$CT")" ]
check "no fixed rule for asking left beside the table" lacks "$CT" "Outward actions need"
for f in "${SKILLS[@]}"; do
  check "${f#"$WF"/}: no rule of its own for asking" lacks "$f" "handoff rule"
done
for r in "Start the day's task after the brief" "Commit the docs" "Push the docs" "Add an item to the backlog" \
  "Claim an item" "Commit code" "Push a work branch" "Stop a background job this session started"; do
  check "the row \"$r\", named by a skill, is in the table" \
    eval 'steps "$CT" | grep -q "^$r" && cat "${SKILLS[@]}" | grep -qF "\"$r\""'
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
check "adopt.sh installs CLAUDE.md and .claude/ under their real names" \
  test -f CLAUDE.md -a -d .claude -a ! -e CLAUDE.template.md -a ! -e dot-claude
check "adopt.sh installs the item format" [ -f notes/item-format.md ]
check "adopt.sh installs the handoff format and the handoffs' folder" \
  test -f notes/handoff-format.md -a -f notes/handoff/README.md
check "adopt.sh installs no single handoff and no archive" test ! -e notes/handoff.md -a ! -e notes/handoff-archive.md
check "adopt.sh installs the workspace .gitignore" [ -f .gitignore ]
check "adopt.sh lists what is left to FILL" has "$T/adopt.txt" "CLAUDE.md:1:"
check "adopt.sh lists the table of what Claude does alone as left to FILL" has "$T/adopt.txt" \
  "FILL: ask the owner for a preset"
"$SH" "$WF/bin/adopt.sh" "$T/ws" --workspace >"$T/adopt2.txt" 2>&1
check "adopt.sh run again exits 0" [ $? = 0 ]
check "adopt.sh run again overwrites nothing" has "$T/adopt2.txt" "CLAUDE.md (identical)"
check "adopt.sh run again still lists what is left to FILL" has "$T/adopt2.txt" "  CLAUDE.md:1:"

# .claude/workflow-version names the release taken: its tag, or the tag and the commits since; with no tag, the
# commit and its date; outside a checkout of the workflow (an archive unpacked in another repo), unversioned. On a
# copy of the workflow, since CI checks out one commit and no tag.
mkdir -p "$T/wf-copy" && cp -R "$WF/bin" "$WF/template" "$WF/workspace" "$T/wf-copy/" && cd "$T/wf-copy" || exit 1
adopted() { # <workflow copy> <project>: the version file it writes
  "$SH" "$1/bin/adopt.sh" "$2" >/dev/null 2>&1 && cat "$2/.claude/workflow-version"
}
git_q init && git_q add -A && git_q commit -m "a release"
check "workflow-version: no tag, the commit and its date" \
  eval 'adopted "$T/wf-copy" "$T/ver0" | grep -qE "^workflow [0-9a-f]{7,} [0-9]{4}-[0-9]{2}-[0-9]{2}, adopted "'
git_q tag -a v1.0.0 -m v1.0.0
check "workflow-version: adopted from the v1.0.0 tag, v1.0.0" \
  eval 'adopted "$T/wf-copy" "$T/ver1" | grep -q "^workflow v1.0.0, adopted [0-9-]*$"'
git_q commit --allow-empty -m "after the release"
check "workflow-version: a commit after v1.0.0, the tag and the commits since" \
  eval 'adopted "$T/wf-copy" "$T/ver2" | grep -qE "^workflow v1\.0\.0-1-g[0-9a-f]{7,}, adopted "'
mkdir -p "$T/outer" && git -C "$T/outer" init -q && git -C "$T/outer" commit -q --allow-empty -m outer &&
  cp -R "$T/wf-copy" "$T/outer/wf" && rm -rf "$T/outer/wf/.git"
check "workflow-version: an archive unpacked in another repo, unversioned" \
  eval 'adopted "$T/outer/wf" "$T/ver3" | grep -q "^workflow unversioned, adopted "'
cd "$T/ws" || exit 1

printf '%s\n' 'REPOS=("api|api|origin||")' 'KEEP_LOCAL="keepme"' 'UNITS=0' >.claude/ground-truth.conf
git add .gitignore CLAUDE.md BACKLOG.md questions.md notes .claude && git_q commit -m docs && git_q push -u origin main
check "the workspace .gitignore keeps the code repos out" [ -z "$(git status --porcelain --untracked-files=all)" ]
check "the workspace .gitignore tracks the item format" [ -n "$(git ls-files notes/item-format.md)" ]
check "the workspace .gitignore tracks the handoffs' folder" [ -n "$(git ls-files notes/handoff/README.md)" ]

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
check "ground truth: no claim" eval 'grep -A1 "^== claims (BACKLOG.md, shared on origin/main)$" "$T/gt.txt" | grep -qx "  none"'

# Claims: B-11 on a live branch, B-12 on a branch that is gone, B-13 on a branch with no commit since January (claimed
# then too), B-14 claimed here and not pushed.
old=$(GIT_COMMITTER_DATE=2026-01-02T10:00:00 git -C api commit-tree 'HEAD^{tree}' -p HEAD -m old)
git -C api branch old "$old"
cp BACKLOG.md "$T/ws-backlog.bak"
claims_backlog() { # [<B-14's claim>]
  printf '%s\n' '# Demo — Backlog' '' 'next id: B-15 (last given to claude@ws)' '' '## api' '' '### 🔲 B-11 Live' \
    'claimed: claude@ws on feat' 'Done when: done.' '' '### 🔲 B-12 Gone' 'claimed: claude@other on feat/gone' \
    'Done when: done.' '' '### 🔲 B-13 Old' 'claimed: claude@other on old' 'Done when: done.' '' '### 🔲 B-14 Mine' \
    ${1:+"$1"} 'Done when: done.'
}
claims_backlog >BACKLOG.md
git add BACKLOG.md && GIT_COMMITTER_DATE=2026-01-02T10:00:00 git_q commit -m claims && git_q push origin main
claims_backlog 'claimed: claude@ws on spike' >BACKLOG.md
"$SH" "$GT" >"$T/gt-claims.txt" 2>&1
rc=$?
sed 's/^/      | /' "$T/gt-claims.txt"
check "ground truth, claims: exits 0, a stale claim is a finding" [ "$rc" = 0 ]
check "ground truth, claims: a claim, its branch, its repo, pushed or not" \
  eval 'has "$T/gt-claims.txt" "  B-11 Live: claude@ws on feat" && has "$T/gt-claims.txt" ", ahead 1 / behind 0 of origin/feat"'
check "ground truth, claims: a branch that is gone" has "$T/gt-claims.txt" "      ⚠ GONE: no branch feat/gone in api"
check "ground truth, claims: a stale claim" has "$T/gt-claims.txt" \
  "      api: last commit 01-02 10:00, LOCAL ONLY: on no remote at all, ⚠ STALE: no commit for "
check "ground truth, claims: a live claim is not stale" [ "$(grep -c STALE "$T/gt-claims.txt")" = 1 ]
check "ground truth, claims: a claim not pushed" has "$T/gt-claims.txt" \
  "  B-14 Mine: claude@ws on spike, ⚠ NOT PUSHED: no other session sees it"
cp "$T/ws-backlog.bak" BACKLOG.md && git add BACKLOG.md && git_q commit -m "no claims" && git_q push origin main

# questions.md: its size and its rulings; longer than QUESTIONS_TRIM_LINES (150 when unset), flagged for the trim pass
# of /handoff; 0 turns the flag off.
check "ground truth, questions.md: its size, under the default threshold" \
  eval 'grep -A1 "^== questions.md (trim above 150 lines)$" "$T/gt.txt" | grep -q "^  [0-9]* lines, 0 ruling(s) in §2$"'
cp questions.md "$T/ws-questions.bak" && cp .claude/ground-truth.conf "$T/ws-conf.bak"
printf '%s\n' '# Demo — questions' '' 'next id: Q-4 (last given to claude@ws)' '' '# 1. Open decisions' '' \
  '### 💬 Q-3 Which one?' 'The question.' '' '# 2. Rulings' '' '### 🟢 Q-1 Never X' 'ruled: 2026-01-02' \
  'Owner: "no X".' '' '### 🟢 Q-2 Always Y' 'ruled: 2026-01-03' 'Owner: "always Y".' >questions.md
qn=$(wc -l <questions.md | tr -d ' ')
echo "QUESTIONS_TRIM_LINES=$((qn - 1))" >>.claude/ground-truth.conf
"$SH" "$GT" --no-fetch >"$T/gt-trim.txt" 2>&1
check "ground truth, questions.md: above the threshold, flagged for a trim, its rulings counted" has "$T/gt-trim.txt" \
  "  ⚠ TRIM: $qn lines, 2 ruling(s) in §2: /handoff proposes a trim pass"
echo "QUESTIONS_TRIM_LINES=$qn" >>.claude/ground-truth.conf
"$SH" "$GT" --no-fetch >"$T/gt-trim.txt" 2>&1
check "ground truth, questions.md: at the threshold, not flagged" \
  eval 'has "$T/gt-trim.txt" "  $qn lines, 2 ruling(s) in §2" && lacks "$T/gt-trim.txt" TRIM:'
echo "QUESTIONS_TRIM_LINES=0" >>.claude/ground-truth.conf
"$SH" "$GT" --no-fetch >"$T/gt-trim.txt" 2>&1
check "ground truth, questions.md: 0 turns the trim off" \
  eval 'has "$T/gt-trim.txt" "== questions.md (no trim: QUESTIONS_TRIM_LINES=0)" && lacks "$T/gt-trim.txt" TRIM:'
cp "$T/ws-questions.bak" questions.md && cp "$T/ws-conf.bak" .claude/ground-truth.conf
check "/handoff runs the trim pass on the flag of the ground truth" \
  has "$WF/template/dot-claude/skills/handoff/SKILL.md" '**Trim `questions.md`** when the ground truth (step 1) says `⚠ TRIM`'
check "the template's ground-truth.conf sets the trim threshold" \
  grep -qx 'QUESTIONS_TRIM_LINES=150' "$WF/template/dot-claude/ground-truth.conf"

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
"$SH" "$ITS" check "$WF/template/BACKLOG.md" "$WF/template/questions.md" "$WF/template/notes/lessons.md" \
  >"$T/it.txt" 2>&1
check "items.sh: the template's trackers and lessons pass" [ $? = 0 ]
EX=("$WF/example/BACKLOG.md" "$WF/example/questions.md" "$WF/example/notes/lessons.md"
  "$WF/example/notes/handoff/README.md" "$WF/example/notes/handoff/pantry.md")
"$SH" "$ITS" check "${EX[@]}" >"$T/it.txt" 2>&1
check "items.sh: the example's trackers, lessons and handoff pass" [ $? = 0 ]
check "items.sh: the example's lessons and handoff are read" has "$T/it.txt" "OK: 13 item(s)"
LC_ALL=C "$SH" "$ITS" check "${EX[@]}" >"$T/it.txt" 2>&1
check "items.sh: the example's trackers, lessons and handoff pass in the C locale" [ $? = 0 ]
TS="$WF/test/fixtures/two-sessions"
"$SH" "$ITS" check "$TS/BACKLOG.md" "$TS/questions.md" "$TS/notes/handoff/README.md" "$TS/notes/handoff/api-fix.md" \
  "$TS/notes/handoff/web-offline.md" >"$T/it.txt" 2>&1
check "items.sh: two sessions' handoffs pass" [ $? = 0 ]
check "items.sh: two sessions' handoffs are both read" has "$T/it.txt" "OK: 5 item(s)"
(cd "$T" && "$SH" "$T/ws/$IT" check) >"$T/it.txt" 2>&1
check "items.sh: with no file, it checks the project's trackers, from any directory" [ $? = 0 ]
cp "$T/ws/notes/lessons.md" "$T/lessons.bak" && printf '%s\n' '## Git' '- A lesson with no id.' >>"$T/ws/notes/lessons.md"
(cd "$T" && "$SH" "$T/ws/$IT" check) >"$T/it.txt" 2>&1
check "items.sh: with no file, it checks the lessons too" has "$T/it.txt" "notes/lessons.md:"
cp "$T/lessons.bak" "$T/ws/notes/lessons.md"
printf '%s\n' '# H-1 2026-10-12 18:40 CEST · claude@ws' '' '## Next' '1. B-1 An item that does not exist' '' \
  '## Waiting for the user' 'None.' '' '## Running' 'None.' '' '## Unfinished' 'None.' '' '## Done' 'None.' '' \
  '## Learned' 'None.' >"$T/ws/notes/handoff/ws.md"
(cd "$T" && "$SH" "$T/ws/$IT" check) >"$T/it.txt" 2>&1
check "items.sh: with no file, it checks the handoffs too" has "$T/it.txt" "notes/handoff/ws.md:4: H-1: B-1 is in no tracker"
rm "$T/ws/notes/handoff/ws.md"
check "items.sh: adopt.sh makes it executable" [ -x "$T/ws/$IT" ]
BR="$WF/test/fixtures/broken"
"$SH" "$ITS" check "$BR/BACKLOG.md" "$BR/questions.md" "$BR/lessons.md" "$BR/notes/handoff/README.md" \
  "$BR/notes/handoff/web.md" >"$T/it-broken.txt" 2>&1
rc=$?
sed 's/^/      | /' "$T/it-broken.txt"
check "items.sh: a broken tracker exits 2" [ "$rc" = 2 ]
for problem in 'BACKLOG.md:9: B-1: no `Done when:` line' 'BACKLOG.md:12: B-2: ⏸️ without a `waits:` line' \
  'BACKLOG.md:15: B-2 is given twice' 'BACKLOG.md:19: B-4: unknown field `owner:`' \
  'BACKLOG.md:18: B-4: ⚠ without a `repos:` line' 'BACKLOG.md:24: `### Done:`: not a state' \
  'BACKLOG.md:27: `B-05` is not a B- id' 'BACKLOG.md:33: B-6: text after the `Done when:` paragraph' \
  'BACKLOG.md:3: `next id` is B-3, not above the highest id here, B-7' 'questions.md:5: ⚠ marks a cross-repo' \
  'questions.md:10: Q-1: 🟢 without a `ruled:` line' 'questions.md:14: Q-2: `ruled:` is not a YYYY-MM-DD date' \
  'questions.md:1: no `next id: Q-<n>' 'lessons.md:8: L-1 is given twice' \
  'lessons.md:11: `### 🔲`: a lesson is `### L-<n> <title>`, with no state' 'lessons.md:16: a lesson without an id' \
  'lessons.md:19: L-3: unknown field `owner:`' 'lessons.md:22: ⚠ marks a cross-repo BACKLOG item, not a lesson' \
  'lessons.md:1: no `next id: L-<n>' 'web.md:1: H-4: the file is not named after its session' \
  'web.md:2: H-4: `continues: H-7`: it names an older handoff' 'web.md:3: H-4: unknown field `owner:`' \
  'web.md:6: H-4: a task in Next without an id' 'web.md:7: H-4: B-99 is in no tracker' \
  'web.md:12: H-4: no `## Running` before `## Unfinished`' 'web.md:15: H-4: `## Done` is empty' \
  'web.md:17: H-4: `## Notes` is not a section of a handoff' 'web.md:18: H-4: no `## Learned` section' \
  'BACKLOG.md:36: B-7: `claimed:` is not `<agent>@<session> on <branch>`: claude@web' \
  'handoff/README.md:3: `next id` is H-3, not above the highest handoff, H-4'; do
  check "items.sh reports ${problem#*: }" has "$T/it-broken.txt" "$problem"
done
"$SH" "$ITS" check "$T/nowhere/BACKLOG.md" >"$T/it-missing.txt" 2>&1
check "items.sh: a file it cannot read exits 2" [ $? = 2 ]
check "items.sh: a file it cannot read says UNKNOWN" has "$T/it-missing.txt" "UNKNOWN: $T/nowhere/BACKLOG.md"

# items.sh list: the records the board reads. A heading it cannot read is kept as written, never dropped.
tab=$(printf '\t')
"$SH" "$ITS" list "$WF/example/BACKLOG.md" "$WF/example/questions.md" >"$T/list.txt" 2>&1
check "items.sh list: the example exits 0" [ $? = 0 ]
check "items.sh list: one record per item" [ "$(grep -c "^I$tab" "$T/list.txt")" = 9 ]
check "items.sh list: an item with its state, ⚠, section, title and fields" \
  has "$T/list.txt" "${tab}B-14${tab}open${tab}1${tab}web${tab}Show which ingredient matched a search${tab}repos: api → web$tab"
check "items.sh list: a question with its repos" has "$T/list.txt" "${tab}Q-2${tab}ruling${tab}0$tab"
"$SH" "$ITS" list "$WF/example/notes/lessons.md" >"$T/list-lessons.txt" 2>&1
check "items.sh list: a lesson, with its section and title" \
  has "$T/list-lessons.txt" "${tab}L-3${tab}lesson${tab}0${tab}Git${tab}Stacked PRs target main$tab$tab"
"$SH" "$ITS" list "${EX[@]}" >"$T/list-handoff.txt" 2>&1
check "items.sh list: a handoff, with its date, session and the handoff it continues" has "$T/list-handoff.txt" \
  "${tab}H-9${tab}handoff${tab}0$tab${tab}2026-10-09 18:40 CEST · claude@pantry${tab}continues: H-8$tab## Next\n1. B-7 "
"$SH" "$ITS" list "$WF/test/fixtures/broken/BACKLOG.md" >"$T/list-broken.txt" 2>&1
check "items.sh list: a broken tracker exits 2" [ $? = 2 ]
check "items.sh list: a heading that is not an item is kept as written" has "$T/list-broken.txt" \
  "U$tab$WF/test/fixtures/broken/BACKLOG.md${tab}24$tab### Done: a heading that is not an item\nDone when: never."
check "items.sh list: the problems, as records" has "$T/list-broken.txt" "P$tab$WF/test/fixtures/broken/BACKLOG.md${tab}9${tab}B-1:"

# The board: a project with two repos and a history. B-1 is added then closed, B-2 goes from open to waiting, B-3
# exists only on disk; B-2's text holds what could break the page: quotes, a backslash, a closing script tag.
BD="$WF/template/dot-claude/skills/session-start/board.sh"
mkdir -p "$T/board/.claude" && cd "$T/board" || exit 1
git_q init && git symbolic-ref HEAD refs/heads/main
printf '%s\n' 'REPOS=("api|api|origin||" "web|web|origin||")' >.claude/ground-truth.conf
backlog() { # <B-2 state> <B-2 field>, then the items to add after it
  printf '%s\n' '# Demo — Backlog' '' "next id: B-4 (last given to claude@test)" '' '## api' ''
  [ "$1" = closed ] || printf '%s\n' '### 🔲 B-1 First' 'Done when: done.' ''
  printf '%s\n' '## web' '' "### $2 B-2 Second" "$3" 'Says "hi" \o/, </script> and */ to the page.' 'Done when: done.' "${@:4}"
}
backlog open 🔲 "" >BACKLOG.md
printf '%s\n' '# Demo — questions' '' 'next id: Q-2 (last given to claude@test)' '' '# 1. Open decisions' '' \
  '### 💬 Q-1 Which one?' 'repos: api, web' 'The question.' >questions.md
git add -A && GIT_COMMITTER_DATE=2026-01-02T10:00:00 git_q commit -m "two items"
backlog closed ⏸️ "waits: the API" >BACKLOG.md
GIT_COMMITTER_DATE=2026-02-03T10:00:00 git_q commit -am "B-1 done, B-2 waits"
backlog closed ⏸️ "waits: the API" '' '### 🔲 B-3 Third' 'Done when: done.' >BACKLOG.md
"$SH" "$BD" --no-open --out "$T/board.html" "$T/board" >"$T/board.txt" 2>&1
check "board.sh exits 0" [ $? = 0 ]
check "board.sh prints where the page is" has "$T/board.txt" "Board: $T/board.html"
item_has() { grep -F "\"id\":\"$1\"," "$T/board.html" | grep -qF -- "$2"; } # <id> <text>: on that item's line
check "board: the project's name and its repos" has "$T/board.html" '{"project":"Demo",'
check "board: the repos come from ground-truth.conf" has "$T/board.html" '"repos":["api","web"]'
check "board: an open item, its section, its date added" \
  item_has B-2 '"state":"waiting","cross":0,"section":"web","title":"Second","fields":"waits: the API",'
check "board: the date an item was added" item_has B-2 '"added":"2026-01-02","changed":"2026-02-03","closed":""'
check "board: a state change in the history" item_has B-2 '["2026-02-03","'
check "board: how it changed" item_has B-2 '"B-1 done, B-2 waits","open → waiting"]'
check "board: a deleted item comes back as closed, with its date" item_has B-1 '"closed":"2026-02-03"'
check "board: a closed item keeps its last text" item_has B-1 '"title":"First"'
check "board: an item not committed yet" item_has B-3 '"not committed yet","added"]'
check "board: a question's repos" item_has Q-1 '"fields":"repos: api, web"'
check "board: claimed is a column of the backlog, not a state" \
  eval 'has "$T/board.html" "(S.tab === \"B\" ? \"<th>Claimed</th>\" : \"\")" && lacks "$T/board.html" "[\"claimed\", \"🔲\", \"claimed\"]"'
check "board: text cannot end the page's script early" [ "$(grep -c '</script>' "$T/board.html")" = 2 ]
if command -v node >/dev/null 2>&1; then
  node -e 'var h = require("fs").readFileSync(process.argv[1], "utf8");
    var d = JSON.parse(h.split("<script id=\"data\" type=\"application/json\">")[1].split("</script>")[0]);
    var b = d.items.filter(function (i) { return i.id === "B-2"; })[0];
    process.exit(d.items.length === 4 && b.body.indexOf("Says \"hi\" \\o/, </script> and */ to the page.") === 0 ? 0 : 1);' "$T/board.html"
  check "board: the data parses as JSON, the text intact" [ $? = 0 ]
fi
mkdir "$T/nogit" && cp "$WF/example/BACKLOG.md" "$WF/example/questions.md" "$T/nogit/"
(cd "$T" && "$SH" "$BD" --no-open --out "$T/nogit.html" "$T/nogit") >"$T/nogit.txt" 2>&1
check "board: a folder with no git still gets a page" [ $? = 0 ]
check "board: without git, it says so" has "$T/nogit.html" '"git":false'
"$SH" "$BD" --no-open --out "$T/broken.html" "$WF/test/fixtures/broken" >/dev/null 2>&1
check "board: broken trackers still get a page" [ $? = 0 ]
check "board: a heading it cannot read is on the page, as written" has "$T/broken.html" \
  '"type":"U","file":"BACKLOG.md","line":24,"text":"### Done: a heading that is not an item\nDone when: never."'
"$SH" "$BD" --no-open "$T/nowhere" >"$T/board-missing.txt" 2>&1
check "board: no trackers exits 2" [ $? = 2 ]
check "board: no trackers says UNKNOWN" has "$T/board-missing.txt" "UNKNOWN"
check "board: adopt.sh makes it executable" [ -x "$T/ws/.claude/skills/session-start/board.sh" ]

# Commits and PRs: a code repo whose commit names B-1, quoted by its hash in B-1, and a fake gh that knows the code
# repo's PRs and fails for the docs repo's.
mkdir "$T/board2-api" && cd "$T/board2-api" || exit 1
git_q init && git symbolic-ref HEAD refs/heads/main && git remote add origin https://github.com/demo/api.git
GIT_COMMITTER_DATE=2026-02-02T10:00:00 git_q commit --allow-empty -m "Round small quantities up to 1 g" \
  -m "A pinch of salt rounded to 0 g (B-1)."
api_sha=$(git rev-parse HEAD)
mkdir "$T/fakebin"
cat >"$T/fakebin/gh" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"-R demo/api "*) printf '41\tRound to 1 g\tMERGED\tfix/B-1-rounding\tmain\t2026-02-01T09:00:00Z\t2026-02-02T10:00:00Z\t2026-02-02T10:00:00Z\thttps://github.com/demo/api/pull/41\tdev\t$api_sha\tFixes B-1.\\\\nA pinch of salt keeps 1 g.\n' ;;
  *) echo "HTTP 404: Not Found" >&2; exit 1 ;;
esac
EOF
chmod +x "$T/fakebin/gh"

# The board's lessons and handoffs: L-2 is dropped; a 1.x notes/handoff.md is replaced by the session s1's H-1, which
# H-2 replaces.
mkdir -p "$T/board2/notes" && cd "$T/board2" || exit 1
git_q init && git symbolic-ref HEAD refs/heads/main && git remote add origin https://github.com/demo/docs.git
printf '%s\n' '# Demo — Backlog' '' 'next id: B-2 (last given to claude@s1)' '' '## api' '' '### 🔲 B-1 First' \
  "Fixed by ${api_sha:0:7}, see #41." 'Done when: done.' >BACKLOG.md
printf '%s\n' '# Demo — questions' '' 'next id: Q-1 (none given yet)' >questions.md
lessons() { printf '%s\n' '# Lessons' '' 'next id: L-3 (last given to claude@s1)' '' '## Git' '' "$@"; }
lessons '### L-1 Kept' 'A rule.' '' '### L-2 Dropped later' 'A rule.' >notes/lessons.md
printf '%s\n' '# Handoff (2026-01-02 10:00 CET)' '' '## Next' '1. B-1 First' >notes/handoff.md
git add -A && GIT_COMMITTER_DATE=2026-01-02T10:00:00 git_q commit -m "start, 1.x handoff"
lessons '### L-1 Kept' 'A rule.' >notes/lessons.md
git rm -q notes/handoff.md && mkdir notes/handoff
printf '%s\n' '# Handoffs' '' 'next id: H-2 (last given to claude@s1)' >notes/handoff/README.md
handoff() { # <id> <continues line or "">
  printf '%s\n' "# $1 2026-02-03 18:00 CET · claude@s1" ${2:+"$2"} '' '## Next' '1. B-1 First: go on.' '' \
    '## Waiting for the user' 'None.' '' '## Running' 'None.' '' '## Unfinished' 'None.' '' '## Done' 'None.' '' \
    '## Learned' 'L-1 Kept.'
}
handoff H-1 >notes/handoff/s1.md
git add -A && GIT_COMMITTER_DATE=2026-02-03T18:00:00 git_q commit -m "H-1 Handoff, L-2 dropped"
sed 's/^next id: H-2 .*/next id: H-3 (last given to claude@s1)/' notes/handoff/README.md >"$T/r" && mv "$T/r" notes/handoff/README.md
handoff H-2 "continues: H-1" >notes/handoff/s1.md
git add -A && GIT_COMMITTER_DATE=2026-03-04T18:00:00 git_q commit -m "H-2 Handoff" -m "The second day."
"$SH" "$BD" --no-open --out "$T/board2.html" "$T/board2" >"$T/board2.txt" 2>&1
check "board, lessons and handoffs: exits 0" [ $? = 0 ]
item2() { grep -F "\"id\":\"$1\"," "$T/board2.html" | grep -qF -- "$2"; } # <id> <text>
check "board: a lesson that holds" item2 L-1 '"kind":"L","id":"L-1","state":"lesson",'
check "board: a dropped lesson, with the date it was dropped" item2 L-2 '"closed":"2026-02-03"'
check "board: the live handoff, with the one it continues" \
  item2 H-2 '"kind":"H","id":"H-2","state":"handoff","cross":0,"section":"","title":"2026-02-03 18:00 CET · claude@s1","fields":"continues: H-1"'
check "board: a replaced handoff, with the date it was replaced" item2 H-1 '"closed":"2026-03-04"'
check "board: a 1.x handoff, by its date, replaced when it was deleted" item2 'H~2026-01-02T10:00' '"closed":"2026-02-03"'
check "board, lessons and handoffs: no problem found" has "$T/board2.html" '"problems":[],'
if command -v node >/dev/null 2>&1; then
  node -e 'var h = require("fs").readFileSync(process.argv[1], "utf8");
    var d = JSON.parse(h.split("<script id=\"data\" type=\"application/json\">")[1].split("</script>")[0]);
    process.exit(d.items.length === 6 ? 0 : 1);' "$T/board2.html"
  check "board, lessons and handoffs: the data parses as JSON, every item in it" [ $? = 0 ]
fi
mkdir -p .claude && printf 'REPOS=("docs|.|origin||" "api|%s|origin||")\n' "$T/board2-api" >.claude/ground-truth.conf
PATH="$T/fakebin:$PATH" "$SH" "$BD" --no-open --out "$T/board3.html" "$T/board2" >"$T/board3.txt" 2>&1
check "board, commits and PRs: exits 0" [ $? = 0 ]
check "board: a commit's whole message" has "$T/board3.html" '"subject":"H-2 Handoff","body":"The second day."'
check "board: a commit of another repo, quoted by its hash" has "$T/board3.html" \
  "{\"sha\":\"$api_sha\",\"repo\":\"api\",\"date\":\"2026-02-02\",\"author\":\"test\",\"subject\":\"Round small quantities up to 1 g\","
check "board: a PR, with its repo, branch and state" has "$T/board3.html" \
  '{"repo":"api","gh":"demo/api","number":41,"title":"Round to 1 g","state":"MERGED","branch":"fix/B-1-rounding",'
check "board: a PR's description, its newlines kept" has "$T/board3.html" '"body":"Fixes B-1.\nA pinch of salt keeps 1 g."}'
check "board: PRs gh could not read are UNKNOWN, never none" has "$T/board3.html" \
  '{"repo":"docs","gh":"demo/docs","status":"UNKNOWN: gh pr list failed: HTTP 404: Not Found"}'
PATH="$T/fakebin:$PATH" "$SH" "$BD" --no-open --offline --out "$T/board4.html" "$T/board2" >/dev/null 2>&1
check "board --offline: asks GitHub nothing, and says so" has "$T/board4.html" '"gh":"demo/api","status":"not read: --offline"'
check "board --offline: no PR" has "$T/board4.html" '"prs":[],'
if command -v node >/dev/null 2>&1; then
  node -e 'var h = require("fs").readFileSync(process.argv[1], "utf8");
    var d = JSON.parse(h.split("<script id=\"data\" type=\"application/json\">")[1].split("</script>")[0]);
    process.exit(d.prs.length === 1 && d.prs[0].body === "Fixes B-1.\nA pinch of salt keeps 1 g." && d.commits.length >= 4 ? 0 : 1);' \
    "$T/board3.html"
  check "board, commits and PRs: the data parses as JSON, the text intact" [ $? = 0 ]
fi
PATH="$T/fakebin:$PATH" "$SH" "$BD" --no-open --offline --out "$T/board3.html" "$T/board2" >/dev/null 2>&1
check "board --offline: the PRs last read, from the same page's cache" has "$T/board3.html" '"number":41,"title":"Round to 1 g"'
check "board --offline: says when they were read" has "$T/board3.html" '"gh":"demo/api","status":"ok: as read 20'
check "board --offline: a repo never read is still not read" has "$T/board3.html" '"gh":"demo/docs","status":"not read: --offline"'

# Live: read as a script, the page sets its build's stamp and is a comment after that (the only "*/" is its last
# line), so an open page loads its own file to see whether it was rebuilt. The stamp ignores the build time.
stamp() { sed -n '2s/^window.boardStamp = "\([0-9]*\)"; \/\*$/\1/p' "$1"; } # <page>
check "board, live: the first lines set the stamp, the rest is a comment" \
  [ "$(sed -n 1p "$T/board.html" | cut -c1-4)" = "<!--" -a -n "$(stamp "$T/board.html")" -a "$(sed -n 3p "$T/board.html")" = "-->" ]
check "board, live: then the page, in standards mode" [ "$(sed -n 4p "$T/board.html")" = "<!doctype html>" ]
check "board, live: the comment ends on the last line, the only */ in the page" \
  [ "$(tail -n 1 "$T/board.html")" = "<!-- */ -->" -a "$(grep -c '\*/' "$T/board.html")" = 1 ]
check "board, live: a */ in an item is escaped" has "$T/board.html" '<\/script> and *\/ to the page.'
check "board, live: the page knows its own stamp" has "$T/board.html" "<html lang=\"en\" data-stamp=\"$(stamp "$T/board.html")\">"
if command -v node >/dev/null 2>&1; then
  node -e 'var c = { window: {} }; require("vm").runInNewContext(require("fs").readFileSync(process.argv[1], "utf8"), c);
    process.exit(c.window.boardStamp === process.argv[2] ? 0 : 1);' "$T/board.html" "$(stamp "$T/board.html")"
  check "board, live: as JavaScript, the page sets its stamp and nothing else" [ $? = 0 ]
fi
s1=$(stamp "$T/board.html")
sleep 1 # another minute in "built" would not change the stamp; this only spaces the builds
"$SH" "$BD" --no-open --out "$T/board.html" "$T/board" >/dev/null 2>&1
check "board, live: a rebuild with no change keeps the stamp" [ "$(stamp "$T/board.html")" = "$s1" ]
cp "$T/board/BACKLOG.md" "$T/backlog.bak"
printf '%s\n' '' '### 🔲 B-4 Fourth' 'Done when: done.' >>"$T/board/BACKLOG.md"
"$SH" "$BD" --no-open --out "$T/board.html" "$T/board" >/dev/null 2>&1
check "board, live: a change gives a new stamp" [ "$(stamp "$T/board.html")" != "$s1" ]
cp "$T/backlog.bak" "$T/board/BACKLOG.md"

# The text board, and where nothing opens: a cloud session or SSH prints it instead; a display opens the page.
"$SH" "$BD" --no-open --text --out "$T/board.html" "$T/board" >"$T/text.txt" 2>&1
check "board --text: exits 0" [ $? = 0 ]
check "board --text: the open items, by section" has "$T/text.txt" "BACKLOG: 2 open"
check "board --text: a waiting item, with its field" has "$T/text.txt" "    ⏸️ B-2  Second  (waits: the API)"
check "board --text: an open item" has "$T/text.txt" "    🔲 B-3  Third"
check "board --text: the open questions" has "$T/text.txt" "  💬 Q-1  Which one?"
check "board --text: a closed item is not there" lacks "$T/text.txt" "B-1 "
mkdir -p "$T/openers"
for o in xdg-open open start; do printf '#!/usr/bin/env bash\necho "$*" >"%s/opened"\n' "$T" >"$T/openers/$o"; done
chmod +x "$T/openers/"*
nobody() { env -u SSH_CONNECTION -u SSH_TTY -u CLAUDE_CODE_REMOTE -u CLAUDE_CODE_BRIDGE_SESSION_ID "$@"; }
rm -f "$T/opened"
nobody CLAUDE_CODE_REMOTE=true PATH="$T/openers:$PATH" "$SH" "$BD" --out "$T/board.html" "$T/board" >"$T/away.txt" 2>&1
check "board, in a cloud session: exits 0" [ $? = 0 ]
check "board, in a cloud session: the text board instead" has "$T/away.txt" "BACKLOG: 2 open"
check "board, in a cloud session: says why, and how to open the page" has "$T/away.txt" "cannot open in a cloud session"
nobody SSH_CONNECTION="1.2.3.4 5 6.7.8.9 22" PATH="$T/openers:$PATH" "$SH" "$BD" --out "$T/board.html" "$T/board" \
  >"$T/away.txt" 2>&1
check "board, over SSH: the text board instead" has "$T/away.txt" "cannot open in a session over SSH"
sleep 1
check "board, in a cloud session or over SSH: nothing opens" [ ! -e "$T/opened" ]
nobody DISPLAY=:99 PATH="$T/openers:$PATH" "$SH" "$BD" --out "$T/board.html" "$T/board" >"$T/here.txt" 2>&1
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -e "$T/opened" ] && break; sleep 0.2; done
check "board, with a display: the page opens" has "$T/opened" "$T/board.html"
check "board, with a display: no text board" lacks "$T/here.txt" "BACKLOG:"

# Before the setup fills the title in, the page is named after the folder, not after the FILL marker.
mkdir -p "$T/unfilled" "$T/tmpdir" && cp "$WF/template/BACKLOG.md" "$WF/template/questions.md" "$T/unfilled/"
TMPDIR="$T/tmpdir" "$SH" "$BD" --no-open --offline "$T/unfilled" >/dev/null 2>&1
check "board, before the setup: the page is named after the folder" [ -f "$T/tmpdir/unfilled-board.html" ]

# The hook (.claude/settings.json, PostToolUse): the tool call as JSON on stdin. It rebuilds when the call names a
# tracker or moves git, stays quiet and exits 0 whatever happens, and leaves no lock behind.
hook() { printf '%s' "$1" | "$SH" "$BD" --hook --out "$T/hook.html" "${2:-$T/board}" >"$T/hook.txt" 2>&1; } # <json>
rm -f "$T/hook.html"
hook '{"tool_name":"Edit","tool_input":{"file_path":"/p/README.md"}}'
check "hook: an edit of another file exits 0" [ $? = 0 ]
check "hook: an edit of another file builds nothing" [ ! -e "$T/hook.html" ]
hook '{"tool_name":"Edit","tool_input":{"file_path":"/p/BACKLOG.md"}}'
check "hook: an edit of BACKLOG.md exits 0, silently" [ $? = 0 -a ! -s "$T/hook.txt" ]
check "hook: an edit of BACKLOG.md builds the page" has "$T/hook.html" '"id":"B-3",'
printf '%s\n' '' '### 🔲 B-4 Fourth' 'Done when: done.' >>"$T/board/BACKLOG.md"
hook '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
check "hook: a command that touches neither builds nothing" lacks "$T/hook.html" '"id":"B-4",'
hook '{"tool_name":"Bash","tool_input":{"command":"git add BACKLOG.md && git commit -q -m \"B-4 added\""}}'
check "hook: a git commit rebuilds the page" has "$T/hook.html" '"id":"B-4",'
printf '%s\n' '' '### 🔲 B-5 Fifth' 'Done when: done.' >>"$T/board/BACKLOG.md"
hook '{"tool_name":"Bash","tool_input":{"command":"bash .claude/skills/session-start/claim.sh B-5 feat/five"}}'
check "hook: a claim rebuilds the page" has "$T/hook.html" '"id":"B-5",'
for _ in 1 2 3 4; do hook '{"tool_name":"Write","tool_input":{"file_path":"/p/notes/lessons.md"}}' & done
wait
check "hook: calls at once leave no lock and no mark" [ ! -e "$T/hook.lock" -a ! -e "$T/hook.dirty" ]
cp "$T/backlog.bak" "$T/board/BACKLOG.md"
mkdir -p "$T/empty"
hook '{"tool_name":"Edit","tool_input":{"file_path":"/p/BACKLOG.md"}}' "$T/empty"
check "hook: a folder with no tracker still exits 0, silently" [ $? = 0 -a ! -s "$T/hook.txt" ]
check "adopt.sh installs the hook" has "$T/ws/.claude/settings.json" '/.claude/skills/session-start/board.sh\" --hook'
check "adopt.sh installs /board" [ -f "$T/ws/.claude/skills/board/SKILL.md" ]
if command -v node >/dev/null 2>&1; then
  node -e 'var h = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).hooks.PostToolUse[0];
    process.exit(/Edit/.test(h.matcher) && /Write/.test(h.matcher) && /Bash/.test(h.matcher) && h.hooks[0].async ? 0 : 1);' \
    "$T/ws/.claude/settings.json"
  check "the hook: valid JSON, after Edit, Write and Bash, in the background" [ $? = 0 ]
fi

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

# items.sh show, and what git cannot vouch for: B-2 is closed (H-1 names it), B-3 is closed then given again to
# another item; the ruling Q-1 is archived, the question Q-2 closed; a shallow clone holds only the last commit.
mkdir -p "$T/show/notes/handoff" "$T/show/.claude/skills/session-start" && cd "$T/show" || exit 1
cp "$ITS" .claude/skills/session-start/
git_q init && git symbolic-ref HEAD refs/heads/main
show_backlog() { printf '%s\n' '# Demo — Backlog' '' 'next id: B-4 (last given to claude@s1)' '' '## api' '' "$@"; }
show_handoff() { # <id> <the item it names> <continues line or "">
  printf '%s\n' "# $1 2026-01-02 10:00 CET · claude@s1" ${3:+"$3"} '' '## Next' "1. $2: go on." '' \
    '## Waiting for the user' 'None.' '' '## Running' 'None.' '' '## Unfinished' 'None.' '' '## Done' 'None.' '' \
    '## Learned' 'None.'
}
show_backlog '### 🔲 B-1 First' 'Done when: done.' '' '### 🔲 B-2 Second' 'The second one.' 'Done when: done.' '' \
  '### 🔲 B-3 Third' 'Done when: done.' >BACKLOG.md
show_questions() { printf '%s\n' '# Demo — questions' '' 'next id: Q-3 (last given to claude@s1)' '' "$@"; }
show_questions '### 💬 Q-2 Which one?' 'The question.' '' '### 🟢 Q-1 Never X' 'ruled: 2026-01-02' 'Owner: "no X".' \
  >questions.md
printf '%s\n' '# Handoffs' '' 'next id: H-2 (last given to claude@s1)' >notes/handoff/README.md
show_handoff H-1 "B-2 Second" >notes/handoff/s1.md
git add BACKLOG.md questions.md notes && GIT_COMMITTER_DATE=2026-01-02T10:00:00 git_q commit -m "three items"
show_backlog '### 🔲 B-1 First' 'Done when: done.' >BACKLOG.md
printf '%s\n' '# Handoffs' '' 'next id: H-3 (last given to claude@s1)' >notes/handoff/README.md
show_handoff H-2 "B-1 First" "continues: H-1" >notes/handoff/s1.md
show_questions >questions.md
GIT_COMMITTER_DATE=2026-02-03T10:00:00 git_q commit -am "B-2 done, B-3 dropped, Q-1 archived, Q-2 answered"
show_backlog '### 🔲 B-1 First' 'Done when: done.' '' '### 🔲 B-3 Not the third' 'Done when: done.' >BACKLOG.md
GIT_COMMITTER_DATE=2026-03-04T10:00:00 git_q commit -am "B-3 added again"
"$SH" "$IT" show B-2 >"$T/show-b2.txt" 2>&1
rc=$?
sed 's/^/      | /' "$T/show-b2.txt"
check "items.sh show: a closed item exits 0" [ "$rc" = 0 ]
check "items.sh show: when it was closed, and by which commit" has "$T/show-b2.txt" "  closed on 2026-02-03 by "
check "items.sh show: its last version, as written" \
  eval 'has "$T/show-b2.txt" "### 🔲 B-2 Second" && has "$T/show-b2.txt" "The second one."'
check "items.sh show: its history" has "$T/show-b2.txt" "  2026-01-02  "
check "items.sh show: the handoffs that name it, replaced or live" \
  has "$T/show-b2.txt" "  H-1 2026-01-02 10:00 CET · claude@s1 (replaced)"
"$SH" "$IT" show B-3 >"$T/show-b3.txt" 2>&1
check "items.sh show: an id given twice in git is flagged" has "$T/show-b3.txt" \
  "⚠ B-3 is given twice in git: closed as \"Third\", given again in "
"$SH" "$IT" show H-1 >"$T/show-h1.txt" 2>&1
check "items.sh show: a replaced handoff, in full" \
  eval 'has "$T/show-h1.txt" "  replaced on 2026-02-03 by " && has "$T/show-h1.txt" "1. B-2 Second: go on."'
"$SH" "$IT" show Q-1 >"$T/show-q1.txt" 2>&1
check "items.sh show: a deleted ruling is archived" has "$T/show-q1.txt" "  archived on 2026-02-03 by "
"$SH" "$IT" show Q-2 >"$T/show-q2.txt" 2>&1
check "items.sh show: a deleted question is closed" has "$T/show-q2.txt" "  closed on 2026-02-03 by "
"$SH" "$IT" show B-9 >"$T/show-none.txt" 2>&1
check "items.sh show: an id nobody gave exits 1" [ $? = 1 ]
"$SH" "$BD" --no-open --offline --out "$T/show.html" "$T/show" >/dev/null 2>&1
check "board: an id given twice in git is a problem" has "$T/show.html" \
  '"text":"B-3 is given twice in git: closed as \"Third\", given again in '
check "board: and on the item, added when the id was given again" \
  eval 'grep -F "\"id\":\"B-3\"," "$T/show.html" | grep -F "\"added\":\"2026-03-04\"," | grep -qF "\"twice\":\"closed as"'
check "board: a deleted ruling, as a ruling, with the date it went" \
  eval 'grep -F "\"id\":\"Q-1\"," "$T/show.html" | grep -F "\"state\":\"ruling\"," | grep -qF "\"closed\":\"2026-02-03\""'
check "board: a deleted ruling shows as archived, a deleted question as closed" eval \
  'has "$T/show.html" "[\"archived\", \"🗄️\", \"archived\"]" && has "$T/show.html" "it.kind === \"Q\" && it.state === \"ruling\" ? \"archived\" : \"closed\""'
git_q clone --depth 1 "file://$T/show" "$T/shallow"
mkdir -p "$T/shallow/.claude/skills/session-start" && cp "$ITS" "$T/shallow/.claude/skills/session-start/"
(cd "$T/shallow" && "$SH" "$IT" show B-2) >"$T/show-shallow.txt" 2>&1
check "items.sh show, shallow clone: an item it cannot see is UNKNOWN (exit 2)" [ $? = 2 ]
check "items.sh show, shallow clone: says why" has "$T/show-shallow.txt" \
  "UNKNOWN: B-2 is in no file here, and this shallow clone holds the history since 2026-03-04 only"
(cd "$T/shallow" && "$SH" "$IT" show B-1) >"$T/show-shallow1.txt" 2>&1
check "items.sh show, shallow clone: an item it sees, its history UNKNOWN (exit 2)" \
  eval '[ $? = 2 ] && has "$T/show-shallow1.txt" "UNKNOWN before 2026-03-04: a shallow clone"'
"$SH" "$BD" --no-open --offline --out "$T/shallow.html" "$T/shallow" >/dev/null 2>&1
check "board, shallow clone: says so, with the date" has "$T/shallow.html" '"shallow":"2026-03-04",'
check "board, shallow clone: no false date added" \
  eval 'grep -F "\"id\":\"B-1\"," "$T/shallow.html" | grep -qF "\"added\":\"\","'

# Claims (notes/item-format.md, Claims): two clones claim the same item; the one that pushes second is refused, even
# when the other's push lands between its fetch and its push (a pre-push hook makes that happen).
mkdir "$T/claims" && cd "$T/claims" || exit 1
CL=.claude/skills/session-start/claim.sh
git_q init --bare remote.git && git -C remote.git symbolic-ref HEAD refs/heads/main
git_q clone remote.git a
git -C a symbolic-ref HEAD refs/heads/main
mkdir -p a/.claude/skills/session-start && cp "$ITS" "$WF/template/dot-claude/skills/session-start/claim.sh" a/.claude/skills/session-start/
printf '%s\n' '# Backlog' '' 'next id: B-4 (last given to claude@a)' '' '## api' '' '### 🔲 B-1 First' 'Done when: done.' '' \
  '### 🔲 B-2 Second' 'Done when: done.' '' '### ⏸️ B-3 Later' 'waits: the API' 'Done when: done.' >a/BACKLOG.md
git -C a add -A && git_q -C a commit -m start && git_q -C a push origin main
git_q clone remote.git b
(cd a && "$SH" "$CL" B-1 feat/one) >"$T/claim-a.txt" 2>&1
check "claim: exits 0" [ $? = 0 ]
check "claim: says it is claimed" has "$T/claim-a.txt" "CLAIMED: B-1 First, by claude@a on feat/one (origin/main, "
check "claim: the line is on the remote, under the heading" \
  [ "$(git -C remote.git show main:BACKLOG.md | sed -n '7,8p' | tr -d '\r')" = "### 🔲 B-1 First"$'\n'"claimed: claude@a on feat/one" ]
check "claim: one commit, BACKLOG.md alone" \
  [ "$(git -C remote.git show --format=%s --name-only main | tr '\n' ' ')" = "claim B-1  BACKLOG.md " ]
check "claim: the default branch here shows it" \
  eval 'has a/BACKLOG.md "claimed: claude@a on feat/one" && [ -z "$(git -C a status --porcelain)" ]'
"$SH" "$ITS" check a/BACKLOG.md >/dev/null 2>&1
check "claim: the result passes the format check" [ $? = 0 ]
(cd b && "$SH" "$CL" B-1 feat/mine claude@b) >"$T/claim-b.txt" 2>&1
check "claim: an item claimed by another session is refused (exit 1)" [ $? = 1 ]
check "claim: the refusal names who has it" has "$T/claim-b.txt" "REFUSED: B-1 First is claimed by claude@a on feat/one"
check "claim: after a refusal, the default branch here shows the claim" has b/BACKLOG.md "claimed: claude@a on feat/one"
(cd a && "$SH" "$CL" B-1 feat/one) >"$T/claim-again.txt" 2>&1
check "claim: claiming one's own item again is fine" eval '[ $? = 0 ] && has "$T/claim-again.txt" "already claimed"'
# The next session (a new name) goes on with B-1: it takes the claim over, only from the session that holds it.
(cd a && "$SH" "$CL" B-1 feat/one claude@a-2 --from claude@other) >"$T/claim-over-no.txt" 2>&1
check "claim --from: refused when another session holds the claim" \
  eval '[ $? = 1 ] && has "$T/claim-over-no.txt" "is claimed by claude@a on feat/one (origin/main), not by claude@other"'
(cd a && "$SH" "$CL" B-1 feat/one-more claude@a-2 --from claude@a) >"$T/claim-over.txt" 2>&1
check "claim --from: takes the claim over" \
  eval '[ $? = 0 ] && has "$T/claim-over.txt" "CLAIMED: B-1 First, by claude@a-2 on feat/one-more, taken over from claude@a"'
check "claim --from: the line is replaced, not added" \
  [ "$(git -C remote.git show main:BACKLOG.md | sed -n '7,9p' | tr -d '\r')" = "### 🔲 B-1 First"$'\n'"claimed: claude@a-2 on feat/one-more"$'\n'"Done when: done." ]
check "claim --from: its commit says so" [ "$(git -C remote.git log -1 --format=%s main)" = "claim B-1, taken over from claude@a" ]
(cd a && "$SH" "$CL" B-3 feat/three) >"$T/claim-waits.txt" 2>&1
check "claim: an item waiting for its trigger is refused" eval '[ $? = 1 ] && has "$T/claim-waits.txt" "waits for its trigger"'
cp a/BACKLOG.md "$T/claims-backlog.bak"
printf '%s\n' '' '### 🔲 B-4 Only here' 'Done when: done.' >>a/BACKLOG.md
(cd a && "$SH" "$CL" B-4 feat/four) >"$T/claim-new.txt" 2>&1
check "claim: an item not pushed yet is refused, and says to push it" \
  eval '[ $? = 1 ] && has "$T/claim-new.txt" "it is only here; push it first"'
cp "$T/claims-backlog.bak" a/BACKLOG.md
# The race: b reads B-2 unclaimed, then a claims it and pushes before b does.
printf '#!/bin/sh\nrm -f "$0"\ncd "%s" && "%s" "%s" B-2 feat/two-a >"%s" 2>&1\nexit 0\n' \
  "$T/claims/a" "$SH" "$CL" "$T/claim-race-a.txt" >b/.git/hooks/pre-push
chmod +x b/.git/hooks/pre-push
(cd b && "$SH" "$CL" B-2 feat/two-b claude@b) >"$T/claim-race.txt" 2>&1
check "claim, a race: the second push is refused (exit 1)" [ $? = 1 ]
check "claim, a race: the first one won" has "$T/claim-race-a.txt" "CLAIMED: B-2 Second, by claude@a on feat/two-a"
check "claim, a race: the refusal names the winner" has "$T/claim-race.txt" \
  "REFUSED: B-2 Second is claimed by claude@a on feat/two-a"
check "claim, a race: one claim per item on the remote" \
  [ "$(git -C remote.git show main:BACKLOG.md | grep -c '^claimed: ')" = 2 ]
(cd b && "$SH" "$CL" B-1 'two words') >"$T/claim-usage.txt" 2>&1
check "claim: a usage error exits 2" [ $? = 2 ]
check "adopt.sh installs claim.sh, executable" [ -x "$T/ws/$CL" ]

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) FAILED"
  exit 1
fi
echo "all checks passed"
