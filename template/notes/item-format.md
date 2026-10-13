# Item format

Every item in `BACKLOG.md`, `questions.md` and `notes/lessons.md` has one shape, so a person reads it, Claude writes
it, and a script can parse it. The three files point here; `/handoff` follows it when it adds or changes an item.
Both skills check it with `items.sh` ("The check", below): `/session-start` after the ground truth, `/handoff`
before committing.

## Shape

```markdown
next id: <letter>-<n> (last given to <agent>@<session>)      in the file's header, once

## <section>                         BACKLOG: one per repo or file tree. questions.md: "# 1." open, "# 2." rulings

### <state> [⚠ ]<id> <title>
<field>: <value>                     zero or more, right under the heading, from the list below
<body: free markdown>
Done when: <observable result>       BACKLOG only: required, the body's last line
```

A lesson has no state: `### L-<n> <title>`, then its rule and the reason in a few words. A lesson in the file
holds; one that no longer holds is deleted.

```markdown
## web

### 🔲 B-12 Shopping list works offline
claimed: claude@pantry-12 on feat/offline-list
Edits made in a shop with no signal are lost. Worktree `web-offline/`.
Done when: an edit made in airplane mode syncs on reconnect, conflicts resolved last-write-wins per item, tested on
a phone.

### 🔲 ⚠ B-14 Show which ingredient matched a search
repos: api → web
A result does not say why it matched. The API returns `matched_ingredient` on each hit, then the results page
highlights it.
Done when: searching "basil" highlights basil in every result.
```

A whole project in this shape: the workflow repo's `example/BACKLOG.md`, `example/questions.md` and
`example/notes/lessons.md`.

## The id

- `B-` and a number in `BACKLOG.md`, `Q-` in `questions.md`, `L-` in `notes/lessons.md`: `B-12`, `Q-4`, `L-3`.
  Numbers go up by one in each file, so an id is short to say and remember, and a lower number is an older item.
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

A lesson has no state. "In progress" and "done" are never written by hand: an item in progress is still 🔲 open, with
a `claimed:` line that names who works on it (Claims, below), and a finished item is deleted (git keeps it). So a state can never disagree with the facts
behind it.

## Fields

Lowercase `key: value` lines, right under the heading, before the first body line. Only these keys:

| key | on | value |
|---|---|---|
| `claimed` | BACKLOG items | `<agent>@<session> on <branch>`: who works on it, and where (Claims, below) |
| `repos` | ⚠ items | the repos in the order the work runs, producer first: `api → web` |
| `repos` | questions, optional | the repos the decision is about: `api, web`; none = the whole project |
| `repos` | lessons, optional | the repos the lesson is about; none = the whole project |
| `waits` | ⏸️ items | the trigger: a date, a measurement, an owner answer, another id |
| `blocks` | 💬 questions | what waits for the answer |
| `ruled` | 🟢 rulings | `YYYY-MM-DD`, the date of the owner's words quoted in the body |
| `replaces` | 🟢 rulings | `<id> <title>` of the ruling this one overrides |

No date fields otherwise: when an item was added, changed, claimed or closed comes from the commits that touched its
id.
`ruled` is the exception because it dates the owner's words, not a commit.

**An item's repos**, for the board: its `repos:` line, else its section when the section's title starts with a repo's
name from `.claude/ground-truth.conf` (`## api`), so a BACKLOG item rarely needs the line. A question's sections are
"open" and "rulings", so a question names its repos with the line, in a project with more than one repo.

## Body

- BACKLOG: what is wrong or missing, a pointer to the detail (file, note, issue), then `Done when:`.
- 💬: the question, the options (A, B, …) with one marked recommended, and why.
- 🟢: the owner's words, then what not to do because of them.
- Lesson: the rule, then its reason in a few words. **Merge, don't append:** when a new lesson says what an old one
  says, the old one is rewritten and keeps its id; when two lessons merge, one keeps its id, the other is deleted,
  and the commit says so (`L-4 merged into L-2`).

## Claims

