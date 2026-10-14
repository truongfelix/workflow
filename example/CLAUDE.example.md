# Pantry

A self-hosted recipe box and shopping list for one household. The owner decides priorities, and what Claude does
alone (below). This workspace holds two code repos, `api/` (Python, FastAPI, Postgres) and `web/` (TypeScript,
React), and this docs repo at its root. Both code repos are public on GitHub; this docs repo has a private remote. The
`local/family-recipes` branch in `api/` holds real family recipes and is never pushed.

**Sessions:** start with `/session-start`, end with `/handoff` (skills in `.claude/skills/`). Both first run
`.claude/skills/session-start/ground-truth.sh` (repos, worktrees, open PRs + CI, background jobs; configured in
`.claude/ground-truth.conf`): the handoff is a claim, the script is the fact, and a contradiction is reported first.

**Trackers:** open work is in `BACKLOG.md` (a finished item is deleted), questions for the owner and standing rulings
in `questions.md`, today's tasks and what runs in one handoff per session in `notes/handoff/`. No archive files:
git keeps what is deleted. This file keeps only state, rules and how-tos: no to-dos, no decisions waiting, no PR
lists or history (git has them). The trackers, lessons and handoffs as one page, closed ones included, with filters
by repo, state and date: `/board` (`.claude/skills/session-start/board.sh`); a hook rebuilds it after each change.

**Lessons** learned in this project, loaded every session: @notes/lessons.md

This setup comes from the workflow repo (`.claude/workflow-version` names the release).

## What Claude does alone

The owner's answer for each step where a session could stop and ask. **ask first**: say what you are about to do
and wait for a yes. **do, then tell**: do it, then say so in your next message, or in the handoff. **The docs** are
the handoffs, the trackers, `notes/`, this file and `.claude/`: a push whose new commits hold only docs is "Push the
docs", on any branch, the default one included.

| Step | Here |
|---|---|
| Start the day's task after the brief | ask first |
| Commit the docs | do, then tell |
| Push the docs | do, then tell |
| Add an item to the backlog | ask first |
| Claim an item (commit and push its claim line) | ask first |
| Build something that is not an approved backlog item | ask first |
| Commit code | ask first |
| Push a work branch | ask first |
| Open a pull request | ask first |
| Merge a pull request, or push code to a default branch | ask first |
| Delete a branch or worktree whose work has landed | ask first |
| Stop a background job this session started | ask first |
| Release: tag, publish | ask first |
| Comment, or message anyone | ask first |

- A row is a standing answer. A yes in the chat covers that one action, not the next one.
- **Build something that is not an approved backlog item:** a task the owner names in the chat is approved by that
  request, and becomes a backlog item too, as part of it: the backlog stays the whole list of the work. An extra, an
  idea or a bug met on the way becomes a backlog item first (the row "Add an item to the backlog"), and is built once
  the owner approved it.
- The owner changes a row at any time, in words ("from now on, push the docs without asking") or with `/autonomy`,
  which shows the steps to pick: edit the row here, at once; it holds from the next action on.
- An action that fits no row, or a doubt about which row it is: ask first. Ask once for several: `/handoff` puts
  its ask-first steps in one question.
- Presets, for setup or a reset: **Careful** asks first on every row. **Balanced** asks first to start the day's
  task, to build something that is not an approved backlog item, to open or merge a pull request (or push code to a
  default branch), to release, and to comment or message; it does the rest, then tells. **Hands-off** asks first only
  to build something that is not an approved backlog item, to release, and to comment or message.

## Rules

- **Whatever the table says:** never rewrite a branch others may have fetched (a fix is a new commit), never skip a
  hook (`--no-verify`).
- Stage the paths you changed (`git add <paths>`), never `git add -A` / `git add .`; read `git diff --cached
  --name-only` before committing. The owner drops working files into the tree.
- No secrets in tracked files. If one is needed, write that it is needed and where it lives, never its value.
- **A question to the owner** is in plain words: no file, table or setting name (a command the owner runs is named:
  it is what they see), and each choice says what it does.
  Free text is asked in the chat. A question where several can be picked has "None of these": with nothing picked, it
  returns no answer at all, which reads as a skip. A question that fails, or comes back unanswered, is asked again in
  the chat; never answer for the owner.
- The API stores metric quantities only (questions.md Q-2 The API stores metric only).
- Every schema change ships with an Alembic migration and its downgrade, both run by the gate.

## Repos and layout

| path | what | default branch | remote |
|---|---|---|---|
| `api/` | FastAPI service, Postgres | `main` | `origin` = github.com/example-org/pantry-api |
| `web/` | React app | `main` | `origin` = github.com/example-org/pantry-web |
| `<repo>-<topic>/` | worktrees, next to their repo (`web-offline/`) | | |
| `notes/` | the handoffs (one per session), lessons | | |

Staging runs on this machine: Postgres on the `/var/lib/pantry` volume (20 GB), the site on http://localhost:8080.

## Commands

- api: `cd api && uv run pytest -q`; gate: `api/bin/gate` (lint, types, tests, migration up and down; exit 0 =
  ready).
- web: `cd web && npm test`; gate: `web/bin/gate`.
- Checked before a merge by both gates and GitHub CI, with the rules Production (`/checks`). A gate runs with
  `bash .claude/skills/session-start/gate.sh run api` (or `web`), which keeps a receipt of each commit that passed it.
- Backfill into staging, from the workspace root: `systemd-run --user --same-dir --unit pantry-backfill
  api/bin/backfill --from <batch>`.
