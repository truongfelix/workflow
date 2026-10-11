# Pantry

A self-hosted recipe box and shopping list for one household. The owner decides priorities and anything outward.
This workspace holds two code repos, `api/` (Python, FastAPI, Postgres) and `web/` (TypeScript, React), and this
docs repo at its root. Both code repos are public on GitHub; this docs repo has a private remote. The
`local/family-recipes` branch in `api/` holds real family recipes and is never pushed.

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
- **Handoff rule:** /handoff commits and pushes the docs (handoff, trackers, notes) without asking; code still
  needs an OK.
- Stage the paths you changed (`git add <paths>`), never `git add -A` / `git add .`; read `git diff --cached
  --name-only` before committing. The owner drops working files into the tree.
- No secrets in tracked files. If one is needed, write that it is needed and where it lives, never its value.
- The API stores metric quantities only (questions.md Q-2 The API stores metric only).
- Every schema change ships with an Alembic migration and its downgrade, both run by the gate.

## Repos and layout

| path | what | default branch | remote |
|---|---|---|---|
| `api/` | FastAPI service, Postgres | `main` | `origin` = github.com/example-org/pantry-api |
| `web/` | React app | `main` | `origin` = github.com/example-org/pantry-web |
| `<repo>-<topic>/` | worktrees, next to their repo (`web-offline/`) | | |
| `notes/` | handoff, its archive, lessons | | |

Staging runs on this machine: Postgres on the `/var/lib/pantry` volume (20 GB), the site on http://localhost:8080.

## Commands

- api: `cd api && uv run pytest -q`; gate: `api/bin/gate` (lint, types, tests, migration up and down; exit 0 =
  ready).
- web: `cd web && npm test`; gate: `web/bin/gate`.
- Backfill into staging, from the workspace root: `systemd-run --user --same-dir --unit pantry-backfill
  api/bin/backfill --from <batch>`.
