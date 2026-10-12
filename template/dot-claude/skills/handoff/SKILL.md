---
name: handoff
description: End-of-session handoff. Distils the session's previous handoff, records what was done, what still runs in the background, what is next (the task of the day) and what waits for the user, in the session's own notes/handoff/<session>.md, BACKLOG.md, questions.md, CLAUDE.md, the topic notes and memory, then commits and pushes as CLAUDE.md's "What Claude does alone" allows, so any session on any machine can start from an empty context. Use it whenever the user wants to finish, close or wrap up a session ("handoff", "end of day", "save where we are", "switching machines", "battery dying"), before a /clear, or when the conversation is about to be compacted after a long stretch of work.
---

# Handoff

The next session starts with an empty context. It sees only CLAUDE.md, the memory index and whatever
`/session-start` reads (the handoffs in `notes/handoff/` first). Anything not written down is lost, so the goal is a short, exact
record of the present state, not a diary. A change is not done when it merges or deploys; it is done when the next
session can find out what happened and why.

## One place for each kind of information

| What | Where | Rule |
|---|---|---|
| Next tasks (task of the day), what waits for the user, what runs in the background, the last session | `notes/handoff/<session>.md`, one per live session (`notes/handoff-format.md`) | Rewritten by its own session at each handoff, after the old one is distilled; deleted when the session's work has landed or was taken over |
| Earlier handoffs, closed items, dropped lessons | git | No archive files: the board shows them; search with `git log -p -S'<id> ' -- <file>` |
| Open work | `BACKLOG.md` | One section per repo or file tree; every item in the shape of `notes/item-format.md`, with its id. A landed item is deleted, not ticked. Cross-repo items marked ⚠ |
| Questions for the user, rulings, deliberate non-fixes | `questions.md` | §1 💬 open; when the user rules, it moves to §2 as 🟢 with their words and a `ruled:` date. Same item shape as `BACKLOG.md` |
| Long-term state, rules, how-tos | `CLAUDE.md` | State, not history: no PR lists, no commit hashes, no to-dos |
| Details of a topic (plans, measurements, incident notes, how-tos) | `notes/*.md`, component READMEs | Linked from where they are needed |
| Non-obvious learnings, user preferences, corrections | memory directory | One fact per file + one line in `MEMORY.md`; update instead of duplicating |
| Lessons that every session needs | `notes/lessons.md`, imported by `CLAUDE.md` | Short rules, each with its id (`L-3`), in the shape of `notes/item-format.md`; merge, don't append; drop what no longer holds |
| History (what changed when, and why) | git / GitHub | Never copied into the docs |

## Steps

1. **Gather facts from the machine, not from recollection.** The conversation may have been compacted, and things
   said earlier can be stale. Run `bash .claude/skills/session-start/ground-truth.sh`: the same script
   `/session-start` runs, so the next session checks your handoff against the picture you wrote it from. For a
   `CI RED` PR, add `gh pr checks <n> -R <owner/repo>`.
   - **Nothing may exist only on this disk without being named.** Every uncommitted worktree, LOCAL ONLY commit and
     unpushed branch that this session touched is either committed (a `wip:` commit whose body says what is
     unfinished and which tests fail, if any) and pushed, or listed under "Unfinished" with its path and what it
     holds. The rows "Commit code" and "Push a work branch" in CLAUDE.md ("What Claude does alone") say whether that
     needs the user's OK. A worktree listed in an earlier handoff stays listed until it is cleaned up. Branches
     marked "local only BY RULE" are never pushed.
