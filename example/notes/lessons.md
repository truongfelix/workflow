# Lessons

Lessons learned in this project that every session needs: `CLAUDE.md` imports this file, so it loads at every
session start and travels with the repo to every machine and cloud session. `/handoff` adds a lesson here when it
distils the old handoff (step 2) and saves memories (step 5); a narrow fact goes into a memory instead. Keep it
short: merge rather than append, and drop what no longer holds.

Each lesson is an item (`notes/item-format.md`): `### L-<n> <title>`, no state, then the rule and its reason. A new
lesson takes the `next id` below and raises it in the same edit. A merged or dropped lesson is deleted, and the
commit says so (`L-4 merged into L-2`): git keeps it.

next id: L-4 (last given to claude@pantry)

## Git

### L-3 Stacked PRs target main
Stacked PRs target `main`, never another PR's branch: merging with "delete branch" closes every PR stacked on it
(#40, 2026-10-08).

## Tests

### L-1 Read pytest's exit code, never its output
`uv run pytest -q` prints "failed" inside passing test names (`test_import_failed_rows`): read the exit code, never
grep the text.

## Long runs

### L-2 Start long jobs with systemd-run
Start long jobs from the workspace root with `systemd-run --user --same-dir --unit pantry-<name>`, so the ground
truth lists them. A job started with `nohup` is invisible to it.
