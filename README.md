# workflow — Claude Code sessions that pick up where the last one left off

[![test](https://github.com/truongfelix/workflow/actions/workflows/test.yml/badge.svg)](https://github.com/truongfelix/workflow/actions/workflows/test.yml)

Every Claude Code session starts with an empty context. The usual fix is a notes file that the agent updates at the
end of the day and reads the next morning. It works until the notes are wrong: a branch marked "pushed" that never
reached the remote, a job "still running" that died at 1 a.m., a to-do that shipped last week. The next session
believes them and builds on them.

This template keeps a project going across sessions, machines and weeks with three skills and a script:

- **`/session-start`** runs `ground-truth.sh`, which reads the facts from git, GitHub and the machine: every repo and
  worktree against its remote, open PRs and their CI, background jobs. Then it reads the last handoff, reports
  where the two disagree, proposes the day's task, and waits for you (or starts it, if you told it to).
- **`/handoff`** runs the same script, rewrites the handoff from it, updates the trackers (open work, your pending
  decisions, lessons learned), and commits.
- **`/board`** opens the trackers, lessons and handoffs as one page, with filters and each item's history. A hook
  rebuilds it after each change, and an open tab updates itself. Where no browser can show it (a cloud session,
  SSH), it prints the open items instead.

The handoff is a claim; the script is the fact. Both skills run the same script, so the session that writes the
note and the session that reads it look at the same picture.

## What it looks like

Monday morning, `/session-start` on a project whose last session ended on Friday:

```text
Since last session (Fri 9 Oct, 18:40)
- ⚠ The ingredient backfill failed on Saturday at 01:12, at batch 212 of 340: "No space left on
  device" on /var/lib/pantry. The handoff expected it to finish around 03:00.
- ⚠ web: feat/offline-list has 2 commits that were never pushed (Fri 19:05 and 19:20, after the
  handoff). The handoff calls the branch pushed and the edit queue "not started": those commits
  are the queue and its replay.
- ⚠ web: spike/pwa-cache exists only on this laptop, and no note mentions it.
- api: PR #41 (unit conversion) is CI RED: test_round_to_5g, a pinch of salt rounds to 0 g.
- #39 (search by ingredient) is merged, as the handoff says.

Today
1. [api] Fix the rounding in #41 so small quantities keep at least 1 g. Thursday's release needs
   it. Done when CI is green and you have merged it.
2. [ops] Free space on /var/lib/pantry and resume the backfill from batch 212. Done when the
   unit exits 0 and 20 recipes check out on staging.
3. [web] Push the 2 commits, then finish "Shopping list works offline": conflict handling and
   the phone test are left.

Waiting for you
- "Metric only on the shopping list?" I recommend metric only: it matches #41, and a switch can
  come later.
- spike/pwa-cache: push it, keep it local on purpose, or delete it?

I'd start with 1: it is small, and the release waits on it. Which one?
```

A session that trusted Friday's note alone would have asked for a red PR to be merged, reported the backfill as
done, and rewritten code that already existed. The whole scenario, with every file behind this brief and the
script's output, is in [`example/`](example/).

## Quick start

You need bash and git. Optional: the GitHub CLI `gh` (open PRs and CI) and systemd (background jobs, Linux only).
Runs on Linux, macOS and Windows: in Git Bash, which Claude Code uses on Windows, or in WSL. CI tests all three.

```bash
git clone https://github.com/truongfelix/workflow.git
workflow/bin/adopt.sh ~/code/my-project     # copies the template; never overwrites a file
```

Then open Claude Code in your project and ask:

> Set up the workflow: follow "Adopt in a new project" in /path/to/workflow/README.md

Claude first asks what it may do without asking you (commit, push, open a PR, merge, …: a preset, then any change),
then fills in the blanks (what the project is, its repos, its rules), runs the ground truth until it comes back
clean, and runs `/handoff` once to write the first handoff. You change any of those answers whenever you want: "from
now on, push the docs without asking". From then on: `/session-start` when you sit down, `/handoff` before you stop.

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
| `.claude/ground-truth.conf` | the repos the script checks, and branches that must never be pushed |
| `.claude/skills/` | `/session-start` (with `ground-truth.sh`; `items.sh`, the parser and format check of the trackers, lessons and handoffs; `board.sh`, the trackers, lessons and handoffs as one page, with the commits and PRs behind each item), `/handoff` and `/board` |
| `.claude/settings.json` | the hook that rebuilds the board after each change to the trackers or the git history |

It fits a single repo, or a workspace folder holding several repos (a fork, an app, a backend) with a docs repo of
its own at the root. How Claude Code's machine-local memory fits next to these files: [`memory/README.md`](memory/README.md).

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
- **You choose what Claude does alone.** One table: for each step (the day's task, commit, push, PR, merge, release,
  messages), ask you first, or do it and tell you. Set at setup, changed whenever you say so.

## Adopt in a new project

The detailed steps, written for the Claude session doing the setup (you can follow them by hand too). Read
`PRINCIPLES.md` first; then:

1. **Get the workflow:** a clone of this repo on the machine.
2. **Choose the shape.**
   - *One repo:* the project root is the repo; the trackers are committed with the code.
   - *Multi-repo workspace:* a folder holding several code repos (forks, an app, a backend). The root becomes a
     docs-only repo of its own (CLAUDE.md, trackers, `notes/`, `.claude/`), with a whitelist `.gitignore` so the
     nested repos, data and keys stay out, and a PRIVATE remote.
3. **Install:** `bin/adopt.sh <project-root>` (add `--workspace` for the second shape). It copies only missing files,
   prints the ones it skipped with a diff command, and lists the FILL markers.
4. **Fill**, in this order:
   - `CLAUDE.md`, **What Claude does alone**, first: the steps below follow it. Ask the owner for a preset
     (Careful, Balanced or Hands-off, as its last bullet defines them) as a multiple-choice question. Then show the
     table with that preset and ask which rows to change; the owner names them, or none. Set the rows, then
     delete its FILL comment.
   - `.claude/ground-truth.conf`: one line per repo (the remote that counts as "pushed" is YOURS in a fork, not
     upstream), and KEEP_LOCAL for branches that must never be pushed.
   - Run `bash .claude/skills/session-start/ground-truth.sh` until it ends with `GROUND TRUTH: complete`.
   - The rest of `CLAUDE.md`: what the project is, repos and layout, commands, and the project's rules. A rule is
     what Claude must always or never do in this project ("greet.sh stays plain bash", "never touch `migrations/`",
     "a change is done when `make test` passes"). Ask the owner with such examples, and say that it is not the table
     above and that none is fine: rules come as the project meets them. Move any existing to-do list out of
     `CLAUDE.md` into `BACKLOG.md`.
   - `BACKLOG.md`: one section per repo or file tree, filled from what the project already tracks (issues, notes, an
     old TODO). Each item in the shape of `notes/item-format.md`: an id from `next id`, what is wrong or missing, a
     pointer, `Done when:`.
   - `questions.md`: decisions the owner still has to make, and rulings already made that a newcomer would undo,
     in the same shape. Then `bash .claude/skills/session-start/items.sh check` until it exits 0.
   - The skills' FILL item (project-specific checks, what is expected and not news).
   - `.claude/settings.json`, when the project had one (`adopt.sh` lists it as skipped): add the template's
     `PostToolUse` hook to it, which rebuilds the board after each change.
5. **Workspace shape only:** `git init` at the root; check `git status --ignored` and the staged list before the
   first commit; scan for secrets (`gitleaks`); never track a datadir, a key or a binary. Create the private remote
   and push as the table allows.
6. **Close the loop:** run `/handoff` once, so the first handoff (`notes/handoff/<session>.md`) is written from the
   ground truth. The next
   session starts with `/session-start`.

Existing project with its own session docs: adopt anyway (nothing is overwritten), then merge by hand, keeping the
project's content and the template's structure.

## Upgrade a project from here

`bin/adopt.sh <project-root>` again lists every skipped file with its `diff -u` command against the current
template. Merge the generic parts; keep the project's FILL answers. `.claude/workflow-version` records which commit
the project last took.

From 1.x: the trackers' items and the lessons moved from bullets cited by title to one shape with ids, and the one
`notes/handoff.md` with its archive became one handoff per session, with git as the archive
(`notes/handoff-format.md`, "Moving a project to it"). `adopt.sh` installs the new
`notes/item-format.md`, and its last section, "Moving a project to it", is the conversion, done once;
`.claude/skills/session-start/items.sh check` lists what is left. In `CLAUDE.md`, the "outward actions" rule and the
handoff rule became the table "What Claude does alone": copy it from the template, every row "ask first", then set
what the old handoff rule allowed to "do, then tell" (the docs: "Commit the docs" and "Push the docs"; everything:
"Commit code" and "Push a work branch" too), and ask the owner about the other rows.

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
    ground-truth.conf         what the ground truth looks at: the project's repos
    settings.json             the hook that rebuilds the board after each change
    skills/session-start/{SKILL.md,ground-truth.sh,items.sh,board.sh}
    skills/handoff/SKILL.md
    skills/board/SKILL.md
workspace/gitignore           whitelist .gitignore for a multi-repo workspace's docs repo
bin/adopt.sh                  installs the template, never overwrites, lists what is left to FILL
example/                      a filled-in project, and the brief /session-start gave on it
test/run.sh                   tests adopt.sh, ground-truth.sh, items.sh, board.sh and the table "What Claude does alone"; CI runs it on Linux, macOS and Windows
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
