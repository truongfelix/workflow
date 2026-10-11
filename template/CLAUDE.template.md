# <!-- FILL: project name -->

<!-- FILL: one paragraph. What this is, who owns it (the owner decides priorities and anything outward), where the
code lives (one repo, or the repos inside this workspace), what is public and what must stay private. -->

**Sessions:** start with `/session-start`, end with `/handoff` (skills in `.claude/skills/`). Both first run
`.claude/skills/session-start/ground-truth.sh` (repos, worktrees, open PRs + CI, background jobs; configured in
`.claude/ground-truth.conf`): the handoff is a claim, the script is the fact, and a contradiction is reported first.

**Trackers:** open work is in `BACKLOG.md` (a finished item is deleted), questions for the owner and standing rulings
in `questions.md`, today's tasks and what runs in `notes/handoff.md`. This file keeps only state, rules and
how-tos: no to-dos, no decisions waiting, no PR lists or history (git has them). Both trackers as one page, with
filters by repo, state and date: `bash .claude/skills/session-start/board.sh`.

**Lessons** learned in this project, loaded every session: @notes/lessons.md

This setup comes from the workflow repo (`.claude/workflow-version` names the commit). When a
session improves a generic piece (a skill, the ground-truth script), port that part back there.

## Rules

- **Outward actions need the owner's OK:** push, PR, merge, release, comments, messages to anyone. An approval
  covers the action it was given for, not the next one.
- **Handoff rule:** <!-- FILL: one of: "/handoff asks before committing" · "/handoff commits and pushes the docs
  (handoff, trackers, notes) without asking; code still needs an OK" · "/handoff commits and pushes everything,
  wip included" -->
- Stage the paths you changed (`git add <paths>`), never `git add -A` / `git add .`; read `git diff --cached
  --name-only` before committing. The owner drops working files into the tree.
- No secrets in tracked files. If one is needed, write that it is needed and where it lives, never its value.
- <!-- FILL: project rules (architecture, things never to touch, how work is verified). -->

## Repos and layout

<!-- FILL: each repo or top-level directory: what it is, its default branch, its remote, where worktrees go. -->

## Commands

<!-- FILL: install, run, test, and the gate (the script whose exit code says "ready"). If a check must hold, it
belongs in that gate, not in this file: a document is not a gate. -->
