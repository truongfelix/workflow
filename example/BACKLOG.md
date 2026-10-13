# Pantry — Backlog (open work)

The queue of **open** work. Owner decisions and deliberate non-fixes are not here: they are in `questions.md`. What
is in flight today (running jobs, the task of the day) is in the handoffs, `notes/handoff/`.

**Rules**
- **No finished work.** When an item lands, delete it; git has the history. A done entry rots while still reading
  as authoritative. The commit that deletes it says where it landed (a commit hash, a PR number), so the board leads
  from the closed item to the work. Measured results go to `notes/`.
- **Sections are cut along repos or file trees**, so one session (or one worktree) can take a section while another
  session takes another, and their work merges cleanly.
- **Every item has one shape** (`notes/item-format.md`): `### <state> <id> <title>`, its fields, a body, and
  `Done when:`. ⚠ marks a cross-repo item, which runs alone in the order of its `repos:` line, producer first; never
  inside one section's batch. ⏸️ marks an item waiting for the trigger in its `waits:` line.
- **A new item takes the id in `next id`**; the same edit raises that line and names who took it.
- **Claim an item before any work on it**: `claim.sh` pushes its `claimed:` line (`notes/item-format.md`, Claims),
  so no other session takes it. An item another session claimed is theirs.
- An item is what is wrong or missing, a pointer to the detail, and when it is **done**. How it was found goes in
  the commit message.
- **Cite an item by its id** (with its title for the reader), never by a position: positions move, ids do not.
- **Re-confirm before acting**: an item can be done already (`/session-start` step 3). A deleted item can also come
  back through a long-lived branch that carried an old copy of this file: `git log -S'<id> ' -- BACKLOG.md`.

Order set by the owner: what the 2026-10-15 release needs first (B-7 Unit conversion on import), then `api`, then
`web`.

next id: B-17 (last given to claude@pantry)

---

## api

### 🔲 B-7 Unit conversion on import
claimed: claude@pantry on fix/unit-conversion
Recipes imported from US sites keep cups and ounces, so the shopping list cannot add them up. PR #41, branch
`fix/unit-conversion`.
Done when: an imported recipe stores grams and millilitres only, and #41 is merged.

### 🔲 B-15 Import rejects recipes with no yield
claimed: claude@api-yield on fix/yield-default
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
claimed: claude@pantry on feat/offline-list
Edits made in a shop with no signal are lost. Worktree `web-offline/`.
Done when: an edit made in airplane mode syncs on reconnect, conflicts resolved last-write-wins per item, tested on
a phone.

### 🔲 ⚠ B-14 Show which ingredient matched a search
repos: api → web
A result does not say why it matched. The API returns `matched_ingredient` on each hit, then the results page
highlights it.
Done when: searching "basil" highlights basil in every result.
