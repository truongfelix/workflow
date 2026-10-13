#!/usr/bin/env bash
#
# run.sh — test bin/adopt.sh and the scripts of the skills (ground-truth.sh, items.sh, claim.sh, gate.sh, board.sh,
# autonomy.sh) on throwaway repos and workspaces. CI runs it on Linux, macOS (/bin/bash 3.2) and Windows (Git Bash,
# CRLF checkout).
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
  template/dot-claude/skills/session-start/claim.sh template/dot-claude/skills/session-start/gate.sh \
  template/dot-claude/skills/session-start/lib.sh template/dot-claude/skills/session-start/attach.sh \
  template/dot-claude/skills/autonomy/autonomy.sh \
  template/dot-claude/ground-truth.conf; do
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
for r in "Start the day's task after the brief" "Commit the docs" "Push the docs" "Add an item to the backlog" \
  "Claim an item" "Commit code" "Push a work branch" "Stop a background job this session started"; do
  check "the row \"$r\", named by a skill, is in the table" \
    eval 'steps "$CT" | grep -q "^$r" && cat "${SKILLS[@]}" | grep -qF "\"$r\""'
done

# /autonomy (template/dot-claude/skills/autonomy): autonomy.sh reads and sets the table's rows, by a preset or step by
# step, and deletes the setup's FILL comment once the owner has chosen. Its presets are the template's last bullet.
AU="$WF/template/dot-claude/skills/autonomy/autonomy.sh"
norm() { sed '/<!-- FILL: ask the owner for a preset/,/-->/d; s/| ask first |$/| ? |/; s/| do, then tell |$/| ? |/' "$1" | cat -s; }
cp "$CT" "$T/au.md"
"$SH" "$AU" show -f "$T/au.md" >"$T/au-show.txt" 2>&1
check "autonomy show: the template's table is Careful, each step with its answer" \
  eval '[ $? = 0 ] && has "$T/au-show.txt" "preset: Careful" &&
    [ "$(grep -c "ask first$" "$T/au-show.txt")" = "$(rows "$CT" | wc -l | tr -d " ")" ]'
"$SH" "$AU" preset balanced -f "$T/au.md" >"$T/au-bal.txt" 2>&1
check "autonomy preset balanced: asks first to start the day's task, open or merge a PR, release, message" \
  [ "$(rows "$T/au.md" | grep '| ask first |$' | sed 's/ | ask first |$//; s/^| //' | tr '\n' ';')" = \
    "Start the day's task after the brief;Open a pull request;Merge a pull request, or push code to a default branch;Release: tag, publish;Comment, or message anyone;" ]
check "autonomy preset balanced: does the rest, then tells" [ "$(rows "$T/au.md" | grep -c '| do, then tell |$')" = 8 ]
check "autonomy preset: says the preset the rows make" has "$T/au-bal.txt" "preset: Balanced"
check "autonomy preset: the setup's FILL comment is gone" lacks "$T/au.md" "FILL: ask the owner for a preset"
check "autonomy: nothing but the rows and the FILL comment changes" [ "$(norm "$CT")" = "$(norm "$T/au.md")" ]
"$SH" "$AU" ask "Commit code" -f "$T/au.md" >"$T/au-ask.txt" 2>&1
check "autonomy ask: a step by its text, then the closest preset and what differs" \
  eval '[ $? = 0 ] && has "$T/au.md" "| Commit code | ask first |" &&
    has "$T/au-ask.txt" "preset: none, closest Balanced, 1 step(s) switched: Commit code"'
"$SH" "$AU" tell 6 "claim an item" -f "$T/au.md" >/dev/null 2>&1
check "autonomy tell: a step by its number, or the start of its text in any case" \
  eval '[ $? = 0 ] && has "$T/au.md" "| Commit code | do, then tell |" &&
    has "$T/au.md" "| Claim an item (commit and push its claim line) | do, then tell |"'
cp "$T/au.md" "$T/au.bak"
"$SH" "$AU" tell Push -f "$T/au.md" >/dev/null 2>&1
check "autonomy: a step that is not one row exits 1 and changes nothing" eval '[ $? = 1 ] && cmp -s "$T/au.md" "$T/au.bak"'
"$SH" "$AU" preset hands-off -f "$T/au.md" >/dev/null 2>&1
check "autonomy preset hands-off: asks first only to release, and to comment or message" \
  [ "$(rows "$T/au.md" | grep -c '| ask first |$')" = 2 ]
"$SH" "$AU" preset Careful -f "$T/au.md" >/dev/null 2>&1
check "autonomy preset careful: the template's rows again" [ "$(rows "$T/au.md")" = "$(rows "$CT")" ]
"$SH" "$AU" show -f "$CE" >"$T/au-ex.txt" 2>&1
check "autonomy show: the example is Careful but for the docs" \
  has "$T/au-ex.txt" "preset: none, closest Careful, 2 step(s) switched: Commit the docs; Push the docs"
printf '%s\n' '## What Claude does alone' '' '| Step | Here |' '|---|---|' '| Commit code | ask first |' \
  '| Deploy to production | ask first |' '' '## Rules' >"$T/au2.md"
"$SH" "$AU" preset balanced -f "$T/au2.md" >"$T/au2.txt" 2>&1
check "autonomy: a preset never makes a row of the project's own a step done alone" \
  eval 'has "$T/au2.md" "| Deploy to production | ask first |" && has "$T/au2.md" "| Commit code | do, then tell |" &&
    has "$T/au2.txt" "own rows (no preset names them): Deploy to production"'
printf '%s\n' '## What Claude does alone' '' '| Step | Here |' '|---|---|' '| Commit code | maybe |' >"$T/au3.md"
cp "$T/au3.md" "$T/au3.bak"
"$SH" "$AU" preset balanced -f "$T/au3.md" >"$T/au3.txt" 2>&1
check "autonomy: a row answered neither way is UNKNOWN (exit 2), nothing written" \
  eval '[ $? = 2 ] && has "$T/au3.txt" "UNKNOWN: the row \"Commit code\" answers \"maybe\"" && cmp -s "$T/au3.md" "$T/au3.bak"'
"$SH" "$AU" show -f "$T/nowhere.md" >/dev/null 2>&1
check "autonomy: no CLAUDE.md is UNKNOWN (exit 2)" [ $? = 2 ]
while IFS= read -r l; do printf '%s\r\n' "$l"; done < <(tr -d '\r' <"$CT") >"$T/au4.md" # not awk: see autonomy.sh
"$SH" "$AU" preset balanced -f "$T/au4.md" >/dev/null 2>&1
crlf() { [ "$(tr -cd '\r' <"$1" | wc -c | tr -d ' ')" = "$(wc -l <"$1" | tr -d ' ')" ]; } # <file>: a CR on each line
check "autonomy: a CRLF file keeps CRLF" crlf "$T/au4.md"
crlf "$T/au4.md" || od -c "$T/au4.md" | sed -n '1,6p' | sed 's/^/      | /'
{ printf '%s\n' '## What Claude does alone' '' '| Step | Here |' '|---|---|'; printf '%s' '| Commit code | ask first |'; } >"$T/au5.md"
"$SH" "$AU" preset balanced -f "$T/au5.md" >/dev/null 2>&1
check "autonomy: a last row with no newline is set, and keeps none" \
  eval '[ $? = 0 ] && [ "$(tail -c 31 "$T/au5.md")" = "| Commit code | do, then tell |" ] && [ "$(tail -c 1 "$T/au5.md")" = "|" ]'

# The workspace: ws/ is the docs repo, ws/api a code repo, ws/api-feat its worktree.
cd "$T" || exit 1
git_q init --bare remote-api.git && git_q init --bare remote-docs.git && git_q init --bare remote-dev.git
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
# A second remote, as a private one beside a public origin: v2 (a worktree) and priv (none) track branches there;
# another clone pushes to dev/v2, which only a fetch of dev shows.
git remote add dev "$T/remote-dev.git"
git_q worktree add ../api-v2 -b v2
(cd ../api-v2 && git_q commit --allow-empty -m v2 && git_q push -u dev v2 && git_q commit --allow-empty -m "v2, not pushed")
git_q branch priv && git_q push -u dev priv
git update-ref refs/heads/priv "$(git commit-tree 'priv^{tree}' -p priv -m "priv, not pushed")"
git_q branch pushed-to-dev && git_q push -u dev pushed-to-dev
git_q clone --branch v2 "$T/remote-dev.git" "$T/dev-other" &&
  (cd "$T/dev-other" && git_q commit --allow-empty -m "v2, from another machine" && git_q push origin v2)
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
check "adopt.sh lists no FILL marker of a script (B-52)" lacks "$T/adopt.txt" ".sh:"
# B-53: nothing in a new project describes the workflow's own repo or a sample of another project.
check "adopt.sh: the lessons hold no sample lesson" lacks notes/lessons.md "Stacked PRs"
check "adopt.sh: CLAUDE.md does not send improvements back to the workflow repo" lacks CLAUDE.md "port that part back"
check "adopt.sh: BACKLOG.md has no placeholder for a second repo" lacks BACKLOG.md "second repo"
# B-55: the trackers' rules are in the item format, not in the files every session reads.
check "adopt.sh: BACKLOG.md does not carry the rules, the item format does" \
  eval 'lacks BACKLOG.md "Only approved items are built" && has notes/item-format.md "Only approved items are built"'