An item is claimed when an agent starts working on it: the claim says who works on it, and where. Two sessions must
not work on one item, so the claim is pushed at once, as the row "Claim an item" in `CLAUDE.md` ("What Claude does
alone") allows:

```bash
bash .claude/skills/session-start/claim.sh B-12 feat/B-12-offline-list
```

It adds `claimed: <agent>@<session> on <branch>` under the item's heading, in a commit of its own (`claim B-12`) on
the remote's default branch, and pushes it.
- **agent:** who does the work: `claude`, a subagent's name, `owner`.
- **session:** the name other sessions message it by (`ListAgents`: "This session is workflow-dev-64"), so Claude
  knows at once which session works on what; the worktree's folder name where there is none. Claude passes it as
  the third argument, `claude@<name>`.
- **branch:** where the work goes: the fact behind the claim, which the ground truth follows.

The push is the lock. When another session pushed first, git refuses the push; the script reads the item again
from the new tip, then claims it there, or exits 1 and names who has it: pick another item. The claim is built on
the remote's tip, never on the files here, so it works from any branch or worktree. An item that is not on the
remote yet is pushed before it is claimed: its id is final then, and it shows in git even if it is finished the same
day.

The ground truth lists every claim with its branch: the repo it is in, its last commit, pushed or not. It reports a
claim not pushed (no other session sees it), a branch that is gone, and a branch with no commit for
`CLAIM_STALE_DAYS` days (`.claude/ground-truth.conf`, 3 by default; counted from the claim when the branch is
older): its session may have stopped without a handoff. Only the owner releases another session's claim.

Releasing: when the work lands, the item is deleted, claim and all. When a session stops before that, `/handoff`
keeps the claim with its branch pushed and named under "Unfinished", or deletes the line, and the docs push frees
the item. A new session has a new name: going on with a claim its handoff kept, it takes the claim over with
`--from <the claim's agent@session>`, which replaces the line only while the remote still has that claim.

## The check

`bash .claude/skills/session-start/items.sh check` reads both trackers and the lessons, and lists, with its file and
line, each place they depart from this format: a `###` heading that does not match the shape, an unknown state or field,
a malformed or duplicate id, a missing `next id` line or one not above every id in its file, a BACKLOG item without
`Done when:` as its last paragraph, ⚠ without `repos:`, ⏸️ without `waits:`, 🟢 without `ruled:` or with a date not in
`YYYY-MM-DD`, a `claimed:` line not in the shape `<agent>@<session> on <branch>`, a lesson with a state, a lesson
left as a bullet, with no id. Exit 0 when every item follows the format; 2 when one does not, or when a file cannot
be read: never a silent pass. Fenced code and HTML comments are skipped, so a tracker can show an example. It checks
the handoffs too (`notes/handoff-format.md`, "The check").

## The board

`bash .claude/skills/session-start/board.sh` writes both trackers, the lessons and the handoffs as one page, a tab each,
and opens it: the repos and their count, every item with its state (and in the backlog, who claimed it), repos and dates, filters by repo (one, several, or
the items that span more than one), state, date (added, last changed, closed, ruled) and text, each item's history from
git, and the handoffs that name it. Each commit opens to its whole message and the files it changed; a commit hash
quoted anywhere (an item, a handoff, a commit message, a PR) links to that commit in whichever repo of
`.claude/ground-truth.conf` holds it, and so do the commits that name an item by its id. PRs come from GitHub, read by
`gh` when the page is built: a PR that names an item (title, description, branch) and a PR an item names (`#41`) show
with the item, with their description and merge commit. Without `gh`, or with `--offline`, the page says the PRs were
not read. Closed items come back from git: a deleted item as "closed", a deleted lesson as "dropped", a replaced handoff
as "replaced". Handoffs written before they had ids (one `notes/handoff.md`) are shown by their date. The page is
read-only and rebuilt at each run (no server, nothing to install): run the script again to refresh it. An item the
parser cannot read shows in the problems box as written, never dropped.

## Moving a project to it

A project that adopted the workflow before this format (1.x: bullets, cited by title) converts its trackers once.
Each item becomes a heading with an id, numbered from 1 in the order the items were created, oldest first
(`git log --reverse -S'<title>' -- BACKLOG.md` dates one); states, ⚠ and triggers move into their fields; each
lesson in `notes/lessons.md` becomes `### L-<n> <title>` the same way; each file gets its `next id` line; and every
place that cites an item by its title (the handoff, `CLAUDE.md`, the notes) puts
the id in front of it. `items.sh check` lists whatever is left.
