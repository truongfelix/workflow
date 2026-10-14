# workflow — Claude Code sessions that pick up where the last one left off

[![test](https://github.com/truongfelix/workflow/actions/workflows/test.yml/badge.svg)](https://github.com/truongfelix/workflow/actions/workflows/test.yml)

Every Claude Code session starts with an empty context. The usual fix is a notes file that the agent updates at the
end of the day and reads the next morning. It works until the notes are wrong: a branch marked "pushed" that never
reached the remote, a job "still running" that died at 1 a.m., a to-do that shipped last week. The next session
believes them and builds on them.

This template keeps a project going across sessions, machines and weeks with five skills and a script:

- **`/session-start`** runs `ground-truth.sh`, which reads the facts from git, GitHub and the machine: every repo and
  worktree against its remote (or the branch it tracks on another one), open PRs and their CI, the items other
  sessions claimed and their branches, background jobs. Then it reads the last handoff, reports where the two
  disagree, proposes the day's task, and waits for you (or starts it, if you told it to). When an agent starts working
  on the task, it claims it: `claim.sh` pushes a `claimed:` line that names the agent, so two sessions in parallel
  never take the same item.
- **`/handoff`** runs the same script, rewrites the handoff from it, updates the trackers (open work, your pending
  decisions, lessons learned), and commits.
- **`/board`** opens the trackers, lessons and handoffs as one page, with filters and each item's history, and for
  each claimed item where its work is (on which machine, pushed or not, in an open PR with its CI, or merged) and
  whether it passed the project's own check on this machine; an id shows its item's title on hover. Its Settings tab
  shows what Claude does alone, how the code is checked, and when the rulings and lessons are due a trim. A hook rebuilds it after each change, and an open tab
  updates itself. Where no browser can show it (a cloud session, SSH), it prints the open items instead.
- **`/autonomy`** shows what Claude does without asking you, step by step (commit, push, open or merge a PR,
  release, …), and changes it: a preset, or the steps you pick from a list.
- **`/checks`** shows how the code is checked before a merge (its own check, such as its tests; GitHub CI; both; or
  nothing yet) and the rules kept, such as "a release needs a pass on its exact commit", and changes them.
- **`/trim`** proposes one plan for your rulings and lessons, in a session of its own, once the brief says a file grew
  past the size you set. It asks the same questions of each entry (still true? enforced by a check? said by a doc?
  would the mistake come back?), then keeps, shortens, moves, merges or deletes it (git keeps it); you change only the
  lines you disagree with.

The handoff is a claim; the script is the fact. `/session-start` and `/handoff` run the same script, so the session
that writes the note and the session that reads it look at the same picture.

## What it looks like

Monday morning, `/session-start` on a project whose last session ended on Friday. It ran the ground truth, read
Friday's handoff, checked each claim it was about to repeat (the failed unit's log, the two commits not pushed, the
red CI job), and answered:

```text
Since last session (Fri 9 Oct, 18:40)
- ⚠ B-16 Backfill ingredients on staging: the backfill failed on Saturday at 01:12, at batch 212
  of 340: "No space left on device" on /var/lib/pantry. The handoff expected it to end by 03:00.
- ⚠ B-12 Shopping list works offline: feat/offline-list has 2 commits that were never pushed
  (Fri 19:05 and 19:20, after the handoff). The handoff calls the branch pushed and the edit
  queue "not started": those commits are the queue and its replay.
- ⚠ web: spike/pwa-cache exists only on this laptop, and no note mentions it.
- B-7 Unit conversion on import: PR #41 is CI red: test_round_to_5g, a pinch of salt rounds
  to 0 g.
- #39 (search by ingredient) is merged, as the handoff says.

Today
1. B-7 Unit conversion on import [api]: fix the rounding in #41 so small quantities keep at
   least 1 g. Thursday's release needs it. Done when CI is green and you have merged it.
2. B-16 Backfill ingredients on staging [ops]: free space on /var/lib/pantry and resume from
   batch 212. Done when the unit exits 0 and 20 recipes check out on staging.
3. B-12 Shopping list works offline [web]: push the 2 commits, then finish it: conflict
   handling and the phone test are left.

Waiting for you
- Q-3 Metric only on the shopping list? I recommend metric only: it matches #41, and a switch
  can come later.
- spike/pwa-cache: push it, keep it local on purpose, or delete it?
- B-15 Import rejects recipes with no yield was claimed on 1 Oct by another session
  (api-yield-3), and its branch has had no commit since: release it, so a session can take it?

I'd start with 1: it is small, and the release waits on it. Which one?
```

A session that trusted Friday's note alone would have asked for a red PR to be merged, reported the backfill as
done, and rewritten code that already existed. The whole scenario, with every file behind this brief and the
script's output, is in [`example/`](example/).

## Quick start

You need bash, git and a remote for your project (on GitHub or any git host): the workflow keeps its state in git.
Optional: the GitHub CLI `gh` (open PRs and CI) and systemd (background jobs, Linux only).
Runs on Linux, macOS and Windows: in Git Bash, which Claude Code uses on Windows, or in WSL. CI tests all three.

```bash
git clone https://github.com/truongfelix/workflow.git
workflow/bin/adopt.sh ~/code/my-project     # copies the template; never overwrites a file
```

Then open Claude Code in your project and ask:

> Set up the workflow: follow "Adopt in a new project" in /path/to/workflow/README.md

Claude first asks for your project's git remote, then where its notes and to-do lists live (with the code, or in a
repo of their own), then what it may do without asking you (commit, push, open a PR, merge, …: a preset, then any
change), then fills in the blanks (what the project is, its repos, how its code is
checked, its rules), runs the ground truth until it comes back clean, and runs `/handoff` once to write the first
handoff. You change any of those answers whenever you want, in words ("from now on, push the docs without asking")
or with `/autonomy` and `/checks`. From then on: `/session-start` when you sit down, `/handoff` before you stop,
`/board` whenever you want to see the work at a glance.