check "adopt.sh: questions.md does not carry the rules, and points to the item format" \
  eval 'lacks questions.md "moves to §2 as" && has questions.md "The rules of the two trackers"'
# B-54: a config still holding its FILL lines is a finding in the ground truth, until the lines are gone.
mkdir "$T/fresh" && (cd "$T/fresh" && git_q init -b main && "$SH" "$WF/bin/adopt.sh" . >/dev/null 2>&1)
(cd "$T/fresh" && "$SH" .claude/skills/session-start/ground-truth.sh --no-fetch >"$T/fresh-gt.txt" 2>&1)
check "ground truth: an unfilled config exits 0 and says so in a section" \
  eval 'has "$T/fresh-gt.txt" "== setup" && has "$T/fresh-gt.txt" "still has its FILL lines"'
check "ground truth: an unfilled config does not end with a plain complete" \
  eval 'tail -n 1 "$T/fresh-gt.txt" | grep -q "^GROUND TRUTH: complete, but the setup is not"'
grep -v '^# FILL\|^# "Adopt in a new project", step 4' "$T/fresh/.claude/ground-truth.conf" >"$T/fresh-conf" &&
  cp "$T/fresh-conf" "$T/fresh/.claude/ground-truth.conf"
(cd "$T/fresh" && "$SH" .claude/skills/session-start/ground-truth.sh --no-fetch >"$T/fresh-gt.txt" 2>&1)
check "ground truth: a filled config ends with a plain complete, no setup section" \
  eval 'tail -n 1 "$T/fresh-gt.txt" | grep -qx "GROUND TRUTH: complete" && lacks "$T/fresh-gt.txt" "== setup"'
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
check "ground truth: a worktree whose branch tracks another remote, against that branch, fetched" \
  has "$T/gt.txt" "    api-v2 [v2]: ahead 1 / behind 1 of dev/v2"
check "ground truth: a branch that tracks another remote, its commits not pushed there" \
  has "$T/gt.txt" "    priv: 1 commit(s) not pushed to dev/priv"
check "ground truth: a branch pushed to the remote it tracks is not listed" lacks "$T/gt.txt" "pushed-to-dev"
check "ground truth: the docs repo, in sync" has "$T/gt.txt" "ahead 0 / behind 0 of origin/main, 0 uncommitted"
check "ground truth: complete" has "$T/gt.txt" "GROUND TRUTH: complete"
check "ground truth: no claim" eval 'grep -A1 "^== claims (BACKLOG.md, shared on origin/main)$" "$T/gt.txt" | grep -qx "  none"'

# Claims: B-11 on a live branch, B-12 on a branch that is gone (claimed on this machine), B-13 on a branch with no
# commit since January (claimed then too), B-15 on a branch claimed on another machine and not here, B-14 claimed here
# and not pushed.
old=$(GIT_COMMITTER_DATE=2026-01-02T10:00:00 git -C api commit-tree 'HEAD^{tree}' -p HEAD -m old)
git -C api branch old "$old"
cp BACKLOG.md "$T/ws-backlog.bak"
claims_backlog() { # [<B-14's claim>]
  printf '%s\n' '# Demo — Backlog' '' 'next id: B-16 (last given to claude@ws)' '' '## api' '' '### 🔲 B-11 Live' \
    'claimed: claude@ws on feat' 'Done when: done.' '' '### 🔲 B-12 Gone' 'claimed: claude@other on feat/gone at laptop' \
    'Done when: done.' '' '### 🔲 B-13 Old' 'claimed: claude@other on old' 'Done when: done.' '' '### 🔲 B-15 Away' \
    'claimed: claude@far on feat/away at desktop-2' 'Done when: done.' '' '### 🔲 B-14 Mine' ${1:+"$1"} 'Done when: done.'
}
claims_backlog >BACKLOG.md
git add BACKLOG.md && GIT_COMMITTER_DATE=2026-01-02T10:00:00 git_q commit -m claims && git_q push origin main
claims_backlog 'claimed: claude@ws on spike' >BACKLOG.md
CLAIM_MACHINE=laptop "$SH" "$GT" >"$T/gt-claims.txt" 2>&1
rc=$?
sed 's/^/      | /' "$T/gt-claims.txt"
check "ground truth, claims: exits 0, a stale claim is a finding" [ "$rc" = 0 ]
check "ground truth, claims: a claim, its branch, its repo, pushed or not" \
  eval 'has "$T/gt-claims.txt" "  B-11 Live: claude@ws on feat" && has "$T/gt-claims.txt" ", ahead 1 / behind 0 of origin/feat"'
check "ground truth, claims: a branch that is gone" has "$T/gt-claims.txt" "      ⚠ GONE: no branch feat/gone in api"
check "ground truth, claims: a branch claimed on another machine is not gone, it may be there alone" \
  has "$T/gt-claims.txt" "      ⚠ NOT HERE: no branch feat/away in api, here or on a remote: its commits are on desktop-2 alone"
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
eval "$(sed -n '/^with_timeout()/,/^}/p' "$(dirname "$GT")/lib.sh")"
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
  'BACKLOG.md:36: B-7: `claimed:` is not `<agent>@<session> on <branch> at <machine>`: claude@web' \
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
  eval 'has "$T/board.html" "(S.tab === \"B\" ? \"<th>Claimed</th><th>Where</th>\" + (D.gated ? \"<th title=" &&
    lacks "$T/board.html" "[\"claimed\", \"🔲\", \"claimed\"]"'
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
# With no --out, the page goes to the temp folder, or to the default browser's own folder when it is a snap: a snap
# browser reads neither /tmp nor the hidden folders of the home, so the page would not open, nor a link to it.
mkdir -p "$T/fakebin4" "$T/home/snap/firefox/common" "$T/tmp4"
printf '%s\n' '#!/bin/sh' 'echo "$BROWSER_DESKTOP"' >"$T/fakebin4/xdg-mime" && chmod +x "$T/fakebin4/xdg-mime"
BROWSER_DESKTOP=firefox_firefox.desktop HOME="$T/home" TMPDIR="$T/tmp4" PATH="$T/fakebin4:$PATH" \
  "$SH" "$BD" --no-open --offline "$T/board2" >"$T/board-snap.txt" 2>&1
check "board, a snap browser: the page in its own folder, which it can read" \
  eval 'has "$T/board-snap.txt" "Board: $T/home/snap/firefox/common/" && [ -n "$(ls "$T/home/snap/firefox/common/")" ]'
BROWSER_DESKTOP=firefox.desktop HOME="$T/home" TMPDIR="$T/tmp4" PATH="$T/fakebin4:$PATH" \
  "$SH" "$BD" --no-open --offline "$T/board2" >"$T/board-tmp.txt" 2>&1
check "board, any other browser: the page in the temp folder" has "$T/board-tmp.txt" "Board: $T/tmp4/"
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

# Where the work of each claimed item is (notes/item-format.md, Claims): computed from git and the PRs, never written
# in the item. In the api repo: B-1's branch is gone and its PR merged; B-2's is pushed, a commit ahead, in an open PR
# with green CI; B-3's is only here; B-4's was claimed on another machine and is nowhere here; B-5's is pushed, no PR.
cp -R "$T/board2" "$T/board5" && cd "$T/board2-api" || exit 1
git update-ref refs/remotes/origin/main main
git_q checkout -b feat/two && git_q commit --allow-empty -m two && git update-ref refs/remotes/origin/feat/two HEAD
git_q commit --allow-empty -m "two, not pushed"
git_q checkout -b spike main && git_q commit --allow-empty -m spike
git_q checkout -b feat/pushed main && git_q commit --allow-empty -m pushed
git update-ref refs/remotes/origin/feat/pushed HEAD && git_q checkout main && git_q branch -D feat/pushed
# The gate (gate.sh's records in the clone's git directory): B-2's last commit passed after an older failure, B-3's
# failed, B-5's was not run, but the commit before it passed.
mkdir -p .git/gate-receipts .git/gate-failures
echo "failed: before" >".git/gate-failures/$(git rev-parse feat/two)" && touch -t 202601010000 ".git/gate-failures/$(git rev-parse feat/two)"
echo "passed: now" >".git/gate-receipts/$(git rev-parse feat/two)"
echo "failed: now" >".git/gate-failures/$(git rev-parse spike)"
echo "passed: then" >".git/gate-receipts/$(git rev-parse main)"
cd "$T/board5" || exit 1
printf '%s\n' 'GATES=("api|true")' 'GITHUB_CI=("api")' >>.claude/ground-truth.conf
printf '%s\n' '# Demo — Backlog' '' 'next id: B-6 (last given to claude@s1)' '' '## api' '' '### 🔲 B-1 First' \
  'claimed: claude@s1 on fix/B-1-rounding at laptop' 'Done when: done.' '' '### 🔲 B-2 Second' \
  'claimed: claude@s1 on feat/two at laptop' 'Done when: done.' '' '### 🔲 B-3 Third' \
  'claimed: claude@s1 on spike at laptop' 'Done when: done.' '' '### 🔲 B-4 Fourth' \
  'claimed: claude@s2 on feat/away at desktop-2' 'Done when: done.' '' '### 🔲 B-5 Fifth' \
  'claimed: claude@s1 on feat/pushed at laptop' 'Done when: done.' >BACKLOG.md
