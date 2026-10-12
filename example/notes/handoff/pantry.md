# H-9 2026-10-09 18:40 CEST · claude@pantry
continues: H-8

## Next
1. B-7 Unit conversion on import [api]: the 2026-10-15 release needs it. PR #41, branch `fix/unit-conversion`,
   checkout `api/`: CI was still running at handoff; if green, ask the owner to merge. Done when #41 is merged.
2. B-16 Backfill ingredients on staging [api]: check that the unit finished (see Running), then spot-check 20
   recipes on staging. Done when the unit exited 0 and the 20 recipes show their ingredients.
3. B-12 Shopping list works offline [web]: continue on `feat/offline-list` in `web-offline/` (pushed). The edit
   queue is not started: `web/src/list/sync.ts`. Done when B-12 is.

## Waiting for the user
- Q-3 Metric only on the shopping list?: blocks the totals row of the shopping list.

## Running
| What | Unit / process | Ends | Check | Stop |
|---|---|---|---|---|
| B-16: ingredient backfill, 340 batches into staging | `pantry-backfill.service` (systemd-run --user) | ~Sat 03:00 CEST | `journalctl --user -u pantry-backfill -n 20` | `systemctl --user stop pantry-backfill` |

## Unfinished
- web: `web-offline/` [feat/offline-list], pushed, IndexedDB cache done, edit queue not started.

## Done
- B-11 Search recipes by ingredient: #39 merged.
- B-7 Unit conversion on import: #41 opened, replacing #40 (L-3 Stacked PRs target main).
- B-16 Backfill ingredients on staging: started at 18:20.

## Learned
- L-3 Stacked PRs target main: new, from H-8's "Learned".
- `npm test` in `web/` runs against the staging API unless `API_URL=http://localhost:8080` is set, so its results
  change with staging data.
