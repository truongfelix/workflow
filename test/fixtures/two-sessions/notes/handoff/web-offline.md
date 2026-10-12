# H-13 2026-10-12 18:40 CEST · claude@web-offline
continues: H-11

## Next
1. B-2 Shopping list works offline: the edit queue replays; conflicts are left. Done when B-2 is.

## Waiting for the user
None.

## Running
| What | Unit / process | Ends | Check | Stop |
|---|---|---|---|---|
| Phone test build | `web-offline-build` | 19:30 | `journalctl --user -u web-offline-build -n 20` | `systemctl --user stop web-offline-build` |

## Unfinished
- web: `web-offline/` on `feat/B-2-offline-list`, 1 commit LOCAL ONLY: the conflict handler, half written.

## Done
- B-2 Shopping list works offline: the edit queue, pushed.

## Learned
- The service worker caches `/api/list` for a day: clear it before a phone test.