mkdir "$T/fakebin2"
cat >"$T/fakebin2/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"-R demo/api "*statusCheckRollup*) printf '42\tCI green\n' ;;
  *"-R demo/api "*)
    printf '41\tRound to 1 g\tMERGED\tfix/B-1-rounding\tmain\t2026-02-01T09:00:00Z\t2026-02-02T10:00:00Z\t2026-02-02T10:00:00Z\thttps://github.com/demo/api/pull/41\tdev\t\tFixes B-1.\n'
    printf '42\tTwo\tOPEN\tfeat/two\tmain\t2026-02-03T09:00:00Z\t\t\thttps://github.com/demo/api/pull/42\tdev\t\tB-2.\n' ;;
  *) echo "HTTP 404: Not Found" >&2; exit 1 ;;
esac
EOF
chmod +x "$T/fakebin2/gh"
CLAIM_MACHINE=laptop PATH="$T/fakebin2:$PATH" "$SH" "$BD" --no-open --text --out "$T/board5.html" "$T/board5" \
  >"$T/board5.txt" 2>&1
check "board, where: exits 0" [ $? = 0 ]
for w in '"B-1":"fix/B-1-rounding: merged (PR #41): the item can be deleted"' \
  '"B-2":"feat/two: PR #42 open, CI green, 1 commit not pushed"' '"B-3":"spike: only on laptop, not pushed"' \
  '"B-4":"feat/away: not here: on desktop-2 alone (not pushed), or gone"' '"B-5":"feat/pushed: pushed, no PR yet"'; do
  check "board, where: $w" has "$T/board5.html" "$w"
done
check "board, where: the CI of an open PR" has "$T/board5.html" '"number":42,"title":"Two","state":"OPEN"'
check "board, gate: the column shows, the project has a gate" has "$T/board5.html" '"gated":true,'
check "board, where: this machine, as claims name it" has "$T/board5.html" '"machine":"laptop"}'
check "board --text, where: under the item" has "$T/board5.txt" "        where: spike: only on laptop, not pushed"
gate_of() { grep -qF "\"$1\":\"$2\"" "$T/board5.html"; } # <id> <text>: in the data's gate map
check "board, gate: passed on the last commit, after an older failure" gate_of B-2 "passed ($(git -C "$T/board2-api" rev-parse --short=7 feat/two))"
check "board, gate: failed on the last commit" gate_of B-3 "failed ($(git -C "$T/board2-api" rev-parse --short=7 spike))"
check "board, gate: not run on the last commit, and the result before it" \
  gate_of B-5 "not run on the last commit; passed at $(git -C "$T/board2-api" rev-parse --short=7 main)"
check "board, gate: nothing for a branch that is not here" \
  eval 'grep -q "^\"gate\":{" "$T/board5.html" && [ -z "$(grep "^\"gate\":{" "$T/board5.html" | grep -F "\"B-4\"")" ]'
check "board --text, gate: under the item, on this machine" has "$T/board5.txt" "        gate: failed ($(git -C "$T/board2-api" rev-parse --short=7 spike)) (on this machine)"
# Offline (the hook's builds), the PRs are those last read: a PR opened or merged since is not in them, so what the
# board says of a PR says when it was read, never "no PR yet".
CLAIM_MACHINE=laptop PATH="$T/fakebin2:$PATH" "$SH" "$BD" --no-open --offline --out "$T/board5.html" "$T/board5" \
  >/dev/null 2>&1
check "board --offline, where: an open PR read earlier says when" \
  has "$T/board5.html" '"B-2":"feat/two: PR #42 open, CI green, as read 20'
check "board --offline, where: no PR when they were last read, not \"no PR yet\"" \
  has "$T/board5.html" '"B-5":"feat/pushed: pushed, no PR as read 20'
# What checks the code (/checks) decides what shows: no CI word for a repo whose GitHub CI does not count, "no gate"
# for a repo with no gate, and no Gate column at all for a project with none.
grep -v -e '^GATES=' -e '^GITHUB_CI=' .claude/ground-truth.conf >"$T/conf5" && cat "$T/conf5" >.claude/ground-truth.conf
echo 'GATES=("web|true")' >>.claude/ground-truth.conf
CLAIM_MACHINE=laptop PATH="$T/fakebin2:$PATH" "$SH" "$BD" --no-open --out "$T/board6.html" "$T/board5" >/dev/null 2>&1
check "board, gate: no gate for a repo that GATES does not name" grep -qF '"B-2":"no gate"' "$T/board6.html"
check "board, where: no CI word for a repo GITHUB_CI does not name" \
  has "$T/board6.html" '"B-2":"feat/two: PR #42 open, 1 commit not pushed"'
cat "$T/conf5" >.claude/ground-truth.conf
CLAIM_MACHINE=laptop "$SH" "$BD" --no-open --offline --text --out "$T/board7.html" "$T/board5" >"$T/board7.txt" 2>&1
check "board, gate: no column and no gate text in a project with no gate" \
  eval 'has "$T/board7.html" "\"gated\":false," && grep -q "^\"gate\":{}," "$T/board7.html" && lacks "$T/board7.txt" "gate:"'
# Settings, a tab of its own: what Claude does alone, as autonomy.sh reads CLAUDE.md, and how the code is checked
# before a merge, as the conf sets it: each repo, each rule in plain words, kept or not.
cp "$WF/template/CLAUDE.template.md" CLAUDE.md && "$SH" "$AU" preset balanced -f CLAUDE.md >/dev/null
printf '%s\n' 'GATES=("api|true")' 'GATE_PASS=("api|^ok$")' 'GITHUB_CI=("api")' 'GATE_RULES="receipt merge recipt"' \
  >>.claude/ground-truth.conf
CLAIM_MACHINE=laptop "$SH" "$BD" --no-open --offline --out "$T/board8.html" "$T/board5" >/dev/null 2>&1
check "board, settings: each step with its answer, as autonomy.sh reads CLAUDE.md" \
  has "$T/board8.html" '["Commit the docs","do, then tell"]'
check "board, settings: the preset the steps make" has "$T/board8.html" '"autoPreset":"Balanced"'
check "board, settings: a repo with its gate, the line it passes on, its GitHub CI" \
  has "$T/board8.html" '["api","true","^ok$","demo/api"]'
check "board, settings: a repo that nothing checks" has "$T/board8.html" '["docs","","",""]'
check "board, settings: each rule in plain words, kept or not" \
  has "$T/board8.html" '["regression",false,"Each bug fix comes with a check that fails without the fix"]'
check "board, settings: the rules make no preset, and a word that is no rule" \
  has "$T/board8.html" '"rulesPreset":"","rulesUnknown":"recipt","repoRules":[]}'
# The page's own script, run in node on a stand-in for the browser's document: page.js <page> <expression> prints
# what the expression gives once the page has loaded. What the Settings tab shows, and an id's title on hover.
cat >"$T/page.js" <<'JSEOF'
var fs = require("fs"), vm = require("vm"), h = fs.readFileSync(process.argv[2], "utf8");
var data = h.split("<script id=\"data\" type=\"application/json\">")[1].split("</script>")[0];
var code = h.split("<script>\n")[1].split("</script>")[0], els = {};
function el(id) {
  return els[id] || (els[id] = { id: id, innerHTML: "", textContent: id === "data" ? data : "", value: "",
    hidden: false, classList: { toggle: function () {} }, addEventListener: function () {} });
}
var c = { els: els, window: {}, URLSearchParams: URLSearchParams, setInterval: function () {},
  location: { hash: "", href: "file:///board.html" }, history: { replaceState: function () {} },
  sessionStorage: { getItem: function () { return null; }, setItem: function () {}, removeItem: function () {} },
  document: { getElementById: el, addEventListener: function () {}, hidden: true, activeElement: null,
    documentElement: { getAttribute: function () { return ""; } } } };
