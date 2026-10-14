# Upgrade a project from here

The upgrade, step by step, written for the Claude session doing it (you can follow it by hand too). The owner starts
it with one sentence in a Claude Code session opened in the project: *Upgrade the workflow: follow
/path/to/workflow/UPGRADE.md*.

`bin/adopt.sh <project-root>` again lists every skipped file with its `diff -u` command against the current
template. Merge the generic parts; keep the project's FILL answers. The skills' scripts (`.claude/skills/*/*.sh`)
hold no answer of the project: take the template's, all of them at once (they share `session-start/lib.sh`); a
`SKILL.md` keeps the project's answer to its FILL item. `.claude/workflow-version` names the release `adopt.sh` last
ran from, as the releases page names it: `v1.0.0`, or `v1.0.0-3-gabc1234` three commits after it. An upgrade changes
only the docs (`CLAUDE.md`, the trackers, `notes/`, `.claude/`): commit and push it as the rows "Commit the docs"
and "Push the docs" say, its paths staged by name.

From 1.x, in this order:
1. **The new files:** `adopt.sh` installs what 1.x did not have: the skills `/board`, `/autonomy`, `/checks` and
   `/trim`, the scripts beside `ground-truth.sh`, `notes/item-format.md`, `notes/handoff-format.md`, and
   `.claude/settings.json`, whose hook rebuilds the board after each change (a project with a `settings.json` of its
   own: add the template's `PostToolUse` hook to it). The files 1.x had are skipped and differ: the steps below.
2. **`CLAUDE.md`:** the "outward actions" rule and the handoff rule became the table "What Claude does alone": copy it
   from the template with its bullets, and delete its FILL comment (a preset would undo the rows set here). Every row
   is "ask first", except what the old handoff rule allowed, which becomes "do, then tell":
   - "/handoff asks before committing": no row.
   - "/handoff commits and pushes the docs": "Commit the docs" and "Push the docs".
   - "/handoff commits and pushes everything": those two, "Commit code" and "Push a work branch".

   The old rules settled the commits and the outward actions (pushes, pull requests, merges, releases, messages). Six
   rows are new: start the day's task, add an item to the backlog, claim one, build something that is not an approved
   backlog item, delete a branch or worktree whose work has landed, stop a background job. Ask the owner about those
   six with `/autonomy`, naming them: it asks about those alone, never with a preset. Copy the bullet "A question to
   the owner" from the template's Rules too: `/autonomy`, `/checks` and the setup ask the owner as it says.
3. **`.claude/ground-truth.conf`:** 1.x had `REPOS`, `KEEP_LOCAL` and `UNITS`. Take the template's file and put the
   project's three lines back in it, the docs repo (`.`) first in `REPOS`: it adds when a claim is stale, the sizes
   that call for `/trim`, and how the code is checked. Run `/checks` (the project's own check, GitHub CI, both or
   nothing yet, and the rules kept), then delete the file's two FILL lines. A code repo of `REPOS` gets a pointer
   (`attach.sh`; [`SETUP.md`](SETUP.md), "A session opened in a code repo"):
   `bash .claude/skills/session-start/attach.sh <name>` for each; the ground truth says `NO POINTER` until then.
4. **The trackers:** their items and the lessons moved from bullets cited by title to one shape with ids. The last
   section of `notes/item-format.md`, "Moving a project to it", is the conversion, done once, each tracker's header
   included (1.x's says to cite an item by its title). `.claude/skills/session-start/items.sh check` lists what is
   left. An item's history before its id is found by its title (`git log -S'<title>' -- BACKLOG.md`): the board and
   `items.sh show` start at the conversion.
5. **Commit and push** the upgrade, as above. `items.sh check` still lists the old `notes/handoff.md`: the next step
   moves it.
6. **The handoff:** the one `notes/handoff.md` with its archive became one handoff per session, with git as the
   archive (`notes/handoff-format.md`, "Moving a project to it"). Run `/handoff` once: it moves it, and commits it as
   the table says. Then `items.sh check` exits 0 and the ground truth ends `GROUND TRUTH: complete`.

`/trim` is new: it proposes a plan for the rulings of `questions.md` and the lessons, in a session of its own. The
ground truth flags `questions.md` past `QUESTIONS_TRIM_LINES` and `notes/lessons.md` past `LESSONS_TRIM_LINES` (1000
lines each), and `/session-start` suggests `/trim` on the flag.
