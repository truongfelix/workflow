# Handoff format

A handoff is what a session leaves for the next one: what to do next, what waits for the owner, what still runs,
what is unfinished, what was done and learned. `/handoff` writes it in this shape, `/session-start` reads it, and
`items.sh check` checks it, like the items of `notes/item-format.md`, whose id rules it follows.

## One per session

- `notes/handoff/<session>.md`: one file per live session. `<session>` is the session's name, the one other sessions
  message it by (`ListAgents`: "This session is web-offline"), as in its claims (`notes/item-format.md`, Claims); the
  worktree's folder name where there is none. Two sessions working at once each write their own, so neither
  overwrites the other.
- A new session has a new name: it takes the last handoff over when that one's session no longer runs, so a project
  worked by one session at a time keeps one file.
- `notes/handoff/README.md`: what the folder holds, and the `next id` line:
  `next id: H-13 (last given to claude@web-offline)`. Two sessions handing off at once conflict on that line and
  renumber, as with items.
- A session writes only its own file. Taking over another session's work: the new handoff names that session's
  handoff in `continues:`, and deletes its file in the same commit.
- A session that ends for good (its work landed, or another session took it over) deletes its file. The last handoff
  is never deleted: the next session takes it over.

## Shape

```markdown
# H-12 2026-10-09 18:40 CEST · claude@web-offline
continues: H-11

## Next
1. B-12 Shopping list works offline [web]: <why now>, <where to start: file, branch, command>, <done when>.

## Waiting for the user
- Q-3 Metric only on the shopping list?: blocks the totals row.

## Running
None.

## Unfinished
- web: `web-offline/` on `feat/B-12-offline-list`, pushed; the edit queue is not started; B-12: claim kept.

## Done
- B-11 Search recipes by ingredient: #39 merged.

## Learned
- L-3 Stacked PRs target main (new).
- `npm test` in `web/` runs against the staging API unless `API_URL` is set.
```

- **Heading:** `# H-<n> YYYY-MM-DD HH:MM <zone> · <agent>@<session>`, on the first line. The file is named after the
  session: `web-offline.md`. `continues:`, right under it, names the handoff this one replaces (the session's
  previous one, or the one taken over); a session's first handoff has none.
- **Sections:** these six, in this order. An empty one says `None.`, so a missing section is an error, not
  "nothing".
- **Every task names an id.** Each task in Next (a numbered line) and in Waiting for the user (a bullet) starts with
  the B- or Q- id of its item. A task without one becomes a BACKLOG item, or a question, first: the handoff orders
  and comments the trackers, it holds no work of its own.
- **Running** is a table: what, the unit or process, when it ends, how to check it, how to stop it.
- **Learned** names the lessons this session added or changed, by id, then any fact the next session needs that is
  not a lesson. That fact is distilled at the next handoff: it goes where it acts (a lesson, a memory, a topic note,
  `CLAUDE.md`, a gate script) or is dropped.
- **The commit** that writes it starts with its id: `H-12 Handoff: search merged (B-11); next offline (B-12)`.

Keep it under about 60 lines: what needs more space goes in a topic note, linked from here.

## Git is the archive

There is no archive file. A replaced handoff, a finished item, a ruling that no longer guards anything and a lesson
that no longer holds are deleted from their live file, and git keeps each one word for word.
`bash .claude/skills/session-start/items.sh show <id>` prints any of them (B-, Q-, L- or H-), live or deleted: its
text, the commits that added, changed and closed it, and the handoffs that name it. The board shows them all: past
handoffs, closed items, archived rulings, dropped lessons. Both say when git cannot vouch for the past: in a shallow
clone the history before its oldest commit is UNKNOWN (`git fetch --unshallow`), never "none"; and an id that git
shows given twice (back under another title after it was closed, or held by two items at once) is flagged.

## The check

`bash .claude/skills/session-start/items.sh check` reads every handoff with the trackers and reports, with its file
and line: a first line not in the heading's shape, a file not named after its session, an unknown field, a
`continues:` that is not an older H- id, a missing, unknown, repeated or out-of-order section, an empty one, a task
without an id, an id that is in no tracker (a task names an open item: one that landed goes under Done), an H- id
given twice, and a `next id` not above every handoff's id.

## Moving a project to it

A project that adopted the workflow before this format (1.x) has one `notes/handoff.md` and a
`notes/handoff-archive.md`. Its next `/handoff` distils `notes/handoff.md` as usual, writes
`notes/handoff/<session>.md` as H-1 with `notes/handoff/README.md` at `next id: H-2`, and deletes both old files,
once git holds every handoff in the archive (`git log -p -- notes/handoff.md` shows each version); keep the archive,
frozen, if it holds handoffs older than the repo. A 1.x handoff has no id: the board shows it by its date
(`H~<date>`), a brief names it by its date, and `git log -p -- notes/handoff.md` prints it (`items.sh show <id>`
lists the ones that name an item).
