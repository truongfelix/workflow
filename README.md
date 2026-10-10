# workflow — Claude Code sessions that pick up where the last one left off

[![test](https://github.com/truongfelix/workflow/actions/workflows/test.yml/badge.svg)](https://github.com/truongfelix/workflow/actions/workflows/test.yml)

Every Claude Code session starts with an empty context. The usual fix is a notes file that the agent updates at the
end of the day and reads the next morning. It works until the notes are wrong: a branch marked "pushed" that never
reached the remote, a job "still running" that died at 1 a.m., a to-do that shipped last week. The next session
believes them and builds on them.

This template keeps a project going across sessions, machines and weeks with two skills and a script:

- **`/session-start`** runs `ground-truth.sh`, which reads the facts from git, GitHub and the machine: every repo and
  worktree against its remote, open PRs and their CI, background jobs. Then it reads the last handoff, reports
  where the two disagree, proposes the day's task, and waits for you.
- **`/handoff`** runs the same script, rewrites the handoff from it, updates the trackers (open work, your pending
  decisions, lessons learned), and commits.

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

Claude fills in the blanks (what the project is, its repos, its rules), runs the ground truth until it comes back
clean, and runs `/handoff` once to write the first handoff. From then on: `/session-start` when you sit down,
`/handoff` before you stop.

## What you get

```
session N:   /session-start ──► work ──► /handoff
                   ▲                         │
                   └──── git (trackers) ◄────┘   ← session N+1, any machine or cloud session
```

| file | holds |
|---|---|
| `notes/handoff.md` | today: next tasks, what waits for you, what runs in the background, the last session. Short, rewritten at each handoff |
| `notes/handoff-archive.md` | every earlier handoff, word for word. Searched when needed, never read at start |
| `BACKLOG.md` | open work only, one section per repo. A finished item is deleted, not ticked: git keeps the history |
| `questions.md` | decisions only you can make, each with options and a recommendation; past rulings, so no session "fixes" them |
| `notes/lessons.md` | what the project learned the hard way, loaded into every session |
| `CLAUDE.md` | what the project is, its rules and commands. No to-dos, no history |
| `.claude/ground-truth.conf` | the repos the script checks, and branches that must never be pushed |
| `.claude/skills/` | `/session-start` (with `ground-truth.sh`) and `/handoff` |

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
- **Propose, then wait.** The session recommends; you pick the day's work and approve each push, PR or merge.

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
   - `.claude/ground-truth.conf`: one line per repo (the remote that counts as "pushed" is YOURS in a fork, not
     upstream), and KEEP_LOCAL for branches that must never be pushed.
   - Run `bash .claude/skills/session-start/ground-truth.sh` until it ends with `GROUND TRUTH: complete`.
   - `CLAUDE.md`: what the project is, the rules, the **handoff rule** (may `/handoff` commit and push without
     asking?), repos and layout, commands. Move any existing to-do list out of it into `BACKLOG.md`.
   - `BACKLOG.md`: one section per repo or file tree, filled from what the project already tracks (issues, notes, an
     old TODO). Each item: what is wrong or missing, a pointer, when it is done.
   - `questions.md`: decisions the owner still has to make, and rulings already made that a newcomer would undo.
   - The skills' FILL item (project-specific checks, what is expected and not news).
5. **Workspace shape only:** `git init` at the root; check `git status --ignored` and the staged list before the
   first commit; scan for secrets (`gitleaks`); never track a datadir, a key or a binary. Create the private remote
   and push only with the owner's OK.
6. **Close the loop:** run `/handoff` once, so the first `notes/handoff.md` is written from the ground truth. The next
   session starts with `/session-start`.

Existing project with its own session docs: adopt anyway (nothing is overwritten), then merge by hand, keeping the
project's content and the template's structure.

## Upgrade a project from here

`bin/adopt.sh <project-root>` again lists every skipped file with its `diff -u` command against the current
template. Merge the generic parts; keep the project's FILL answers. `.claude/workflow-version` records which commit
the project last took.

## Improve the workflow

When a project's session improves a generic piece (a skill step, a ground-truth check, a principle learned the hard
way), port the generic part back here in its own commit, with the reason. Project-specific content never comes back
here, and neither do lessons: a lesson stays in the `notes/lessons.md` of the project that learned it.

## Layout of this repo

```
template/                     copied into a project's root by bin/adopt.sh
  CLAUDE.md                   skeleton with FILL markers
  BACKLOG.md  questions.md  notes/handoff.md  notes/handoff-archive.md  notes/lessons.md
  .claude/ground-truth.conf   what the ground truth looks at: the project's repos
  .claude/skills/session-start/{SKILL.md,ground-truth.sh}
  .claude/skills/handoff/SKILL.md
workspace/gitignore           whitelist .gitignore for a multi-repo workspace's docs repo
bin/adopt.sh                  installs the template, never overwrites, lists what is left to FILL
example/                      a filled-in project, and the brief /session-start gave on it
test/run.sh                   tests adopt.sh and ground-truth.sh; CI runs it on Linux, macOS and Windows
memory/README.md              how the memory layer is used
PRINCIPLES.md                 the why
```

The skills and `ground-truth.sh` hold no project data, so a project can upgrade them from here. Project data lives
in `ground-truth.conf`, `CLAUDE.md`, the trackers and the notes. Nothing here depends on a machine, a session or an
owner.

## License

MIT, see [`LICENSE`](LICENSE).
