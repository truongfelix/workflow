# Handoff (2026-10-09 18:40 CEST)

Read by /session-start. Open work: `BACKLOG.md`. Decisions and rulings: `questions.md`. Rewritten at each /handoff.

## Next (task of the day, in order)
1. [api] Land PR #41 "Convert recipe units to grams on import": the 2026-10-15 release needs it. CI was still
   running at handoff; if green, ask the owner to merge. Branch `fix/unit-conversion`, checkout `api/`. Done when
   #41 is merged.
2. [ops] Check that the ingredient backfill finished (see Running), then spot-check 20 recipes on staging. Done
   when the unit exited 0 and the 20 recipes show their ingredients.
3. [web] "Shopping list works offline" (BACKLOG): continue on `feat/offline-list` in `web-offline/` (pushed). The
   edit queue is not started: `web/src/list/sync.ts`. Done when the BACKLOG item is.

## Waiting for the user
- questions.md "Metric only on the shopping list?": blocks the totals row of the shopping list.

## Running in the background
| What | Unit / process | Ends | Check | Stop |
|---|---|---|---|---|
| Ingredient backfill, 340 batches into staging | `pantry-backfill.service` (systemd-run --user) | ~Sat 03:00 CEST | `journalctl --user -u pantry-backfill -n 20` | `systemctl --user stop pantry-backfill` |

## Last session (2026-10-09)
- Done: #39 search by ingredient merged; #41 opened (replaces #40, see lessons); backfill started 18:20.
- Unfinished: web: `web-offline/` [feat/offline-list], pushed, IndexedDB cache done, edit queue not started.
- Learned: `npm test` in `web/` runs against the staging API unless `API_URL=http://localhost:8080` is set, so its
  results change with staging data.
