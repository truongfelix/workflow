# Handoff archive

Every earlier `notes/handoff.md`, newest first, moved here word for word by `/handoff` once its lessons were
promoted and its live items carried forward. Never read at session start: search it (`grep -n`) when the handoff or
a question points here.

# Handoff (2026-10-08 19:10 CEST)

Read by /session-start. Open work: `BACKLOG.md`. Decisions and rulings: `questions.md`. Rewritten at each /handoff.

## Next (task of the day, in order)
1. [api] PR #39 "Search recipes by ingredient": answer the review (an index on `ingredients.name`), then ask the
   owner to merge. Done when #39 is merged.
2. [api] Reopen the unit conversion against `main`: its PR #40 closed when its base branch was deleted. Branch
   `fix/unit-conversion`. Done when a new PR is open with CI running.
3. [ops] Once #39 is merged, start the ingredient backfill on staging (it needs the new index), as a
   `systemd-run --user` unit.

## Waiting for the user
- questions.md "Metric only on the shopping list?"

## Running in the background
| What | Unit / process | Ends | Check | Stop |
|---|---|---|---|---|

## Last session (2026-10-08)
- Done: #38 import recipes from URLs merged; web #17 print layout merged.
- Unfinished: none, every worktree is pushed.
- Learned: merging #38 with "delete branch" closed #40, which was stacked on it. Stacked PRs must target `main`.
