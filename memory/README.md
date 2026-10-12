# Memory — how sessions remember across conversations

Memory is split two ways: by **time** (what is live, what is past, what was learned) and by **reach** (who needs it).

## By time: live, git, distilled

| layer | where | read |
|---|---|---|
| **Live** | `notes/handoff/<session>.md`, one per session: Next, Waiting, Running, Unfinished, Done, Learned | every session start |
| **Git** | every earlier handoff, closed item and dropped lesson, word for word | never whole; searched by id when something points there |
| **Distilled** | `notes/lessons.md`, memories, topic notes, CLAUDE.md, gate scripts | where each lesson acts |

`/handoff` replaces the session's live file each time, and distils it first: each lesson that still holds is
promoted to where it acts, each still-live item (a deadline, an owed step) is carried into the new live file. Only
then is the old file replaced; git keeps it. An append-only log that skips the distilling grows until nobody reads it, with its
lessons buried inside.

## By reach: repo or machine

Three layers, kept apart on purpose.

| layer | where | travels with | holds |
|---|---|---|---|
| **Project state** | the repo: `notes/handoff/`, `BACKLOG.md`, `questions.md`, `CLAUDE.md`, `notes/` | git: every machine, every cloud session, every clone | what is true about the project and what is next |
| **Project lessons** | the repo: `notes/lessons.md`, imported by `CLAUDE.md` | git, like the state | rules every session of this project needs; added by `/handoff` step 5 |
| **Working memory** | `~/.claude/projects/<path-slug>/memory/` (Claude Code auto-memory) | nothing: this machine and this project path only | how to work here: the owner's corrections and preferences, narrow facts, a machine's quirks |

Lessons stay with the project that learned them. This repo holds none, so the workflow fits any project, session,
machine and owner.

**The catch:** working memory does not reach another machine or a cloud session, and it is keyed by the project's
path (moving the checkout starts it empty). So anything another session needs to continue the WORK goes in the
repo; memory holds only what makes a session work BETTER. Never link from a tracked file to a memory file.

## Auto-memory format (Claude Code)

- **One fact per file**, with frontmatter:

  ```markdown
  ---
  name: never-git-add-dash-a
  description: one line, used to decide relevance when recalling
  metadata:
    type: feedback          # user | feedback | project | reference
  ---

  The fact. For feedback and project memories:
  **Why:** what happened (date, what it cost).
  **How to apply:** the concrete rule.
  Related: [[other-memory-name]]
  ```

- **`MEMORY.md` is the index**: one line per memory (`- [Title](file.md) — hook`), loaded into every session's
  context. Bodies are read only when relevant, so the hook line must say enough to know when to open it.
- **Types**: `user` (who the owner is, how they like to work), `feedback` (corrections and confirmed approaches,
  with the reason), `project` (constraints and goals not visible in the code; absolute dates), `reference`
  (pointers to dashboards, tickets, external docs).

## Rules

- **Don't save what the repo records** (code structure, past fixes, git history, CLAUDE.md content). Save what was
  non-obvious about it.
- **Update, don't duplicate.** Check the index before writing; delete a memory that turned out wrong.
- **A memory is point-in-time.** Before acting on one that names a file, flag or function, check it still exists.
- **Feedback memories carry the why.** A rule without its reason gets applied where it does not fit, or dropped where
  it does.
- **Private stays private.** Memory is a good place for things that must never be committed (undisclosed security
  issues, personal context), precisely because it does not travel. Keep it that way: never copy such a memory into
  a tracked file.
- **Promote what every session needs.** A memory that every session of the project needs (a tool quirk, a git
  habit) becomes a lesson in `notes/lessons.md` (`### L-<n> <title>`), which travels with the repo; once it is there, delete the memories
  it fully covers, so it does not load twice.