2. **Distil, then rewrite this session's handoff**, `notes/handoff/<session>.md` (`<session>`: the worktree's
   folder name unless the owner named the session). Two layers: the live file and what is distilled out of it. Git
   keeps every earlier version; nobody reads it whole, so a lesson left only in an old handoff is a lesson lost.
   - **Distil the old file first** (this session's own, or the one it took over). Each fact under "Learned" that is
     not yet a lesson, and each ⚠ in it: if it still holds, it goes where it acts (a lesson in `notes/lessons.md`, a
     memory, a topic note, CLAUDE.md, a gate script); if it is stale, it is dropped. Anything still LIVE in it (a
     deadline, an owed step, a running job) is carried into the new file.
   - **Write the new file** in the shape of `notes/handoff-format.md`, with the template below: a new id from
     `notes/handoff/README.md` (take `next id`, raise it and name this session in the same edit), `continues:` the
     handoff it replaces. Every task in Next and Waiting for the user names a B- or Q- id: a task without one becomes
     a BACKLOG item (or a question) first. Absolute dates, times with their zone. Name exact paths, branches, units
     and commands, so the next session can act without searching.
   - **Taking over** another session's handoff: `continues:` its id, and delete its file in the same commit.
   - **The session ends for good** (its work landed, nothing live is left): delete its file instead of rewriting it.
   - **Moving from 1.x, once** (a `notes/handoff.md` and its archive): `notes/handoff-format.md`, "Moving a project
     to it".
3. **Update the trackers.** `BACKLOG.md`: delete every item that landed (the commit says where: `B-12 done: a1b2c3d
   on main, PR #41`, so the board links the closed item to that commit and PR), add what was found and not fixed in the
   section it touches (⚠ cross-repo if it needs two; the row "Add an item to the backlog"), fix anything the session
   proved wrong. `questions.md`: add new questions to §1 with a recommendation; move a question the user answered to
   §2 as 🟢 with their words and a `ruled:` date (or delete it if nothing is left to guard). `CLAUDE.md` only when a
   rule, a how-to or the long-term state changed. Keep all three short.
   - **Every new item gets its file's `next id`**, and the same edit raises that line and names this session:
     `next id: B-14 (last given to claude@<session>)` (`notes/item-format.md`, "The id"). An item keeps its id when
     its title, state or section changes. If the push is rejected and the rebase conflicts on that line, keep the
     remote's line and renumber your new items from it.
   - Cite items by id with their title (`B-12 Shopping list works offline`), here and in the handoff.
   - Then `bash .claude/skills/session-start/items.sh check`: it lists each item (lessons and handoffs included)
     that departs from its format, with its line. Fix them until it exits 0, before committing (step 7); write the
     handoff (step 2) before running it.
4. **Update the topic notes the session touched** (status lines, measurements, how-tos), so the trackers can stay
   short.
5. **Save memories** for what a future session would otherwise get wrong: corrections from the user, surprising
   facts, confirmed preferences. Check the index for an existing memory first. Route each one by how far it holds:
   - a rule every session needs (a tool quirk, a git habit, a verification rule, a way of working with the owner)
     → a lesson in `notes/lessons.md`, even when it sounds generic: a lesson belongs to the project that learned it
     and travels with its repo. A new one is `### L-<n> <title>` with the file's `next id`, raised in the same edit;
     the handoff's "Learned" section names it by id. Merge, don't append: a merged lesson is deleted and the commit
     says so (`notes/item-format.md`, Body). Once a lesson is there, delete the memories it fully covers;
   - a narrow fact or a preference → this project's memory directory (local to this machine: anything another
     machine or a cloud session needs goes in the repo);
   - an improvement to the session loop itself (a skill step, a ground-truth check) → its generic part goes back to
     the workflow repo in its own commit (README, "Improve the workflow"). Never a lesson.
6. **Background work:** stop anything that should not keep running, as the row
   "Stop a background job this session started" allows; ask the user if unsure, and always for a job another
   session started. Everything left running goes in the "Running" table with how to check it and how to stop it.
7. **Commit and push the docs** (handoff, trackers, notes) as the rows "Commit the docs" and "Push the docs" allow.
   Every ask-first step of this handoff (steps 1, 3, 6 and this one) goes to the user in one question, with what
   each would do. The message starts with the handoff's id: `H-5 Handoff: <what was done>; next <ids>`. Then verify
   that the remote has the tip (`git log origin/<branch> -1`, or run the ground truth again): a push that failed is
   a handoff that did not happen. Never commit secrets: if a secret is needed, write THAT it is needed, never its
   value.
8. **Tell the user in a few lines:** where the state is written, the next task, and what waits for them.

## Template for notes/handoff/<session>.md

```markdown
# H-<n> YYYY-MM-DD HH:MM <zone> · <agent>@<session>
continues: H-<n>

## Next
1. <id> <title> [<repo or area>]: <why now>, <where to start: file, branch, command>, <done when ...>

## Waiting for the user
- <Q- id and title that block the Next list; a new question goes into questions.md first>

## Running
| What | Unit / process | Ends | Check | Stop |
|---|---|---|---|---|

## Unfinished
- <repo>: <worktree / branch>, <uncommitted, LOCAL ONLY or pushed>, <what is left>

## Done
- <id> <title>: <commit or PR, where it landed, CI>

## Learned
- <L- ids added or changed>; <a fact the next session needs that is not a lesson>
```

An empty section says `None.`; a missing section is an error. Keep it under about 60 lines. If something needs more
space, it belongs in a topic note with a link from here.
