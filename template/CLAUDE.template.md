# <!-- FILL: project name -->

<!-- FILL: one paragraph. What this is, who owns it (the owner decides priorities, and what Claude does alone:
below), where the code lives (one repo, or the repos inside this workspace), what is public and what must stay
private. -->

**Sessions:** start with `/session-start`, end with `/handoff` (skills in `.claude/skills/`). Both first run
`.claude/skills/session-start/ground-truth.sh` (repos, worktrees, open PRs + CI, background jobs; configured in
`.claude/ground-truth.conf`): the handoff is a claim, the script is the fact, and a contradiction is reported first.

**Trackers:** open work is in `BACKLOG.md` (a finished item is deleted), questions for the owner and standing rulings
in `questions.md`, today's tasks and what runs in one handoff per session in `notes/handoff/`. No archive files:
git keeps what is deleted. This file keeps only state, rules and how-tos: no to-dos, no decisions waiting, no PR
lists or history (git has them). The trackers, lessons and handoffs as one page, closed ones included, with filters
by repo, state and date: `/board` (`.claude/skills/session-start/board.sh`); a hook rebuilds it after each change.

**Lessons** learned in this project, loaded every session: @notes/lessons.md

This setup comes from the workflow repo (`.claude/workflow-version` names the release). When a
session improves a generic piece (a skill, the ground-truth script), port that part back there.

## What Claude does alone

The owner's answer for each step where a session could stop and ask. **ask first**: say what you are about to do
and wait for a yes. **do, then tell**: do it, then say so in your next message, or in the handoff. **The docs** are
the handoffs, the trackers, `notes/`, this file and `.claude/`: a push whose new commits hold only docs is "Push the
docs", on any branch, the default one included.

<!-- FILL: ask the owner for a preset (the last bullet below), listing the steps in plain words and naming no file
(README, "Adopt in a new project", step 4), then whether to keep it or change some steps, each step then an option
to pick or not, with its answer; set the rows, then delete this comment. Until then every row is Careful. -->

| Step | Here |
|---|---|
| Start the day's task after the brief | ask first |
| Commit the docs | ask first |
| Push the docs | ask first |
| Add an item to the backlog | ask first |
| Claim an item (commit and push its claim line) | ask first |
| Commit code | ask first |
| Push a work branch | ask first |
| Open a pull request | ask first |
| Merge a pull request, or push code to a default branch | ask first |
| Delete a branch or worktree whose work has landed | ask first |
| Stop a background job this session started | ask first |
| Release: tag, publish | ask first |
| Comment, or message anyone | ask first |

- A row is a standing answer. A yes in the chat covers that one action, not the next one.
- The owner changes a row at any time ("from now on, push the docs without asking"): edit the row here, at once; it
  holds from the next action on.
- An action that fits no row, or a doubt about which row it is: ask first. Ask once for several: `/handoff` puts
  its ask-first steps in one question.
- Presets, for setup or a reset: **Careful** asks first on every row. **Balanced** asks first to start the day's
  task, to open or merge a pull request (or push code to a default branch), to release, and to comment or message;
  it does the rest, then tells. **Hands-off** asks first only to release, and to comment or message.

## Rules

- **Whatever the table says:** never rewrite a branch others may have fetched (a fix is a new commit), never skip a
  hook (`--no-verify`).
- Stage the paths you changed (`git add <paths>`), never `git add -A` / `git add .`; read `git diff --cached
  --name-only` before committing. The owner drops working files into the tree.
- No secrets in tracked files. If one is needed, write that it is needed and where it lives, never its value.
- <!-- FILL: project rules: what Claude must always or never do here (an architecture choice, a file never to touch,
  how a change is verified). None is fine: delete this line, and add rules as the project meets them. -->

## Repos and layout

<!-- FILL: each repo or top-level directory: what it is, its default branch, its remote, where worktrees go. -->

## Commands

<!-- FILL: install, run, test, and the gate (the script whose exit code says "ready"). If a check must hold, it
belongs in that gate, not in this file: a document is not a gate. -->

The gate runs with `bash .claude/skills/session-start/gate.sh run <repo>`, which keeps a receipt of each commit that
passed it. Each repo's gate command and the gate rules this project keeps (a preset: Production, Steady or
Prototype) are in `.claude/ground-truth.conf` (`GATES`, `GATE_RULES`).
