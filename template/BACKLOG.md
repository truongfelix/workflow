# <!-- FILL: project name --> — Backlog (open work)

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

<!-- FILL: the priority order between sections, if the owner set one. -->

---

## <!-- FILL: first repo or file tree -->

- 🔲 **<title>**: <what is wrong or missing>. <pointer: file, note, issue>. Done when: <observable result>.

## <!-- FILL: second repo or file tree -->
