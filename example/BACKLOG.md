# Pantry — Backlog (open work)

The queue of **open** work. Owner decisions and deliberate non-fixes are not here: they are in `questions.md`. What
is in flight today (running jobs, the task of the day) is in the handoffs, `notes/handoff/`.

Its rules (only approved items are built, a landed item is deleted, how it is claimed and cited) are in
`notes/item-format.md`, "The rules of the two trackers".

Order set by the owner: what the 2026-10-15 release needs first (B-7 Unit conversion on import), then `api`, then
`web`.

next id: B-17 (last given to claude@pantry)

---

## api

### 🔲 B-7 Unit conversion on import
claimed: claude@pantry-12 on fix/unit-conversion at laptop
Recipes imported from US sites keep cups and ounces, so the shopping list cannot add them up. PR #41, branch
`fix/unit-conversion`.
Done when: an imported recipe stores grams and millilitres only, and #41 is merged.

### 🔲 B-15 Import rejects recipes with no yield
claimed: claude@api-yield-3 on fix/yield-default at laptop
About 4% of imports fail with `yield is required` (the backfill's log).
Done when: a missing yield defaults to 1 serving and the recipe page flags it.

### 🔲 B-16 Backfill ingredients on staging
Recipes imported before the ingredient index (#39) have no ingredients in it: 340 batches, run as the unit
`pantry-backfill` so the ground truth lists it.
Done when: the unit exited 0, and 20 recipes picked at random show their ingredients on staging.

### ⏸️ B-13 Search on Postgres full-text instead of LIKE
waits: the ingredient index size, once the backfill's 340 batches are in
Search matches with `LIKE`; whether full-text is needed depends on the index size on the full set.
Done when: a search answers in under 100 ms on the full set.

## web

### 🔲 B-12 Shopping list works offline
claimed: claude@pantry-12 on feat/offline-list at laptop
Edits made in a shop with no signal are lost. Worktree `web-offline/`.
Done when: an edit made in airplane mode syncs on reconnect, conflicts resolved last-write-wins per item, tested on
a phone.

### 🔲 ⚠ B-14 Show which ingredient matched a search
repos: api → web
A result does not say why it matched. The API returns `matched_ingredient` on each hit, then the results page
highlights it.
Done when: searching "basil" highlights basil in every result.
