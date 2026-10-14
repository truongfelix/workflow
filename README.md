# workflow — Claude Code sessions that pick up where the last one left off

[![test](https://github.com/truongfelix/workflow/actions/workflows/test.yml/badge.svg)](https://github.com/truongfelix/workflow/actions/workflows/test.yml)

Every Claude Code session starts with an empty context. The usual fix is a notes file the agent updates at night and
reads in the morning. It works until the notes are wrong: a branch "pushed" that never reached the remote, a job
"still running" that died at 1 a.m., a to-do that shipped last week. The next session believes them.

This template checks the notes against the facts at every start. The handoff is a claim; the script is the fact.

- **`/session-start`** reads git, GitHub and the machine (`ground-truth.sh`): each repo and branch against its remote,
  open PRs and their CI, the items other sessions claimed, background jobs. Then the last handoff: it reports where
  they disagree, proposes the day's task, and waits for you.
- **`/handoff`** runs the same script and records where things stand, for the next session on any machine.
- **`/board`** shows the backlog, your decisions, the lessons and the handoffs as one page that updates itself.
- **`/autonomy`** sets what Claude does without asking you: commit, push, open or merge a PR, release, …
- **`/checks`** sets how the code is checked before a merge (its tests, GitHub CI, both) and the rules you keep.
- **`/trim`** proposes what to keep, shorten or delete once your rulings and lessons grow.

## What it looks like

Monday morning, `/session-start` on a project whose last session ended on Friday:

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

Today
1. B-7 Unit conversion on import [api]: fix the rounding in #41 so small quantities keep at
   least 1 g. Thursday's release needs it. Done when CI is green and you have merged it.
2. B-16 Backfill ingredients on staging [ops]: free space on /var/lib/pantry and resume from
   batch 212. Done when the unit exits 0 and 20 recipes check out on staging.

Waiting for you
- Q-3 Metric only on the shopping list? I recommend metric only: it matches #41.

I'd start with 1: it is small, and the release waits on it. Which one?
```

A session that trusted Friday's note alone would have asked for a red PR to be merged, reported the backfill as
done, and rewritten code that already existed. Every file behind this brief is in [`example/`](example/).

## Quick start

You need bash, git and a remote for your project; optionally the GitHub CLI `gh` (PRs and CI) and systemd
(background jobs). Linux, macOS, and Windows in Git Bash or WSL.

```bash
git clone https://github.com/truongfelix/workflow.git ~/workflow
~/workflow/bin/adopt.sh ~/code/my-project     # copies the template; overwrites nothing but its version file
```

Then open Claude Code in your project and ask:

> Set up the workflow: follow ~/workflow/SETUP.md

Claude follows the copy you cloned, the same version as its scripts. To read the guide first:
[`SETUP.md` on GitHub](https://github.com/truongfelix/workflow/blob/main/SETUP.md).

Claude asks for the git remote, then where its notes and to-do lists live (with the code, or in a repo of their own),
what it may do without asking you, and how the code is checked; it fills in the rest, commits the setup, runs your
check once on it, and runs `/handoff` once to write the first handoff. From then on: `/session-start` when you sit
down, `/handoff` before you stop. A project on 1.x upgrades the same way, *Upgrade the workflow: follow
~/workflow/UPGRADE.md* ([`UPGRADE.md` on GitHub](https://github.com/truongfelix/workflow/blob/main/UPGRADE.md)).

## What you get

| file | holds |
|---|---|
| `notes/handoff/<session>.md` | where things stand, one file per session; earlier ones are in git |
| `BACKLOG.md` | open work, each item with an id (`B-12`); a finished item is deleted, git keeps it |
| `questions.md` | decisions only you can make, and past rulings so no session "fixes" them (`Q-4`) |
| `notes/lessons.md` | what the project learned the hard way, loaded into every session (`L-3`) |
| `CLAUDE.md` | what the project is, what Claude does without asking you, its rules and commands |
| `.claude/` | the skills and their scripts; `ground-truth.conf`: the repos, and how their code is checked |

One repo or several: the notes live with the code, or in a private repo of their own, and `attach.sh` adds a code
repo later. Claude Code's machine-local memory fits beside these files: [`memory/README.md`](memory/README.md).

## The ideas behind it

[`PRINCIPLES.md`](PRINCIPLES.md) explains why each piece exists; every rule in it comes from something that went
wrong. In short: a note is a claim, checked against git before it is repeated; finished work is deleted, not ticked;
an unreadable result is UNKNOWN, never a pass; only approved items are built; you choose what Claude does alone.

## Improve the workflow

When a project's session improves a generic piece (a skill step, a ground-truth check), port it back here in its own
commit, with the reason. Project content never comes back here, nor do lessons.

## Layout of this repo

```
template/            copied into a project by bin/adopt.sh; CLAUDE.template.md and dot-claude/ become CLAUDE.md
                     and .claude/ there only, so they do not load in a session working on this repo
bin/adopt.sh         installs the template, overwrites nothing but its version file, lists what is left to FILL
SETUP.md             the setup, step by step, for the Claude session doing it; a session opened in a code repo
UPGRADE.md           the upgrade from an earlier release, step by step
workspace/gitignore  the .gitignore of a docs repo when the notes have a repo of their own
example/             a filled-in project: the files behind the brief above
test/run.sh          the tests; CI runs them on Linux, macOS and Windows
test/macos.sh        runs them on Linux as macOS would (bash 3.2.57, Apple's awk), for work with no CI
PRINCIPLES.md        the why
```

## License

MIT, see [`LICENSE`](LICENSE).
