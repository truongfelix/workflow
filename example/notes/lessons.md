# Lessons

Lessons learned in this project that every session needs: `CLAUDE.md` imports this file, so it loads at every
session start and travels with the repo to every machine and cloud session. `/handoff` adds a lesson here when it
distils the old handoff (step 2) and saves memories (step 5); a narrow fact goes into a memory instead. Keep it
short: merge rather than append, and drop what no longer holds.

## Git
- Stacked PRs target `main`, never another PR's branch: merging with "delete branch" closes every PR stacked on it
  (#40, 2026-10-08).

## Tests
- `uv run pytest -q` prints "failed" inside passing test names (`test_import_failed_rows`): read the exit code,
  never grep the text.

## Long runs
- Start long jobs from the workspace root with `systemd-run --user --same-dir --unit pantry-<name>`, so the ground
  truth lists them. A job started with `nohup` is invisible to it.