console.log(String(vm.runInNewContext(code + "\n;(" + process.argv[3] + ")", c)));
JSEOF
if command -v node >/dev/null 2>&1; then
  node "$T/page.js" "$T/board8.html" '(S.tab = "S", render(), els.list.innerHTML + "\nfilters hidden: " + els.filters.hidden)' \
    >"$T/board8-settings.txt" 2>&1
  check "board page, settings: what Claude does alone, a row per step" eval 'has "$T/board8-settings.txt" "<h2>What Claude does alone</h2>" &&
    has "$T/board8-settings.txt" "<tr><td>Commit the docs</td><td class=\"tell\">do, then tell</td></tr>"'
  check "board page, settings: each repo, its gate and its GitHub CI" has "$T/board8-settings.txt" \
    '<tr><td>api</td><td><code>true</code> <span class="muted">passes on a line matching</span> <code>^ok$</code></td><td>demo/api</td></tr>'
  check "board page, settings: a rule not kept" has "$T/board8-settings.txt" \
    '<li class="muted">✗ Each bug fix comes with a check that fails without the fix</li>'
  check "board page, settings: the filters, which no setting has, are hidden" has "$T/board8-settings.txt" "filters hidden: true"
  node "$T/page.js" "$T/board8.html" 'fmt("see B-2, L-2 and B-99")' >"$T/board8-ids.txt" 2>&1
  check "board page, ids: an item's title on hover" has "$T/board8-ids.txt" '<a href="#" data-id="B-2" title="Second">B-2</a>'
  check "board page, ids: a closed item's title, and its state" \
    eval 'grep -qE "data-id=\"L-2\" title=\"[^\"]+ \(✗ dropped\)\">L-2</a>" "$T/board8-ids.txt"'
  check "board page, ids: an id of no item stays text" has "$T/board8-ids.txt" " and B-99"
  node "$T/page.js" "$T/board8.html" 'claimCell(byId["B-2"]) + "\n" + whereCell({ where: "feat/two: PR #42 open" })' \
    >"$T/board8-cells.txt" 2>&1
  check "board page, claimed: the session, cut to a width, the claim line on hover" has "$T/board8-cells.txt" \
    '<td class="who" title="claimed: claude@s1 on feat/two at laptop"><div class="cut">s1</div></td>'
  check "board page, where: cut to a width, whole on hover" has "$T/board8-cells.txt" \
    '<td class="where" title="feat/two: PR #42 open"><div class="cut">feat/two: PR #42 open</div></td>'
  check "board page: Title keeps its width, the columns beside it are cut" \
    eval 'grep -qx "td.title { min-width: 14em; }" "$T/board8.html" && grep -qx "td.where .cut { max-width: 10em; }" "$T/board8.html"'
fi
cd "$T/board2" || exit 1

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
# A claimed item: its "Where" is read from the PRs, which once overwrote the switch that opens the page.
rm -f "$T/opened" && cp "$T/board/BACKLOG.md" "$T/backlog.claim"
awk '{ print } index($0, "B-3 Third") { print "claimed: claude@s1 on feat/three at laptop" }' "$T/backlog.claim" \
  >"$T/board/BACKLOG.md"
nobody DISPLAY=:99 PATH="$T/openers:$PATH" "$SH" "$BD" --out "$T/board.html" "$T/board" >/dev/null 2>&1
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -e "$T/opened" ] && break; sleep 0.2; done
check "board, with a display and a claimed item: the page opens" has "$T/opened" "$T/board.html"
cp "$T/backlog.claim" "$T/board/BACKLOG.md"
check "board, with a display: no text board" lacks "$T/here.txt" "BACKLOG:"

# Before the setup fills the title in, the page is named after the folder, not after the FILL marker.
mkdir -p "$T/unfilled" "$T/tmpdir" && cp "$WF/template/BACKLOG.md" "$WF/template/questions.md" "$T/unfilled/"
BROWSER_DESKTOP=firefox.desktop PATH="$T/fakebin4:$PATH" TMPDIR="$T/tmpdir" \
  "$SH" "$BD" --no-open --offline "$T/unfilled" >/dev/null 2>&1
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
printf '%s\n' '' '### 🔲 B-6 Sixth' 'Done when: done.' >>"$T/board/BACKLOG.md"
hook '{"tool_name":"Bash","tool_input":{"command":"gh pr create --title \"B-6 Sixth\" --body x"}}'
check "hook: a gh pr call alone (a PR opened) rebuilds the page" has "$T/hook.html" '"id":"B-6",'
n=6
for f in /p/CLAUDE.md /p/.claude/ground-truth.conf; do
  n=$((n + 1))
  printf '%s\n' '' "### 🔲 B-$n After $f" 'Done when: done.' >>"$T/board/BACKLOG.md"
  hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$f\"}}"
  check "hook: an edit of a setting ($f) rebuilds the page" has "$T/hook.html" "After $f"
done
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
mkdir -p a/.claude/skills/session-start && cp "$ITS" "$WF/template/dot-claude/skills/session-start/"{claim,lib}.sh \
  a/.claude/skills/session-start/
printf '%s\n' '# Backlog' '' 'next id: B-4 (last given to claude@a)' '' '## api' '' '### 🔲 B-1 First' 'Done when: done.' '' \
  '### 🔲 B-2 Second' 'Done when: done.' '' '### ⏸️ B-3 Later' 'waits: the API' 'Done when: done.' >a/BACKLOG.md
