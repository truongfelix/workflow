# Pantry — open questions and deliberate non-fixes

| file | holds |
|---|---|
| `BACKLOG.md` | the open-work queue |
| this file | **§1** questions only the owner can decide · **§2** rulings and deliberate non-fixes, so they are not "rediscovered" as bugs or "rescued" by a push |

Status: 💬 needs the owner's decision · 🟢 decided (ruling in force) · ⏸️ deferred, with its trigger in `waits:`

next id: Q-4 (last given to claude@pantry)

Every entry has one shape (`notes/item-format.md`): `### <state> <id> <title>`, its fields, then the question or
the ruling, its reason, and a pointer to the detail. Name things by what the owner sees (a screen's title, a
command), not by code names. A question carries the options and a recommendation. When the owner rules, the entry
moves to §2 as 🟢 with their words and a `ruled:` date, or it is deleted if nothing is left to guard. Cite an entry
by its **id**, with its title for the reader.

---

# 1. Open decisions 💬

### 💬 Q-3 Metric only on the shopping list?
repos: web
blocks: the totals row of the shopping list
The shopping list adds quantities up, so once #41 lands it shows grams and millilitres. Cups and spoons would need
a display switch.
- **A. Metric only for now** (recommended): one code path, it matches #41, and a switch can come later.
- **B. A "Units" switch in Settings**: about two days in `web/`, and every total is tested in both units.

# 2. Rulings and deliberate non-fixes — do not "fix" these by reflex

### 🟢 Q-2 The API stores metric only
repos: api, web
ruled: 2026-10-02
Owner: "Store one unit. Showing cups is a display problem." Don't add unit columns to the recipe
tables; converting for display belongs in `web/`.

### 🟢 Q-1 `local/family-recipes` is never pushed
repos: api
ruled: 2026-09-28
Owner: "Those are my grandmother's recipes, they stay on this laptop." The branch in `api/` holds seed
data for local testing. It is in KEEP_LOCAL, so the ground truth lists it as "local only BY RULE".
