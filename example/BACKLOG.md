# Pantry — Backlog (open work)

The queue of **open** work. Owner decisions and deliberate non-fixes are not here: they are in `questions.md`. What
is in flight today (running jobs, the task of the day) is in `notes/handoff.md`.

**Rules**
- **No finished work.** When an item lands, delete it; git has the history. A done entry rots while still reading
  as authoritative. Measured results go to `notes/`.
- **Sections are cut along repos or file trees**, so one session (or one worktree) can take a section while another
  session takes another, and their work merges cleanly.
- **⚠ cross-repo** marks an item that needs more than one section's tree. It runs alone, in order (producer first,
  then each consumer); never inside one section's batch.
- ⏸️ marks an item that waits for a trigger (a date, a measurement, the user). The trigger is named in the item.
- An item is what is wrong or missing, a pointer to the detail, and when it is **done**. How it was found goes in
  the commit message.
- Cite an item by its **title**, never by a number: numbers move.
- **Re-confirm before acting**: an item can be done already (`/session-start` step 3). A deleted item can also come
  back through a long-lived branch that carried an old copy of this file: `git log -S'<phrase>' -- BACKLOG.md`.

Order set by the owner: what the 2026-10-15 release needs first (Unit conversion on import), then `api`, then `web`.

---

## api

- 🔲 **Unit conversion on import**: recipes imported from US sites keep cups and ounces, so the shopping list cannot
  add them up. PR #41, branch `fix/unit-conversion`. Done when: an imported recipe stores grams and millilitres
  only, and #41 is merged.
- 🔲 **Import rejects recipes with no yield**: about 4% of imports fail with `yield is required` (the backfill's
  log). Done when: a missing yield defaults to 1 serving and the recipe page flags it.
- ⏸️ **Search on Postgres full-text instead of LIKE**: waits for the backfill (trigger: the ingredient index size
  once all 340 batches are in). Done when: a search answers in under 100 ms on the full set.

## web

- 🔲 **Shopping list works offline**: edits made in a shop with no signal are lost. Branch `feat/offline-list`,
  worktree `web-offline/`. Done when: an edit made in airplane mode syncs on reconnect, conflicts resolved
  last-write-wins per item, tested on a phone.
- 🔲 ⚠ **Show which ingredient matched a search** (cross-repo, `api` first): the API returns `matched_ingredient` on
  each hit, then the results page highlights it. Done when: searching "basil" highlights basil in every result.