git -C a add -A && git_q -C a commit -m start && git_q -C a push origin main
git_q clone remote.git b
# The machine a claim names: this one's name up to its first dot, or "cloud" in a Claude Code cloud session.
unset CLAIM_MACHINE
hm=$(uname -n) hm=${hm%%.*}
[ "${CLAUDE_CODE_REMOTE:-}" = true ] && hm=cloud
hm=${hm//[[:space:]]/-}
(cd a && "$SH" "$CL" B-1 feat/one) >"$T/claim-a.txt" 2>&1
check "claim: exits 0" [ $? = 0 ]
check "claim: says it is claimed, with the machine" has "$T/claim-a.txt" "CLAIMED: B-1 First, by claude@a on feat/one at $hm (origin/main, "
check "claim: the line is on the remote, under the heading, with the machine" \
  [ "$(git -C remote.git show main:BACKLOG.md | sed -n '7,8p' | tr -d '\r')" = "### 🔲 B-1 First"$'\n'"claimed: claude@a on feat/one at $hm" ]
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
  eval '[ $? = 1 ] && has "$T/claim-over-no.txt" "is claimed by claude@a on feat/one at $hm (origin/main), not by claude@other"'
(cd a && "$SH" "$CL" B-1 feat/one-more claude@a-2 --from claude@a) >"$T/claim-over.txt" 2>&1
check "claim --from: takes the claim over" \
  eval '[ $? = 0 ] && has "$T/claim-over.txt" "CLAIMED: B-1 First, by claude@a-2 on feat/one-more at $hm, taken over from claude@a"'
check "claim --from: the line is replaced, not added" \
  [ "$(git -C remote.git show main:BACKLOG.md | sed -n '7,9p' | tr -d '\r')" = "### 🔲 B-1 First"$'\n'"claimed: claude@a-2 on feat/one-more at $hm"$'\n'"Done when: done." ]
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
check "adopt.sh installs /autonomy, its script executable" \
  [ -f "$T/ws/.claude/skills/autonomy/SKILL.md" -a -x "$T/ws/.claude/skills/autonomy/autonomy.sh" ]

# gate.sh: a repo's gate, and a receipt for each commit that passed it on a clean tree. The rules a project keeps
# (GATE_RULES) and what holds each: "receipt" the pre-push hook, "merge" the ground truth, "regression" /handoff.
GA=.claude/skills/session-start/gate.sh
mkdir "$T/gate" && cd "$T/gate" || exit 1
git_q init --bare remote.git && git -C remote.git symbolic-ref HEAD refs/heads/main
git_q clone remote.git p && cd p || exit 1
git symbolic-ref HEAD refs/heads/main
"$SH" "$WF/bin/adopt.sh" . >/dev/null 2>&1
check "adopt.sh installs gate.sh, executable" [ -x "$GA" ]
check "adopt.sh installs /checks" [ -f .claude/skills/checks/SKILL.md ]
check "adopt.sh lists how the code is checked as left to FILL" \
  eval '"$SH" "$WF/bin/adopt.sh" . 2>&1 | grep -q "then how its code is checked with the /checks skill"'
check "the setup follows /checks for how the code is checked" has "$WF/README.md" '`/checks` skill (`.claude/skills/checks/SKILL.md`)'
check "the template's ground-truth.conf checks nothing and keeps no rule until the setup" \
  eval 'grep -qx "GATE_RULES=\"\"" .claude/ground-truth.conf && grep -qx "GATES=()" .claude/ground-truth.conf &&
    grep -qx "GITHUB_CI=()" .claude/ground-truth.conf'
# The gate passes on "pass", fails otherwise, and edits a tracked file on "edit". grep, not ==: a Windows checkout
# can hold CRLF.
mkdir bin && printf '%s\n' '#!/bin/sh' 'if grep -q edit state.txt; then echo edited >>state.txt; exit 0; fi' \
  'grep -q pass state.txt || { echo "the gate fails"; exit 1; }' >bin/gate
echo pass >state.txt
git add -A && git_q commit -m first && git_q push origin main && git remote set-head origin main
"$SH" "$GA" run >"$T/gate-none.txt" 2>&1
check "gate: no gate set is UNKNOWN (exit 2)" eval '[ $? = 2 ] && has "$T/gate-none.txt" "UNKNOWN: no gate set"'
printf '%s\n' 'GATES=("project|sh bin/gate")' 'GATE_RULES="receipt regression merge"' >>.claude/ground-truth.conf
git add -A && git_q commit -m "the gate" && git_q push origin main
short=$(git rev-parse --short HEAD) head=$(git rev-parse HEAD)
"$SH" "$GA" check >"$T/gate-check0.txt" 2>&1
check "gate check: a commit never gated has no receipt (exit 1)" \
  eval '[ $? = 1 ] && has "$T/gate-check0.txt" "NO RECEIPT: $short has not passed the gate of project here"'
"$SH" .claude/skills/session-start/ground-truth.sh --no-fetch >"$T/gate-gt0.txt" 2>&1
sed 's/^/      | /' "$T/gate-gt0.txt" | sed -n '/== checks/,/^      | $/p'
check "ground truth, gate: the rules kept and their preset" has "$T/gate-gt0.txt" \
  "== checks (rules kept: receipt regression merge = Production)"
check "ground truth, gate: the rule merge flags a default branch with no receipt" has "$T/gate-gt0.txt" \
  "  project (gate: sh bin/gate): origin/main at ${head:0:7}, ⚠ NO RECEIPT: not gated since it last changed (gate.sh run project, on it)"
check "ground truth, gate: the rule receipt flags a repo with no hook" has "$T/gate-gt0.txt" \
  ", ⚠ NO HOOK: a release tag would go out unchecked (gate.sh hook project)"
echo fail >state.txt
"$SH" "$GA" run >"$T/gate-dirty.txt" 2>&1
check "gate run: not run on uncommitted changes (exit 2)" \
  eval '[ $? = 2 ] && has "$T/gate-dirty.txt" "NOT RUN: " && has "$T/gate-dirty.txt" " M state.txt"'
check "gate run: no receipt for a tree with uncommitted changes" [ ! -e ".git/gate-receipts/$head" ]
echo pass >state.txt
"$SH" "$GA" run >"$T/gate-run.txt" 2>&1
check "gate run: a pass writes the receipt (exit 0)" \
  eval '[ $? = 0 ] && has "$T/gate-run.txt" "RECEIPT: $short passed the gate of project"'
check "gate run: the receipt is in the git directory, not in the tree" \
  eval '[ -f ".git/gate-receipts/$head" ] && [ -z "$(git status --porcelain)" ]'
"$SH" "$GA" check project HEAD >"$T/gate-check1.txt" 2>&1
check "gate check: the receipt (exit 0)" eval '[ $? = 0 ] && has "$T/gate-check1.txt" "RECEIPT: $short passed the gate of project on "'
"$SH" .claude/skills/session-start/ground-truth.sh --no-fetch >"$T/gate-gt1.txt" 2>&1
check "ground truth, gate: a default branch gated since it last changed" \
  eval 'has "$T/gate-gt1.txt" "  project (gate: sh bin/gate): origin/main at ${head:0:7}, receipt of " && lacks "$T/gate-gt1.txt" "NO RECEIPT"'
# A worktree of the repo: its commit is gated there, and the receipt is shared with the main checkout.
git_q worktree add ../p-feat -b feat
(cd ../p-feat && git_q commit --allow-empty -m feat && "$SH" "$T/gate/p/$GA" run) >"$T/gate-wt.txt" 2>&1
check "gate run in a worktree: its own commit" \
  eval '[ $? = 0 ] && has "$T/gate-wt.txt" "RECEIPT: $(git rev-parse --short feat) passed the gate of project"'
"$SH" "$GA" check feat >/dev/null 2>&1
check "gate check: the receipt of a worktree's commit, seen from the main checkout" [ $? = 0 ]
echo fail >state.txt && git_q commit -am broken
"$SH" "$GA" run >"$T/gate-fail.txt" 2>&1
check "gate run: a gate that fails, no receipt (exit 1)" eval '[ $? = 1 ] && has "$T/gate-fail.txt" "FAILED: the gate of project exited 1: no receipt for $(git rev-parse --short HEAD)" &&
  [ ! -e ".git/gate-receipts/$(git rev-parse HEAD)" ]'
check "gate run: a failed run is recorded, with its exit code, for the board" \
  grep -qx "exit: 1" ".git/gate-failures/$(git rev-parse HEAD)"
echo edit >state.txt && git_q commit -am edits
"$SH" "$GA" run >"$T/gate-edit.txt" 2>&1
check "gate run: a gate that edits the tree, no receipt (exit 1)" eval '[ $? = 1 ] && has "$T/gate-edit.txt" "NO RECEIPT: the gate passed, but the checkout changed" &&
  [ ! -e ".git/gate-receipts/$(git rev-parse HEAD)" ]'
check "gate run: a checkout changed while the gate passed is no failure" [ ! -e ".git/gate-failures/$(git rev-parse HEAD)" ]
echo pass >state.txt && git_q commit -am fixed
# The rule "receipt": the pre-push hook refuses a release tag whose commit has no receipt.
"$SH" "$GA" hook >"$T/gate-hook.txt" 2>&1
check "gate hook: installed" eval '[ $? = 0 ] && [ -x .git/hooks/pre-push ] && has "$T/gate-hook.txt" "HOOK: installed in "'
"$SH" "$GA" hook >"$T/gate-hook2.txt" 2>&1
check "gate hook: installed again, already there" eval '[ $? = 0 ] && has "$T/gate-hook2.txt" "HOOK: already in "'
git_q push origin main
check "gate hook: a push with no release tag goes" [ "$(git rev-parse origin/main)" = "$(git rev-parse HEAD)" ]
git tag -a v1.0.0 -m "release 1.0.0"
git push origin v1.0.0 >"$T/gate-push0.txt" 2>&1
check "gate hook: a release tag on a commit with no receipt is refused" \
  eval '[ $? != 0 ] && has "$T/gate-push0.txt" "REFUSED: v1.0.0 is on $(git rev-parse --short HEAD), which has not passed the gate here" &&
  [ -z "$(git ls-remote --tags origin v1.0.0)" ]'
mkdir -p .git/gate-failures && echo "failed: before" >".git/gate-failures/$(git rev-parse HEAD)"
"$SH" "$GA" run >/dev/null 2>&1
check "gate run: a pass removes the record of a failure on that commit" [ ! -e ".git/gate-failures/$(git rev-parse HEAD)" ]
git push origin v1.0.0 >"$T/gate-push1.txt" 2>&1
check "gate hook: a release tag on a commit with a receipt goes" \
  eval '[ $? = 0 ] && [ -n "$(git ls-remote --tags origin v1.0.0)" ]'
"$SH" .claude/skills/session-start/ground-truth.sh --no-fetch >"$T/gate-gt2.txt" 2>&1
gate_section() { sed -n '/^== checks/,/^$/p' "$1"; } # <ground truth output>
check "ground truth, gate: no flag once gated and hooked" eval '[ -z "$(gate_section "$T/gate-gt2.txt" | grep "⚠")" ]'
cp .claude/ground-truth.conf "$T/gate-conf.bak"
git_q commit --allow-empty -m "not gated" && git tag v1.0.1
echo 'GATE_RULES="regression merge"' >>.claude/ground-truth.conf
git push origin v1.0.1 >"$T/gate-push2.txt" 2>&1
check "gate hook: without the rule receipt (Steady), a release tag goes" \
  eval '[ $? = 0 ] && [ -n "$(git ls-remote --tags origin v1.0.1)" ]'
"$SH" .claude/skills/session-start/ground-truth.sh --no-fetch >"$T/gate-gt3.txt" 2>&1
check "ground truth, gate: the preset Steady, and no hook needed" \
  eval 'has "$T/gate-gt3.txt" "== checks (rules kept: regression merge = Steady)" && lacks "$T/gate-gt3.txt" "NO HOOK"'
git_q push origin main
echo 'GATE_RULES=""' >>.claude/ground-truth.conf
"$SH" .claude/skills/session-start/ground-truth.sh --no-fetch >"$T/gate-gt4.txt" 2>&1
check "ground truth, gate: the preset Prototype, a missing receipt is no flag" \
  eval 'has "$T/gate-gt4.txt" "== checks (rules kept: none = Prototype)" && has "$T/gate-gt4.txt" ", no receipt" &&
  [ -z "$(gate_section "$T/gate-gt4.txt" | grep "⚠")" ]'
printf '%s\n' 'GATE_RULES="merge recipt"' 'GATES=()' >>.claude/ground-truth.conf
"$SH" .claude/skills/session-start/ground-truth.sh --no-fetch >"$T/gate-gt5.txt" 2>&1
check "ground truth, gate: an unknown rule, and rules with no gate" \
  eval 'has "$T/gate-gt5.txt" "== checks (rules kept: merge recipt, no preset)" && has "$T/gate-gt5.txt" "  ⚠ unknown rule(s) in GATE_RULES: recipt" &&
  has "$T/gate-gt5.txt" "  ⚠ nothing checks the code: the rules kept need a gate or GitHub CI (/checks)"'
cp "$T/gate-conf.bak" .claude/ground-truth.conf
# Another pre-push hook is kept: the script says what to add to it.
mv .git/hooks/pre-push "$T/gate-ours" && printf '%s\n' '#!/bin/sh' 'exit 0' >.git/hooks/pre-push
"$SH" "$GA" hook >"$T/gate-hook3.txt" 2>&1
check "gate hook: never over another hook (exit 1), says what to add" \
  eval '[ $? = 1 ] && has "$T/gate-hook3.txt" "NOT INSTALLED: " && [ "$(sed -n 2p .git/hooks/pre-push)" = "exit 0" ]'
"$SH" "$GA" check nowhere HEAD >/dev/null 2>&1
check "gate: a repo with no gate is UNKNOWN (exit 2)" [ $? = 2 ]
check "/handoff names the check of each bug fix under the rule regression" \
  has "$WF/template/dot-claude/skills/handoff/SKILL.md" '**The rule "regression"**, when the ground truth'"'"'s checks section lists it'
# A gate whose exit code is not its verdict (GATE_PASS): a script that exits 0 once it has run, also with a stage
# skipped, says it passed in a line it prints, in colour. It passes only when it exits 0 and that line is there.
mkdir "$T/gate-line" && cd "$T/gate-line" || exit 1
git_q init && git symbolic-ref HEAD refs/heads/main
"$SH" "$WF/bin/adopt.sh" . >/dev/null 2>&1
mkdir bin && printf '%s\n' '#!/bin/sh' 'g=$(printf "\033[32m") n=$(printf "\033[0m")' \
  'if grep -q skip state.txt; then echo "${g}All checks passed${n} but 1 stage was skipped"; else echo "${g}All checks passed.${n}"; fi' \
  'exit 0' >bin/ci
printf '%s\n' 'GATES=("project|sh bin/ci")' 'GATE_PASS=("project|^All checks passed\.")' >>.claude/ground-truth.conf
echo skip >state.txt && git add -A && git_q commit -m "a stage skipped"
"$SH" "$GA" run >"$T/gate-line1.txt" 2>&1
check "gate run, GATE_PASS: exit 0 without the line is a failure (exit 1), no receipt" \
  eval '[ $? = 1 ] && [ ! -e ".git/gate-receipts/$(git rev-parse HEAD)" ] &&
    has "$T/gate-line1.txt" "FAILED: the gate of project exited 0, but printed no line matching ^All checks passed\.: no receipt for "'
check "gate run, GATE_PASS: the failure is recorded with why" \
  grep -qxF 'why: exited 0, but printed no line matching ^All checks passed\.' ".git/gate-failures/$(git rev-parse HEAD)"
check "gate run, GATE_PASS: the output still shows" has "$T/gate-line1.txt" "but 1 stage was skipped"
echo green >state.txt && git_q commit -am green
"$SH" "$GA" run >"$T/gate-line2.txt" 2>&1
check "gate run, GATE_PASS: exit 0 and the line, in colour, is a pass" \
  eval '[ $? = 0 ] && [ -f ".git/gate-receipts/$(git rev-parse HEAD)" ]'
"$SH" .claude/skills/session-start/ground-truth.sh --no-fetch >"$T/gate-line-gt.txt" 2>&1
check "ground truth, gate: names the line the gate passes on" \
  has "$T/gate-line-gt.txt" "  project (gate: sh bin/ci, passes on a line matching: ^All checks passed\.): "
# GitHub CI as the check (GITHUB_CI): GitHub's rollup of every check on a commit, read with gh, holds the rules as a
# gate does: a release tag needs it green, and so does a default branch with "merge"; a tag is refused while GitHub
# cannot be read. A repo checked by both needs both; with nothing to check, no rule holds.
mkdir "$T/gate-ci" "$T/fakebin3" && cd "$T/gate-ci" || exit 1
git_q init --bare remote.git && git -C remote.git symbolic-ref HEAD refs/heads/main
git_q clone remote.git p && cd p || exit 1
git symbolic-ref HEAD refs/heads/main
"$SH" "$WF/bin/adopt.sh" . >/dev/null 2>&1
printf '%s\n' 'REPOS=("project|.|origin||demo/project")' 'GITHUB_CI=("project")' 'GATE_RULES="receipt regression merge"' \
  >>.claude/ground-truth.conf
git add -A && git_q commit -m first && git_q push origin main && git remote set-head origin main
head=$(git rev-parse HEAD) short=$(git rev-parse --short HEAD)
# The fake gh: `gh api graphql` answers the rollup that $T/gh-ci holds (SUCCESS, FAILURE, none: no check ran, down:
# GitHub cannot be read), and keeps the call; any other call finds nothing.
{ echo '#!/usr/bin/env bash'
  echo "state=\$(cat '$T/gh-ci')"
  cat <<'EOF'
[ "$1 $2" = "api graphql" ] || exit 0
printf '%s\n' "$*" >>"$(dirname "$0")/calls"
[ "$state" = down ] && { echo "error connecting to api.github.com" >&2; exit 1; }
echo "$state"
EOF
} >"$T/fakebin3/gh" && chmod +x "$T/fakebin3/gh"
ci_is() { echo "$1" >"$T/gh-ci"; } # <state>: what GitHub answers from now on
GP="$T/fakebin3:$PATH"
ci_is SUCCESS
PATH=$GP "$SH" "$GA" ci >"$T/ci1.txt" 2>&1
check "gate ci: green (exit 0), on the GitHub repo of REPOS" eval '[ $? = 0 ] && has "$T/ci1.txt" "CI green: $short on demo/project"'
check "gate ci: asks GitHub about that commit of that repo" grep -qF -- "-f owner=demo -f name=project -f oid=$head " "$T/fakebin3/calls"
PATH=$GP "$SH" .claude/skills/session-start/ground-truth.sh --no-fetch >"$T/ci-gt1.txt" 2>&1
check "ground truth, CI: the default branch's last commit, green; the hook missing" has "$T/ci-gt1.txt" \
  "  project (CI: demo/project): origin/main at ${head:0:7}, CI green, ⚠ NO HOOK: a release tag would go out unchecked (gate.sh hook project)"
"$SH" "$GA" hook >/dev/null 2>&1
check "gate hook: installed in a repo that GitHub CI alone checks" eval '[ $? = 0 ] && [ -x .git/hooks/pre-push ]'
ci_is FAILURE
PATH=$GP "$SH" "$GA" ci >"$T/ci2.txt" 2>&1
check "gate ci: red (exit 1)" eval '[ $? = 1 ] && has "$T/ci2.txt" "CI red: $short on demo/project"'
PATH=$GP "$SH" .claude/skills/session-start/ground-truth.sh --no-fetch >"$T/ci-gt2.txt" 2>&1
check "ground truth, CI: the rule merge flags a default branch whose CI is red" has "$T/ci-gt2.txt" \
  "  project (CI: demo/project): origin/main at ${head:0:7}, ⚠ CI red: the default branch is not green"
git tag v1.0.0
PATH=$GP git push origin v1.0.0 >"$T/ci-push1.txt" 2>&1
check "gate hook, CI: a release tag whose commit's CI is red is refused" \
  eval '[ $? != 0 ] && has "$T/ci-push1.txt" "REFUSED: v1.0.0 is on $short, whose CI on demo/project is not green: CI red" &&
    [ -z "$(git ls-remote --tags origin v1.0.0)" ]'
ci_is down
PATH=$GP git push origin v1.0.0 >"$T/ci-push2.txt" 2>&1
check "gate hook, CI: a release tag is refused while GitHub cannot be read, with the reason" \
  eval '[ $? != 0 ] && has "$T/ci-push2.txt" "could not be read (gh api failed: error connecting to api.github.com)"'
PATH=$GP "$SH" .claude/skills/session-start/ground-truth.sh --no-fetch >"$T/ci-gt3.txt" 2>&1
check "ground truth, CI: GitHub that cannot be read is UNKNOWN (exit 2)" eval '[ $? = 2 ] &&
  has "$T/ci-gt3.txt" "UNKNOWN: project: its CI not read: the CI of $short on demo/project could not be read: gh api failed"'
ci_is none
PATH=$GP "$SH" "$GA" ci >"$T/ci3.txt" 2>&1
check "gate ci: no check ran on the commit (exit 1)" eval '[ $? = 1 ] && has "$T/ci3.txt" "no CI: $short on demo/project"'
ci_is SUCCESS
PATH=$GP git push origin v1.0.0 >"$T/ci-push3.txt" 2>&1
check "gate hook, CI: a release tag whose commit's CI is green goes" \
  eval '[ $? = 0 ] && [ -n "$(git ls-remote --tags origin v1.0.0)" ]'
echo 'GATES=("project|true")' >>.claude/ground-truth.conf && git_q commit -am both && git tag v1.0.1
PATH=$GP git push origin v1.0.1 >"$T/ci-push4.txt" 2>&1
check "gate hook, both: CI green and no receipt is refused" \
  eval '[ $? != 0 ] && has "$T/ci-push4.txt" "REFUSED: v1.0.1 is on $(git rev-parse --short HEAD), which has not passed the gate here"'
"$SH" "$GA" run >/dev/null 2>&1
PATH=$GP git push origin v1.0.1 >"$T/ci-push5.txt" 2>&1
check "gate hook, both: a receipt and CI green, the tag goes" eval '[ $? = 0 ] && [ -n "$(git ls-remote --tags origin v1.0.1)" ]'
git_q push origin main
PATH=$GP "$SH" .claude/skills/session-start/ground-truth.sh --no-fetch >"$T/ci-gt4.txt" 2>&1
check "ground truth, both: the gate and CI of a repo on one line" has "$T/ci-gt4.txt" \
  "  project (gate: true; CI: demo/project): origin/main at $(git rev-parse --short=7 HEAD), receipt of "
printf '%s\n' 'GATES=()' 'GITHUB_CI=()' 'GATE_RULES=""' >>.claude/ground-truth.conf && git_q commit -am "nothing yet"
git tag v1.0.2
PATH=$GP git push origin v1.0.2 >/dev/null 2>&1
check "gate hook, nothing yet: no rule holds, the tag goes" eval '[ $? = 0 ] && [ -n "$(git ls-remote --tags origin v1.0.2)" ]'
PATH=$GP "$SH" .claude/skills/session-start/ground-truth.sh --no-fetch >"$T/ci-gt5.txt" 2>&1
check "ground truth, nothing yet: said, with no flag" eval 'has "$T/ci-gt5.txt" "  nothing checks the code before a merge yet (/checks)" &&
  [ -z "$(gate_section "$T/ci-gt5.txt" | grep "⚠")" ]'
printf '%s\n' 'REPOS=("other|elsewhere|origin||")' 'GATE_RULES="receipt"' >>.claude/ground-truth.conf &&
  git_q commit -am "not a repo of REPOS" && git tag v1.0.3
PATH=$GP git push origin v1.0.3 >"$T/ci-push6.txt" 2>&1
check "gate hook: a repo REPOS does not name is refused a release tag, with the reason" \
  eval '[ $? != 0 ] && has "$T/ci-push6.txt" "REFUSED: this repo is not in REPOS of "'
# One repo, then more (attach.sh): the docs belong to the first repo (the root, "." in REPOS) and a second repo is
# attached later by one command: its line in REPOS, a pointer in the repo so a session opened there finds the docs.
cd "$T" || exit 1
TP=$(cd "$T" && pwd -P) # the folder as the scripts spell it (macOS: /private/var, not /var)
git_q init --bare remote-one.git && git_q init --bare remote-svc.git
git_q clone "$T/remote-one.git" one && cd one || exit 1
git symbolic-ref HEAD refs/heads/main
"$SH" "$WF/bin/adopt.sh" "$T/one" >/dev/null 2>&1
check "attach: adopt.sh installs attach.sh, executable" [ -x .claude/skills/session-start/attach.sh ]
printf '%s\n' 'REPOS=("one|.|origin|main|")' 'KEEP_LOCAL=""' 'UNITS=0' >.claude/ground-truth.conf
printf '%s\n' '# One — Backlog' '' 'next id: B-3 (last given to claude@test)' '' '## one' '' '### 🔲 B-1 First' \
  'Done when: done.' '' '## svc' '' '### 🔲 B-2 Second' 'Done when: done.' >BACKLOG.md
git add CLAUDE.md BACKLOG.md questions.md notes .claude && git_q commit -m docs && git_q push -u origin main
git_q clone "$T/remote-svc.git" svc && (cd svc && git symbolic-ref HEAD refs/heads/main && git_q commit --allow-empty -m first &&
  git_q push -u origin main && git remote set-head origin main)
AT=.claude/skills/session-start/attach.sh
"$SH" .claude/skills/session-start/ground-truth.sh >"$T/at-gt0.txt" 2>&1
check "attach: one repo, the docs repo, needs no pointer" lacks "$T/at-gt0.txt" "NO POINTER"
"$SH" "$AT" svc svc >"$T/at1.txt" 2>&1
check "attach: exits 0" [ $? = 0 ]
check "attach: says the line it added" has "$T/at1.txt" "added to REPOS: svc|svc|origin||"
atrepos() { (REPOS=(); . ./.claude/ground-truth.conf; printf '%s\n' "${REPOS[@]}" | tr '\n' ' '); }
check "attach: REPOS has both repos, the first one untouched" [ "$(atrepos)" = "one|.|origin|main| svc|svc|origin|| " ]
check "attach: the pointer is in the repo and names the docs; inside the root it imports nothing (it loads twice)" \
  eval 'has svc/CLAUDE.md "workflow pointer: written by attach.sh" && has svc/CLAUDE.md "\`$TP/one\`" &&
    lacks svc/CLAUDE.md "@$TP/one/CLAUDE.md"'
check "attach: the pointer is kept out of the repo's commits" eval '[ -z "$(git -C svc status --porcelain)" ]'
check "attach: the repo inside the root is kept out of the docs repo" eval '! git status --porcelain | grep -q svc'
"$SH" "$AT" svc svc >"$T/at2.txt" 2>&1
check "attach: run again, exit 0, nothing added twice" \
  eval '[ $? = 0 ] && [ "$(grep -c "^REPOS+=" .claude/ground-truth.conf)" = 1 ] && [ "$(grep -c "^/CLAUDE.md$" svc/.git/info/exclude)" = 1 ]'
"$SH" .claude/skills/session-start/ground-truth.sh >"$T/at-gt1.txt" 2>&1
check "attach: ground truth exits 0 and lists the second repo, with its pointer" \
  eval '[ $? = 0 ] && has "$T/at-gt1.txt" "== svc (svc)" && lacks "$T/at-gt1.txt" "NO POINTER"'
rm svc/CLAUDE.md
"$SH" .claude/skills/session-start/ground-truth.sh >"$T/at-gt2.txt" 2>&1
check "attach: ground truth flags a repo with no pointer, with the command" \
  has "$T/at-gt2.txt" "⚠ NO POINTER: a session opened in $TP/one/svc does not find the docs (bash .claude/skills/session-start/attach.sh svc)"
"$SH" "$AT" svc >"$T/at3.txt" 2>&1
check "attach: a name already in REPOS gets its pointer back, no path needed" \
  eval '[ $? = 0 ] && [ -f svc/CLAUDE.md ] && [ "$(grep -c "^REPOS+=" .claude/ground-truth.conf)" = 1 ]'
git_q add .claude/ground-truth.conf && git_q commit -m "svc attached" && git_q push origin main
"$SH" .claude/skills/session-start/claim.sh B-2 feat/two claude@test >"$T/at-claim.txt" 2>&1
check "attach: a claim still works with two repos" eval '[ $? = 0 ] && has "$T/at-claim.txt" "CLAIMED: B-2 Second"'
"$SH" .claude/skills/session-start/board.sh --no-open --offline --out "$T/at-board.html" "$T/one" >/dev/null 2>&1
check "attach: the board lists both repos" has "$T/at-board.html" '"repos":["one","svc"]'
# A repo with a CLAUDE.md of its own keeps it; the pointer is CLAUDE.local.md. A repo outside the root is allowed.
git_q clone "$T/remote-svc.git" "$T/far" && printf '%s\n' '# the repo own rules' >"$T/far/CLAUDE.md"
"$SH" "$AT" far "$T/far" >"$T/at4.txt" 2>&1
check "attach: a repo outside the root, with a CLAUDE.md of its own: that file untouched, the pointer beside it" \
  eval '[ $? = 0 ] && [ "$(cat "$T/far/CLAUDE.md")" = "# the repo own rules" ] &&
    has "$T/far/CLAUDE.local.md" "workflow pointer: written by attach.sh" && has "$T/far/CLAUDE.local.md" "@$TP/one/CLAUDE.md" && ! git -C "$T/far" status --porcelain | grep -q CLAUDE.local'
"$SH" .claude/skills/session-start/ground-truth.sh >"$T/at-gt3.txt" 2>&1
check "attach: ground truth accepts a CLAUDE.local.md pointer" lacks "$T/at-gt3.txt" "NO POINTER"
"$SH" "$AT" nope "$T/nowhere" >"$T/at5.txt" 2>&1
check "attach: a path that is not a git checkout is UNKNOWN (exit 2), REPOS unchanged" \
  eval '[ $? = 2 ] && has "$T/at5.txt" "UNKNOWN: " && [ "$(grep -c "^REPOS+=" .claude/ground-truth.conf)" = 2 ]'
cd "$T" || exit 1

# Rules of one repo (REPO_RULES): the project keeps receipt, regression and merge (GATE_RULES), web keeps none of
# them. Each reader looks at the rules of the repo it is looking at: the hook, the checks section, the board.
cd "$T" || exit 1
git_q init --bare remote-rr-api.git && git_q init --bare remote-rr-web.git && git_q init --bare remote-rr-docs.git
mkdir rr && cd rr || exit 1
git_q init && git symbolic-ref HEAD refs/heads/main && git remote add origin "$T/remote-rr-docs.git"
for n in api web; do
  git_q clone "$T/remote-rr-$n.git" $n && (cd $n && git symbolic-ref HEAD refs/heads/main && git_q commit --allow-empty -m first &&
    git_q push -u origin main && git remote set-head origin main)
done
"$SH" "$WF/bin/adopt.sh" "$T/rr" --workspace >/dev/null 2>&1
printf '%s\n' 'REPOS=("api|api|origin|main|" "web|web|origin|main|")' 'UNITS=0' 'GATES=("api|true" "web|true")' \
  'GATE_RULES="receipt regression merge"' 'REPO_RULES=("web|")' >.claude/ground-truth.conf
git add .gitignore CLAUDE.md BACKLOG.md questions.md notes .claude && git_q commit -m docs && git_q push -u origin main
RR=.claude/skills/session-start
"$SH" $RR/ground-truth.sh --no-fetch >"$T/rr-gt.txt" 2>&1
sed 's/^/      | /' "$T/rr-gt.txt" | sed -n '/== checks/,/^      | $/p'
check "rules per repo: the checks section names the project's rules" has "$T/rr-gt.txt" \
  "== checks (rules kept: receipt regression merge = Production)"
check "rules per repo: the repo with rules of its own says so" \
  eval 'grep "^  web (" "$T/rr-gt.txt" | grep -qF "[its own rules: none = Prototype]"'
check "rules per repo: a repo without an entry follows the project's rules" \
  eval 'grep "^  api (" "$T/rr-gt.txt" | grep -qF "⚠ NO RECEIPT" && grep "^  api (" "$T/rr-gt.txt" | grep -qF "⚠ NO HOOK" && 
    ! grep "^  api (" "$T/rr-gt.txt" | grep -qF "its own rules"'
check "rules per repo: a repo that keeps no rule is not flagged for its receipt or its hook" \
  eval '! grep "^  web (" "$T/rr-gt.txt" | grep -qF "⚠"'
"$SH" $RR/gate.sh hook api >/dev/null 2>&1 && "$SH" $RR/gate.sh hook web >/dev/null 2>&1
check "rules per repo: gate.sh hook installs the hook in both" eval '[ -x api/.git/hooks/pre-push ] && [ -x web/.git/hooks/pre-push ]'
(cd api && git tag -a v1.0.0 -m one && git push origin v1.0.0) >"$T/rr-push-api.txt" 2>&1
check "rules per repo: a release tag with no receipt is refused where the rule receipt holds" \
  eval '[ $? != 0 ] && has "$T/rr-push-api.txt" "REFUSED: v1.0.0 is on " && [ -z "$(git -C api ls-remote --tags origin v1.0.0)" ]'
(cd web && git tag -a v1.0.0 -m one && git push origin v1.0.0) >"$T/rr-push-web.txt" 2>&1
check "rules per repo: the same tag goes where the repo keeps no rule" \
  eval '[ $? = 0 ] && [ -n "$(git -C web ls-remote --tags origin v1.0.0)" ]'
"$SH" $RR/board.sh --no-open --offline --out "$T/rr-board.html" "$T/rr" >/dev/null 2>&1
check "rules per repo: the board has the rules of that repo, with its preset" has "$T/rr-board.html" '"repoRules":[["web","","Prototype"]]'
printf '%s\n' 'REPO_RULES+=("ghost|merge" "api|recipt")' >>.claude/ground-truth.conf
"$SH" $RR/ground-truth.sh --no-fetch >"$T/rr-gt2.txt" 2>&1
check "rules per repo: a repo REPOS does not name, and a word that is no rule, are flagged" \
  eval 'has "$T/rr-gt2.txt" "  ⚠ ghost (REPO_RULES): not a repo of REPOS" &&
    has "$T/rr-gt2.txt" "  ⚠ unknown rule(s) in REPO_RULES for api: recipt"'
cd "$T" || exit 1

# The Gate column also says where the CI of the branch's last commit stands: green, red, running with the jobs done,
# not read; --offline shows the verdict last read of that commit, with the time. A repo checked by CI alone, or by a
# gate alone, shows only what applies.
cd "$T" || exit 1
git_q init --bare remote-c51.git && git_q init --bare remote-c51-docs.git
mkdir c51 && cd c51 || exit 1
git_q init && git symbolic-ref HEAD refs/heads/main && git remote add origin "$T/remote-c51-docs.git"
git_q clone "$T/remote-c51.git" app && (cd app && git symbolic-ref HEAD refs/heads/main && git_q commit --allow-empty -m first &&
  git_q push -u origin main && git remote set-head origin main &&
  git_q checkout -b feat/one && git_q commit --allow-empty -m one && git_q push -u origin feat/one)
"$SH" "$WF/bin/adopt.sh" "$T/c51" --workspace >/dev/null 2>&1
conf51() { # <GATES> <GITHUB_CI>: the project's checks
  printf '%s\n' 'REPOS=("app|app|origin|main|demo/app")' 'UNITS=0' "GATES=($1)" "GITHUB_CI=($2)" >.claude/ground-truth.conf
}
conf51 '"app|true"' '"app"'
mkdir -p app/.git/gate-receipts && echo "passed: now" >"app/.git/gate-receipts/$(git -C app rev-parse feat/one)"
printf '%s\n' '# Demo — Backlog' '' 'next id: B-2 (last given to claude@s1)' '' '## app' '' '### 🔲 B-1 First' \
  'claimed: claude@s1 on feat/one at laptop' 'Done when: done.' >BACKLOG.md
git add .gitignore CLAUDE.md BACKLOG.md questions.md notes .claude && git_q commit -m docs
mkdir "$T/fakebin51" && cat >"$T/fakebin51/gh" <<'EOF'
#!/usr/bin/env bash
T=${C51_DIR:?}
case "$*" in
  "api graphql"*)
    v=$(cat "$T/c51-verdict")
    [ "$v" = down ] && { echo "error connecting to api.github.com" >&2; exit 1; }
    echo "$v" ;;
  "api repos/demo/app/commits/"*"/check-runs"*) cat "$T/c51-runs" ;;
  *) echo "HTTP 404: Not Found" >&2; exit 1 ;;
