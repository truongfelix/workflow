# <!-- FILL: project name --> — Backlog (open work)

The queue of **open** work. Owner decisions and deliberate non-fixes are not here: they are in `questions.md`. What
is in flight today (running jobs, the task of the day) is in the handoffs, `notes/handoff/`.

**Rules**
- **Only approved items are built.** A new idea, an extra or a bug met on the way becomes an item here first, and is
  built once the owner approved it: with a yes when it is added or when its work starts (`CLAUDE.md`, the rows "Add
  an item to the backlog" and "Start the day's task after the brief"). So nothing is built that this file does not
  show, and it stays the whole list of the work.
- **No finished work.** When an item lands, delete it; git has the history. A done entry rots while still reading
  as authoritative. The commit that deletes it says where it landed (a commit hash, a PR number), so the board leads
  from the closed item to the work. Measured results go to `notes/`.
- **Sections are cut along repos or file trees**, so one session (or one worktree) can take a section while another
  session takes another, and their work merges cleanly.
- **Every item has one shape** (`notes/item-format.md`): `### <state> <id> <title>`, its fields, a body, and
  `Done when:`. ⚠ marks a cross-repo item, which runs alone in the order of its `repos:` line, producer first; never
  inside one section's batch. ⏸️ marks an item waiting for the trigger in its `waits:` line.
- **A new item takes the id in `next id`**; the same edit raises that line and names who took it.
- **An item is claimed when an agent starts working on it**: `claim.sh` adds its `claimed:` line and pushes it
  (`notes/item-format.md`, Claims), so no other session takes it. An item another session claimed is theirs.
- An item is what is wrong or missing, a pointer to the detail, and when it is **done**. How it was found goes in
  the commit message.
- **Cite an item by its id** (with its title for the reader), never by a position: positions move, ids do not.
- **Re-confirm before acting**: an item can be done already (`/session-start` step 3). A deleted item can also come
  back through a long-lived branch that carried an old copy of this file: `git log -S'<id> ' -- BACKLOG.md`.

<!-- FILL: the priority order between sections, if the owner set one. -->

next id: B-1 (none given yet)

---

## <!-- FILL: first repo or file tree -->

<!-- FILL: the items, each in the shape of notes/item-format.md -->

## <!-- FILL: second repo or file tree -->
