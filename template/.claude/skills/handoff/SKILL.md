---
name: handoff
description: End-of-session handoff. Distils and archives the previous handoff, records what was done, what still runs in the background, what is next (the task of the day) and what waits for the user, in notes/handoff.md, BACKLOG.md, questions.md, CLAUDE.md, the topic notes and memory, then commits and pushes per the project's handoff rule, so any session on any machine can start from an empty context. Use it whenever the user wants to finish, close or wrap up a session ("handoff", "end of day", "save where we are", "switching machines", "battery dying"), before a /clear, or when the conversation is about to be compacted after a long stretch of work.
---

# Handoff

The next session starts with an empty context. It sees only CLAUDE.md, the memory index and whatever
`/session-start` reads (`notes/handoff.md` first). Anything not written down is lost, so the goal is a short, exact
record of the present state, not a diary. A change is not done when it merges or deploys; it is done when the next
session can find out what happened and why.

## One place for each kind of information

| What | Where | Rule |
|---|---|---|
| Next tasks (task of the day), what waits for the user, what runs in the background, the last session | `notes/handoff.md` (live) | Rewritten at each handoff, after the old one is distilled and archived |
| Earlier handoffs | `notes/handoff-archive.md` | Newest first, word for word. Never read at session start; searched when needed |
| Open work | `BACKLOG.md` | One section per repo or file tree. A landed item is deleted, not ticked. Cross-repo items marked ⚠ |
| Questions for the user, rulings, deliberate non-fixes | `questions.md` | §1 💬 open; when the user rules, it moves to §2 as 🟢 with their words and the date |
| Long-term state, rules, how-tos | `CLAUDE.md` | State, not history: no PR lists, no commit hashes, no to-dos |
| Details of a topic (plans, measurements, incident notes, how-tos) | `notes/*.md`, component READMEs | Linked from where they are needed |
| Non-obvious learnings, user preferences, corrections | memory directory | One fact per file + one line in `MEMORY.md`; update instead of duplicating |
| Lessons that every session needs | `notes/lessons.md`, imported by `CLAUDE.md` | Short rules; merge, don't append; drop what no longer holds |
| History (what changed when, and why) | git / GitHub | Never copied into the docs |

## Steps

1. **Gather facts from the machine, not from recollection.** The conversation may have been compacted, and things
   said earlier can be stale. Run `bash .claude/skills/session-start/ground-truth.sh`: the same script
   `/session-start` runs, so the next session checks your handoff against the picture you wrote it from. For a
   `CI RED` PR, add `gh pr checks <n> -R <owner/repo>`.
   - **Nothing may exist only on this disk without being named.** Every uncommitted worktree, LOCAL ONLY commit and
     unpushed branch that this session touched is either committed (a `wip:` commit whose body says what is
     unfinished and which tests fail, if any) and pushed, or listed under "Unfinished" with its path and what it
     holds. Follow the project's handoff rule in CLAUDE.md for whether that needs the user's OK. A worktree listed in
     an earlier handoff stays listed until it is cleaned up. Branches marked "local only BY RULE" are never pushed.
2. **Distil, archive, then rewrite `notes/handoff.md`.** Three layers: the live file, its archive, and the lessons
   distilled out of it. A lesson left only in the archive is a lesson lost, because nobody reads the archive whole.
   - **Distil the old file first.** Each "Learned" line and each ⚠ in it: if it still holds, it goes where it acts
     (`notes/lessons.md`, a memory, a topic note, CLAUDE.md, a gate script); if it is stale, it is dropped. Anything still LIVE in it (a deadline, an owed step, a running job) is carried into the
     new file, never left in the archive.
   - **Archive it:** put the old file's whole content at the top of `notes/handoff-archive.md` (below that file's
     header), word for word.
   - **Write the new file** with the template below. Absolute dates, times with their zone. Name exact paths,
     branches, units and commands, so the next session can act without searching.
3. **Update the trackers.** `BACKLOG.md`: delete every item that landed, add what was found and not fixed in the
   section it touches (⚠ cross-repo if it needs two), fix anything the session proved wrong. `questions.md`: add new
   questions to §1 with a recommendation; move a question the user answered to §2 as 🟢 with their words (or delete
   it if nothing is left to guard). `CLAUDE.md` only when a rule, a how-to or the long-term state changed. Keep all
   three short.
4. **Update the topic notes the session touched** (status lines, measurements, how-tos), so the trackers can stay
   short.
5. **Save memories** for what a future session would otherwise get wrong: corrections from the user, surprising
   facts, confirmed preferences. Check the index for an existing memory first. Route each one by how far it holds:
   - a rule every session needs (a tool quirk, a git habit, a verification rule, a way of working with the owner)
     → one line in `notes/lessons.md`, even when it sounds generic: a lesson belongs to the project that learned it
     and travels with its repo. Merge, don't append. Once a lesson is there, delete the memories it fully covers;
   - a narrow fact or a preference → this project's memory directory (local to this machine: anything another
     machine or a cloud session needs goes in the repo);
   - an improvement to the session loop itself (a skill step, a ground-truth check) → its generic part goes back to
     the workflow repo in its own commit (README, "Improve the workflow"). Never a lesson.
6. **Background work:** stop anything that should not keep running; ask the user if unsure. Everything left running
   goes in the "Running" table with how to check it and how to stop it.
7. **Commit and push the docs** (handoff, trackers, notes) per the project's handoff rule. Then verify that the
   remote has the tip (`git log origin/<branch> -1`, or run the ground truth again): a push that failed is a
   handoff that did not happen. Never commit secrets: if a secret is needed, write THAT it is needed, never its
   value.
8. **Tell the user in a few lines:** where the state is written, the next task, and what waits for them.

## Template for notes/handoff.md

```markdown
# Handoff (YYYY-MM-DD HH:MM <zone>)

Read by /session-start. Open work: `BACKLOG.md`. Decisions and rulings: `questions.md`. Rewritten at each /handoff.

## Next (task of the day, in order)
1. [<repo or area>] <task>: <why now>, <where to start: file, branch, command>, <done when ...>

## Waiting for the user
<the `questions.md` §1 titles that block the Next list; a new question goes into questions.md first>

## Running in the background
| What | Unit / process | Ends | Check | Stop |
|---|---|---|---|---|

## Last session (YYYY-MM-DD)
- Done: <one line each, with PR numbers>
- Unfinished: <repo>: <worktree / branch>, <uncommitted, LOCAL ONLY or pushed>, <what is left>
- Learned: <facts the next session needs that are not in CLAUDE.md>
```

Keep it under about 60 lines. If something needs more space, it belongs in a topic note with a link from here.