esac
EOF
chmod +x "$T/fakebin51/gh"
c51() { # <verdict> [<jobs done/all>] [board.sh options...]: build the board with GitHub saying that; data in $T/c51.html
  echo "$1" >"$T/c51-verdict" && echo "${2:-0/0}" >"$T/c51-runs"
  C51_DIR=$T CLAIM_MACHINE=laptop PATH="$T/fakebin51:$PATH" "$SH" .claude/skills/session-start/board.sh --no-open \
    --out "$T/c51.html" "${@:3}" "$T/c51" >"$T/c51.txt" 2>&1
}
ci51() { grep -qF "\"ci\":{\"B-1\":\"$1\"}" "$T/c51.html"; } # <text>: the CI map of the data
c51 PENDING 2/3
check "board, CI: running, with the jobs done" ci51 "CI running 2/3"
check "board, CI: beside the gate, which still says passed" has "$T/c51.html" "\"gate\":{\"B-1\":\"passed ($(git -C app rev-parse --short=7 feat/one))\"}"
c51 SUCCESS; check "board, CI: green" ci51 "CI green"
c51 FAILURE; check "board, CI: red" ci51 "CI red"
c51 down; check "board, CI: GitHub that cannot be read is not read, never green" ci51 "CI not read"
c51 SUCCESS
c51 FAILURE 0/0 --offline
check "board --offline, CI: the verdict last read of that commit, with when" has "$T/c51.html" '"ci":{"B-1":"CI green, as read 20'
git -C app commit -q --allow-empty -m two && git -C app push -q origin feat/one
c51 SUCCESS 0/0 --offline
check "board --offline, CI: a commit never read is not read, not green" ci51 "CI not read: --offline"
c51 SUCCESS 0/0 --text
check "board --text, CI: under the item" has "$T/c51.txt" "        CI: CI green (of the last commit of its branch)"
conf51 '' '"app"'
c51 PENDING 1/4
check "board, CI: a repo checked by CI alone shows the CI, no gate text" \
  eval 'has "$T/c51.html" "\"gated\":true," && has "$T/c51.html" "\"gate\":{}," && ci51 "CI running 1/4"'
conf51 '"app|true"' ''
c51 SUCCESS
check "board, CI: a repo checked by a gate alone shows no CI" eval 'has "$T/c51.html" "\"ci\":{}," && has "$T/c51.html" "\"B-1\":\"not run on the last commit; passed at "'
cd "$T" || exit 1

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) FAILED"
  exit 1
fi
echo "all checks passed"