## What you get

```
session N:   /session-start ──► work ──► /handoff
                   ▲                         │
                   └──── git (trackers) ◄────┘   ← session N+1, any machine or cloud session
```

| file | holds |
|---|---|
| `notes/handoff/<session>.md` | today, one file per session: next tasks, what waits for you, what runs in the background, what is unfinished, done and learned. Short, rewritten at each handoff; earlier ones are in git |
| `BACKLOG.md` | open work only, one section per repo, each item with an id (`B-12`) that never changes. A finished item is deleted, not ticked: git keeps the history |
| `questions.md` | decisions only you can make, each with options and a recommendation; past rulings, so no session "fixes" them. Ids too (`Q-4`) |
| `notes/item-format.md` | the one shape of every item in both trackers and the lessons, and how a new item gets its id |
| `notes/handoff-format.md` | the one shape of a handoff, with its id (`H-12`) |
| `notes/lessons.md` | what the project learned the hard way, loaded into every session. Ids too (`L-3`) |
| `CLAUDE.md` | what the project is, what Claude does without asking you, its rules and commands. No to-dos, no history |
| `.claude/ground-truth.conf` | the repos the script checks, branches that must never be pushed, when a claim is stale, when `questions.md` and `notes/lessons.md` need a trim, how the code is checked before a merge (each repo's gate, the command that says the code is ready, such as its tests; its GitHub CI) and the rules you keep, for the project or for one repo |
| `.claude/skills/` | `/session-start` (with `ground-truth.sh`; `items.sh`, the parser and format check of the trackers, lessons and handoffs, whose `show <id>` prints any item, live or from git; `claim.sh`, which takes an item for a session, on its branch and machine; `attach.sh`, which adds a code repo to the list and writes its pointer; `gate.sh`, which runs a repo's gate, keeps a receipt of each commit that passed it, and reads a commit's CI on GitHub; `board.sh`, the trackers, lessons and handoffs as one page, with the commits and PRs behind each item and where the work of each claimed item is, and the settings; `lib.sh`, what these scripts share), `/handoff`, `/board`, `/autonomy` (with `autonomy.sh`), `/checks` and `/trim` |
| `.claude/settings.json` | the hook that rebuilds the board after each change to the trackers, the settings or the git history |

It fits one repo, or several (a fork, an app, a backend). There is one design: a docs repo, and a list of the code
repos it follows (`REPOS`). The docs either belong to the main repo, which is then the first entry of the list, or have
a repo of their own; more repos are added to the list later with one command (`attach.sh`, below). How Claude Code's
machine-local memory fits next to these files:
[`memory/README.md`](memory/README.md).

## The ideas behind it

[`PRINCIPLES.md`](PRINCIPLES.md) explains why each piece exists. Every rule in it comes from something that went
wrong. A few:

- **Claims and facts are different things.** A note written by a past session is a claim. Check it against git and
  the machine before acting on it or repeating it.
- **Finished work is deleted, not ticked.** A done entry rots while it still reads as true, and it buries the open
  ones. Git keeps the history.
- **An unreadable result is UNKNOWN, never a pass.** A check that crashes prints nothing, which reads as "found
  nothing". The script says UNKNOWN and exits 2.
- **Nothing exists only on one disk without being named.** Uncommitted work on a dead laptop does not exist.
- **Propose, then wait.** The session recommends; you pick the day's work.
- **Only approved items are built.** A new idea or a bug met on the way becomes a backlog item first, and is built
  once you approve it. So the backlog does not drift: it stays the whole list of the work.
- **You choose what Claude does alone.** One table: for each step (the day's task, commit, push, PR, merge, release,
  messages), ask you first, or do it and tell you. Set at setup, changed whenever you say so.

## Adopt in a new project

The detailed steps, written for the Claude session doing the setup (you can follow them by hand too). Read
`PRINCIPLES.md` first; then:

1. **Get the workflow:** a clone of this repo on the machine. **Then a git remote, before any other question:** the
   workflow does not work without one (the ground truth compares each branch with it, a claim is a push to it, and
   the next session, on any machine, starts from what it holds). Ask the owner for the remote this folder is pushed
   to (a private one if the folder will hold other repos: step 2). A folder that is not a git repo yet gets
   `git init`; with no remote yet, offer to create one (`gh repo create <name> --private`) and wait for the
   owner's yes. Set it as `origin`. On GitHub, before the first commit: GitHub refuses a push whose commits show an
   email address the owner keeps private. Unless `git config user.email` is already a `users.noreply.github.com`
   address, ask: "GitHub can refuse pushes that show your email address. Use your GitHub no-reply address as this
   project's commit email?" On a yes, set it for this repo alone (another clone needs the same line):
   `git config user.email "$(gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"')"`
2. **Choose where the docs live.** Ask the owner this, as a multiple-choice question that recommends neither: both
   are valid, and the owner knows what the folder holds or will hold. Ask it in these words (they follow the rule "A
   question to the owner" of `CLAUDE.md`), changing only what the owner has told you:
   > **Where should this project's notes and to-do lists live?**
   > 1. **With the code, in one repo.** The notes are saved in the same repo as your code. This is simpler. You can
   >    add other repos to the project later. The notes stay with that repo and can't be moved out afterwards.
   > 2. **In a separate repo of their own.** The notes get a private repo, and every code repo is attached to it. This
   >    takes one more repo to set up. Pick it if your code may become public and your notes must stay private. It
   >    also suits a project with several repos from the start.

   What the answer does: the first makes the project root the repo that holds the docs, committed with its code, and
   other repos are attached later with `attach.sh`. The second makes the root a folder that holds only the docs
   (CLAUDE.md, trackers, `notes/`, `.claude/`), with a whitelist `.gitignore` so the code repos inside it, data and keys
   stay out, and a PRIVATE remote; every code repo is attached to it.
3. **Install:** `bin/adopt.sh <project-root>` (add `--workspace` when the docs have their own repo). It copies only missing files,
   prints the ones it skipped with a diff command, and lists the FILL markers.
4. **Fill**, in this order. The owner has not read these files: all the setup says or writes for the owner (its
   questions, its summary at the end, the items it adds) is in plain words, with no preset name either, and each
   question follows `CLAUDE.md`'s rule "A question to the owner". Free text (what the project is, its rules) is an
   open question in the chat, never an option that only says "I'll type it", which returns no text when picked; a
   folder's name is not what the project is.
   - `CLAUDE.md`, **What Claude does alone**, first: the steps below follow it. Follow the `/autonomy` skill
     (`.claude/skills/autonomy/SKILL.md`): the owner picks a preset, with each step listed in plain words, then keeps
     it or picks the steps to switch. Its script sets the rows and deletes the FILL comment.
   - `.claude/ground-truth.conf`: one line per repo (the remote that counts as "pushed" is YOURS in a fork, not
     upstream), and KEEP_LOCAL for branches that must never be pushed. The docs repo is `.`, first in the list: give
     it a name in place of the template's `project` (the project's, or `docs` when the docs have a repo of their
     own). Attach every other repo with `bash .claude/skills/session-start/attach.sh <name> <path>`, which adds its
     line and writes its pointer (below), also later, whenever a repo joins the project; a repo attached later also
     gets its check (`/checks`) and its line in `CLAUDE.md` (what the project is, repos and layout).
   - How the code is checked before a merge: follow the `/checks` skill (`.claude/skills/checks/SKILL.md`): the
     project's own check, GitHub CI, both or nothing yet, each repo's check command, and the rules kept. It sets
     their lines in `.claude/ground-truth.conf` and installs the hook that holds the release rule.
   - Delete the two FILL lines at the top of `.claude/ground-truth.conf`, then run
     `bash .claude/skills/session-start/ground-truth.sh` until it ends with `GROUND TRUTH: complete`.
   - The rest of `CLAUDE.md`: what the project is, who owns it (ask: a commit's author is only a guess), what is
     public and what must stay private, repos and layout, commands, and the project's rules. A rule is
     what Claude must always or never do in this project ("greet.sh stays plain bash", "never touch `migrations/`",
     "a change is done when `make test` passes"). Ask the owner with such examples, and say that it is not the table
     above and that none is fine: rules come as the project meets them. Move any existing to-do list out of
     `CLAUDE.md` into `BACKLOG.md`.
   - `BACKLOG.md`: one section per repo or file tree, filled from what the project already tracks (issues, notes, an
     old TODO). Each item in the shape of `notes/item-format.md`: an id from `next id`, what is wrong or missing, a
     pointer, `Done when:`. An old to-do file whose lines are now items: ask the owner whether to delete it (git keeps
     it); it is not the docs, so a commit that deletes it is pushed as code (the table's rows for code).
   - `questions.md`: decisions the owner still has to make, and rulings already made that a newcomer would undo,
     in the same shape. Then `bash .claude/skills/session-start/items.sh check` until it exits 0.
   - The skills' FILL item (project-specific checks, what is expected and not news).
   - `.claude/settings.json`, only when `adopt.sh` listed it as skipped (the project had its own): add the
     template's `PostToolUse` hook to it, which rebuilds the board after each change. When `adopt.sh` installed it,
     the hook is there and there is nothing to do or report.
5. **Commit and push the setup**, in either shape. Stage the setup's paths by name (`git add <paths>`, never `-A`)
   and read the staged list (`git diff --cached --name-only`). Docs in a repo of their own: at the root, the repo of
   step 1, check `git status --ignored` too; never track a datadir, a key or a binary. Scan the staged files for
   secrets: `gitleaks git --staged` (gitleaks 8.19 and later; before: `gitleaks protect --staged`). Commit, then push
   to the remote of step 1 as the table allows: the setup's files are the docs.
6. **Close the loop:** run `/handoff` once, so the first handoff (`notes/handoff/<session>.md`) is written from the
   ground truth. Then end the setup with one sentence for each skill, when to use it and what it is for:
   `/session-start` when you sit down (it checks git and the machine, reads the last handoff and proposes the day's
   task), `/handoff` before you stop or switch machines (it records where things stand, so the next session picks
   up from there), `/board` whenever you want to see the work (the backlog, your decisions, the lessons and the
   handoffs as one page), `/autonomy` whenever you want Claude to ask you more or less often (it shows each step
   and what Claude does there, and changes the ones you pick), `/checks` when the way the code is checked changes (a
   first test command, GitHub CI added, a rule kept or dropped), `/trim` when the brief says a trim is due (it proposes
   what to keep, shorten, move or delete in your rulings and lessons, and you decide).

Existing project with its own session docs: adopt anyway (nothing is overwritten), then merge by hand, keeping the
project's content and the template's structure.

## A session opened in a code repo

A session finds the project's rules in the `CLAUDE.md` of the folder it is opened in and of the folders above it. A code
repo inside the docs repo's folder is covered by the docs' `CLAUDE.md` above it; a repo elsewhere on the disk, or any
repo whose own `CLAUDE.md` loads alone, is not. So `attach.sh` writes a **pointer** in each attached repo: a short
`CLAUDE.md` (or `CLAUDE.local.md`, when the repo has a `CLAUDE.md` of its own, which is left alone) that says where the
docs are, to start the session there, and, for a repo outside the docs repo's folder, imports the docs' `CLAUDE.md` so its
rules load too (inside the folder they load already). It is kept out of the
repo's commits (`.git/info/exclude`), since it names a path on this machine, and `ground-truth.sh` reports an attached repo
that has none (`NO POINTER`). The first time a session opens in a repo outside the folder, after asking whether you
trust the folder, Claude Code asks whether to allow that import, files outside the repo (the docs' lessons too):
allow it. It keeps the answer for that folder and never asks again (`hasClaudeMdExternalIncludesApproved` in
`~/.claude.json`), and a session that cannot ask (`claude -p`, a script) loads the import only where an interactive
session allowed it. Where it did not load, the pointer tells the session to read the docs' `CLAUDE.md` and its imports
before any work, or to stop and say so when it cannot: an interactive session reads them (asking you first when its
permission mode does), and `claude -p` reads them with `--add-dir <the docs folder>`.

Two limits. The pointer exists on the machine where `attach.sh` ran: a clone on another machine needs the script run
again there. And a cloud session works on one repo, so it cannot work on a project with several: the docs repo and the
code repos are cloned side by side only on your own machines.

## Upgrade a project from here

`bin/adopt.sh <project-root>` again lists every skipped file with its `diff -u` command against the current
template. Merge the generic parts; keep the project's FILL answers. The skills' scripts (`.claude/skills/*/*.sh`)
hold no answer of the project: take the template's, all of them at once (they share `session-start/lib.sh`); a
`SKILL.md` keeps the project's answer to its FILL item. `.claude/workflow-version` names the release `adopt.sh` last
ran from, as the releases page names it: `v1.0.0`, or `v1.0.0-3-gabc1234` three commits after it. An upgrade changes
only the docs (`CLAUDE.md`, the trackers, `notes/`, `.claude/`): commit and push it as the rows "Commit the docs"
and "Push the docs" say, its paths staged by name.

From 1.x, in this order:
1. **The new files:** `adopt.sh` installs what 1.x did not have: the skills `/board`, `/autonomy`, `/checks` and
   `/trim`, the scripts beside `ground-truth.sh`, `notes/item-format.md`, `notes/handoff-format.md`, and
   `.claude/settings.json`, whose hook rebuilds the board after each change (a project with a `settings.json` of its
   own: add the template's `PostToolUse` hook to it). The files 1.x had are skipped and differ: the steps below.
2. **`CLAUDE.md`:** the "outward actions" rule and the handoff rule became the table "What Claude does alone": copy it
   from the template with its bullets, and delete its FILL comment (a preset would undo the rows set here). Every row
   is "ask first", except what the old handoff rule allowed, which becomes "do, then tell":
   - "/handoff asks before committing": no row.
   - "/handoff commits and pushes the docs": "Commit the docs" and "Push the docs".
   - "/handoff commits and pushes everything": those two, "Commit code" and "Push a work branch".

   The old rules settled the commits and the outward actions (pushes, pull requests, merges, releases, messages). Six
   rows are new: start the day's task, add an item to the backlog, claim one, build something that is not an approved
   backlog item, delete a branch or worktree whose work has landed, stop a background job. Ask the owner about those
   with `/autonomy`, "change some steps", never with a preset. Copy the bullet "A question to the owner" from the
   template's Rules too: `/autonomy`, `/checks` and the setup ask the owner as it says.
3. **`.claude/ground-truth.conf`:** 1.x had `REPOS`, `KEEP_LOCAL` and `UNITS`. Take the template's file and put the
   project's three lines back in it, the docs repo (`.`) first in `REPOS`: it adds when a claim is stale, the sizes
   that call for `/trim`, and how the code is checked. Run `/checks` (the project's own check, GitHub CI, both or
   nothing yet, and the rules kept), then delete the file's two FILL lines. A code repo of `REPOS` gets a pointer
   (`attach.sh`, "A session opened in a code repo"): `bash .claude/skills/session-start/attach.sh <name>` for each; the
   ground truth says `NO POINTER` until then.
4. **The trackers:** their items and the lessons moved from bullets cited by title to one shape with ids. The last
   section of `notes/item-format.md`, "Moving a project to it", is the conversion, done once, each tracker's header
   included (1.x's says to cite an item by its title). `.claude/skills/session-start/items.sh check` lists what is
   left. An item's history before its id is found by its title (`git log -S'<title>' -- BACKLOG.md`): the board and
   `items.sh show` start at the conversion.
5. **Commit and push** the upgrade, as above. `items.sh check` still lists the old `notes/handoff.md`: the next step
   moves it.
6. **The handoff:** the one `notes/handoff.md` with its archive became one handoff per session, with git as the
   archive (`notes/handoff-format.md`, "Moving a project to it"). Run `/handoff` once: it moves it, and commits it as
   the table says. Then `items.sh check` exits 0 and the ground truth ends `GROUND TRUTH: complete`.

`/trim` is new: it proposes a plan for the rulings of `questions.md` and the lessons, in a session of its own. The
ground truth flags `questions.md` past `QUESTIONS_TRIM_LINES` and `notes/lessons.md` past `LESSONS_TRIM_LINES` (1000
lines each), and `/session-start` suggests `/trim` on the flag.

## Improve the workflow

When a project's session improves a generic piece (a skill step, a ground-truth check, a principle learned the hard
way), port the generic part back here in its own commit, with the reason. Project-specific content never comes back
here, and neither do lessons: a lesson stays in the `notes/lessons.md` of the project that learned it.

## Layout of this repo

```
template/                     copied into a project's root by bin/adopt.sh
  CLAUDE.template.md          skeleton with FILL markers, installed as CLAUDE.md
  BACKLOG.md  questions.md  notes/lessons.md
  notes/handoff/README.md     the handoffs' folder, one file per session, and their next id
  notes/item-format.md        the shape of a tracker item and its id
  notes/handoff-format.md     the shape of a handoff
  dot-claude/                 installed as .claude/
    ground-truth.conf         what the ground truth looks at: the project's repos, and how their code is checked
    settings.json             the hook that rebuilds the board after each change
    skills/session-start/{SKILL.md,ground-truth.sh,items.sh,claim.sh,gate.sh,board.sh,lib.sh}
    skills/handoff/SKILL.md
    skills/board/SKILL.md
    skills/autonomy/{SKILL.md,autonomy.sh}
    skills/checks/SKILL.md
    skills/trim/SKILL.md
workspace/gitignore           whitelist .gitignore for a multi-repo workspace's docs repo
bin/adopt.sh                  installs the template, never overwrites, lists what is left to FILL
example/                      a filled-in project: the files behind the brief in "What it looks like"
test/run.sh                   tests adopt.sh, the skills' scripts and the table "What Claude does alone"; CI runs it
                              on Linux, macOS and Windows
test/fixtures/broken/         trackers, lessons and a handoff that break their format in every way items.sh reports
test/fixtures/two-sessions/   two sessions' handoffs that pass the check
memory/README.md              how the memory layer is used
PRINCIPLES.md                 the why
```

`CLAUDE.template.md` and `dot-claude/` get their real names only in a project. Under those names, Claude Code
would load them (and the example's `CLAUDE.example.md`) as instructions and skills in a session working on this
repo.

The skills, their scripts and `notes/item-format.md` hold no project data, so a project can upgrade them from
here. Project data lives in `ground-truth.conf`, `CLAUDE.md`, the trackers and the other notes. Nothing here
depends on a machine, a session or an owner.

## License

MIT, see [`LICENSE`](LICENSE).
