# Lessons

Lessons learned in this project that every session needs: `CLAUDE.md` imports this file, so it loads at every
session start and travels with the repo to every machine and cloud session. `/handoff` adds a lesson here when it
distils the old handoff (step 2) and saves memories (step 5); a narrow fact goes into a memory instead. Keep it
short: merge rather than append, and drop what no longer holds.

Each lesson is an item (`notes/item-format.md`): `### L-<n> <title>`, no state, then the rule and its reason. A new
lesson takes the `next id` below and raises it in the same edit. A merged or dropped lesson is deleted, and the
commit says so (`L-4 merged into L-2`): git keeps it.

next id: L-1 (none given yet)

<!-- One section per area (git, long runs, verification, a tool of this project), one lesson per heading:

## Git

### L-1 Stacked PRs target main
Merging a PR with "delete branch" closes every PR stacked on it: stacked PRs target `main`, never another PR's
branch.
-->
