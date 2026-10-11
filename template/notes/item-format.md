# Item format

Every item in `BACKLOG.md` and `questions.md` has one shape, so a person reads it, Claude writes it, and a script can
parse it. Both trackers point here; `/handoff` follows it when it adds or changes an item. Both skills check it with
`items.sh` (the last section but one): `/session-start` after the ground truth, `/handoff` before committing.

## Shape

```markdown
next id: <letter>-<n> (last given to <agent>@<session>)      in the file's header, once

## <section>                         BACKLOG: one per repo or file tree. questions.md: "# 1." open, "# 2." rulings

### <state> [⚠ ]<id> <title>
<field>: <value>                     zero or more, right under the heading, from the list below
<body: free markdown>
Done when: <observable result>       BACKLOG only: required, the body's last line
```

```markdown
## web

### 🔲 B-12 Shopping list works offline
Edits made in a shop with no signal are lost. Branch `feat/offline-list`, worktree `web-offline/`.
Done when: an edit made in airplane mode syncs on reconnect, conflicts resolved last-write-wins per item, tested on
a phone.

### 🔲 ⚠ B-14 Show which ingredient matched a search
repos: api → web
A result does not say why it matched. The API returns `matched_ingredient` on each hit, then the results page
highlights it.
Done when: searching "basil" highlights basil in every result.
```

A whole project in this shape: the workflow repo's `example/BACKLOG.md` and `example/questions.md`.

## The id

- `B-` and a number in `BACKLOG.md`, `Q-` and a number in `questions.md`: `B-12`, `Q-4`. Numbers go up by one in
  each file, so an id is short to say and remember, and a lower number is an older item.
- Each file's header holds the next number and who took the last one:
  `next id: B-13 (last given to claude@web-offline)`. A new file starts at `next id: B-1 (none given yet)`.
- An id never changes (a new title, state or section keeps it) and is never reused: `next id` only goes up, and a
  deleted item keeps its number in git.
- It is how an item is cited, everywhere: the handoff, other items, commit messages, branch names
  (`feat/B-12-offline-list`), PR descriptions. Give the title too, for the reader. `git log -S B-12` shows an item's
  whole life, renames included; search with the next character too (`B-12 `, `B-12:`) so `B-120` does not match. A
  position ("item 2 of today's list") is never a reference: the next day's list numbers differently.
- Why a letter: on GitHub, a bare `#12` in a commit or PR links to issue 12, and the letter says which file to open.

**Giving an id.** Take the number in `next id`, then raise it and name yourself in the same edit:
`next id: B-14 (last given to claude@<session>)`. The agent is who writes the item (`claude`, a subagent's name,
`owner`); the session is the worktree's folder name, unless the owner names it. Commit both with the new item. Until
that commit is pushed, the id is provisional: use it in nothing outside the trackers (no branch name, no commit
message elsewhere).

**Two sessions, same number.** Both edited the `next id` line, so the second push is rejected and its `git pull
--rebase` conflicts on that line. Keep the remote's line, renumber your own new items from it, raise it again, and
continue the rebase. Nobody saw your provisional number. The "last given to" part is what makes that conflict
certain: two sessions that both wrote `next id: B-14` alone would have made the same change, which git merges
silently, leaving two items numbered B-13.

## States

| file | state | means |
|---|---|---|
| BACKLOG | 🔲 | open |
| BACKLOG | ⏸️ | waits for a trigger, named in `waits:` |
| BACKLOG | ⚠ (after the state) | cross-repo: runs alone, in the order of `repos:` |
| questions | 💬 | open: needs the owner's decision |
| questions | 🟢 | ruling in force |
| questions | ⏸️ | deferred: the trigger is in `waits:` |

There is no "in progress" or "done" state: work in flight is in the handoff's Next list, and a finished item is
deleted (git keeps it). So a state can never disagree with the facts behind it.

## Fields

Lowercase `key: value` lines, right under the heading, before the first body line. Only these keys:

| key | on | value |
|---|---|---|
| `repos` | ⚠ items | the repos in the order the work runs, producer first: `api → web` |
| `waits` | ⏸️ items | the trigger: a date, a measurement, an owner answer, another id |
| `blocks` | 💬 questions | what waits for the answer |
| `ruled` | 🟢 rulings | `YYYY-MM-DD`, the date of the owner's words quoted in the body |
| `replaces` | 🟢 rulings | `<id> <title>` of the ruling this one overrides |

No date fields otherwise: when an item was added, changed or closed comes from the commits that touched its id.
`ruled` is the exception because it dates the owner's words, not a commit.

## Body

- BACKLOG: what is wrong or missing, a pointer to the detail (file, note, issue), then `Done when:`.
- 💬: the question, the options (A, B, …) with one marked recommended, and why.
- 🟢: the owner's words, then what not to do because of them.

## The check

`bash .claude/skills/session-start/items.sh check` reads both trackers and lists, with its file and line, each place
they depart from this format: a `###` heading that does not match the shape, an unknown state or field, a malformed
or duplicate id, a missing `next id` line or one not above every id in its file, a BACKLOG item without `Done when:`
as its last paragraph, ⚠ without `repos:`, ⏸️ without `waits:`, 🟢 without `ruled:` or with a date not in
`YYYY-MM-DD`. Exit 0 when every item follows the format; 2 when one does not, or when a file cannot be read: never a
silent pass. Fenced code and HTML comments are skipped, so a tracker can show an example.

## Moving a project to it

A project that adopted the workflow before this format (1.x: bullets, cited by title) converts its trackers once.
Each item becomes a heading with an id, numbered from 1 in the order the items were created, oldest first
(`git log --reverse -S'<title>' -- BACKLOG.md` dates one); states, ⚠ and triggers move into their fields; each file
gets its `next id` line; and every place that cites an item by its title (the handoff, `CLAUDE.md`, the notes) puts
the id in front of it. `items.sh check` lists whatever is left.
