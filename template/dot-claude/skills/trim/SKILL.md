---
name: trim
description: Trim the rulings (questions.md §2) and the lessons (notes/lessons.md) with the owner, in a session set aside for it - each entry kept, shortened, moved to the doc where it acts, or deleted (git keeps it). Use it when the user types /trim, when the /session-start brief says a trim is due (the ground truth flags a file "⚠ TRIM": it passed its size in .claude/ground-truth.conf), or when the user asks to clean up, shorten or prune the rulings or the lessons.
---

# Trim

The rulings in `questions.md` §2 and the lessons in `notes/lessons.md` only grow: an entry stays until someone deletes
it, and every session reads both (`CLAUDE.md` imports the lessons whole). A trim keeps what still guards something and
leaves the rest to git. It runs in a session of its own, never at the end of another one (`/handoff` does not trim):
Claude proposes, the owner decides each entry.

1. **Ground truth:** `bash .claude/skills/session-start/ground-truth.sh`. Its sections `== questions.md` and
   `== notes/lessons.md` give each file's length against its size (`QUESTIONS_TRIM_LINES`, `LESSONS_TRIM_LINES` in
   `.claude/ground-truth.conf`, which the owner sets; 0 = never flagged). Trim the file the user named, else each one
   flagged `⚠ TRIM`, else ask which.
2. **Go through the entries with the owner, four at a time** (one question each, in one AskUserQuestion): the rulings
   of `questions.md` §2, the lessons of `notes/lessons.md`. Each question gives the entry's id and title, what it
   guards and why, and four choices, your recommendation first:
   - **keep**;
   - **keep and shorten**: the same rule in fewer words;
   - **move to its doc**: the rule goes where it acts (a README, a topic note, `CLAUDE.md`, a comment in the code);
   - **delete**: it guards nothing any more (what it forbade is now simply how the code works).
   The test behind the recommendation: would the mistake come back without the entry, and does a script, a doc or
   `CLAUDE.md` already hold it? An entry left unanswered is kept.
3. **Apply the answers.** An entry moved or deleted leaves its file, and the commit says where it went (`Q-3 archived:
   <why>`, `Q-4 moved to README.md`, `L-4 merged into L-2`): git keeps its words and its reason, `items.sh show <id>`
   prints it, and the board shows it as archived. Two lessons that say one thing become one. Then
   `bash .claude/skills/session-start/items.sh check` until it exits 0.
4. **Still above its size** after the pass: propose a new size to the owner (the length now plus a quarter), so the
   next brief does not ask again; with a yes, change its line in `.claude/ground-truth.conf`.
5. **Commit and push** as `CLAUDE.md`'s "What Claude does alone" allows (the rows "Commit the docs" and "Push the
   docs"), and tell the owner what was kept, shortened, moved and deleted, each by its id and title.
