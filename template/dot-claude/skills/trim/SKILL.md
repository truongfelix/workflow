---
name: trim
description: Trim the rulings (questions.md §2) and the lessons (notes/lessons.md) with the owner, in a session set aside for it - Claude answers the same questions about each entry (still true? enforced by a check? said by a doc? could a check enforce it? would the mistake come back?), then proposes one plan, each entry kept, shortened, moved to where it acts, merged or deleted (git keeps it), and the owner changes only the lines they disagree with. Use it when the user types /trim, when the /session-start brief says a trim is due (the ground truth flags a file "⚠ TRIM": it passed its size in .claude/ground-truth.conf), or when the user asks to clean up, shorten or prune the rulings or the lessons.
---

# Trim

The rulings in `questions.md` §2 and the lessons in `notes/lessons.md` only grow: an entry stays until someone deletes
it, and every session reads both (`CLAUDE.md` imports the lessons whole). A trim keeps what still guards something and
leaves the rest to git. It runs in a session of its own, never at the end of another one (`/handoff` does not trim).
Claude answers the same questions about every entry and proposes one plan; the owner decides.

1. **Ground truth:** `bash .claude/skills/session-start/ground-truth.sh`. Its sections `== questions.md` and
   `== notes/lessons.md` give each file's length against its size (`QUESTIONS_TRIM_LINES`, `LESSONS_TRIM_LINES` in
   `.claude/ground-truth.conf`, which the owner sets; 0 = never flagged). Trim the file the user named, else each one
   flagged `⚠ TRIM`, else ask which.
2. **The facts of each entry** (each ruling of `questions.md` §2, each lesson of `notes/lessons.md`):
   - `bash .claude/skills/session-start/items.sh show <id>`: its history, and the handoffs that name it;
   - the latest commit whose message names it, in each repo of the ground truth:
     `git -C <repo> log -1 --format='%cs %h %s' -E --grep='<id>([^0-9]|$)'`;
   - what already holds its rule: search the checks (the tests, the gate, the hooks, `items.sh check`) and the docs
     (README, `CLAUDE.md`, the skills, the topic notes) for its words, and name the check or the line that holds it.
3. **Answer these questions about each entry, in this order.** The first that settles it gives the action; an entry
   kept still goes through 7 and 8.
   1. **Still true?** The file, command or tool it names still exists, and what it guards against can still happen.
      No → **delete**.
   2. **Enforced by a check?** A test, a hook, the gate or the format check fails when it is broken → **delete**; the
      commit names the check.
   3. **Said by a doc?** The README, `CLAUDE.md`, a skill or a topic note says it → **delete**, or shorten it to a
      pointer to that doc.
   4. **About how the tools or the code work, rather than a choice of the owner?** → **move** it to where it acts:
      the code, its doc, and a check.
   5. **Could a check enforce it?** → **keep it for now**, with a backlog item for the check when the mistake is worth
      one (6); once the check lands, the entry shrinks to a line or goes.
   6. **Would the mistake come back without it, and what would it cost?** Minutes of rework and nobody has cited it in
      months → **delete**. Costly (a shared branch rewritten, work or data lost, a secret pushed) → **keep**, however
      old. "Last cited" is evidence, never a rule: no entry goes for its age alone.
   7. **Said twice?** Another entry holds the same rule → **merge** into one id; the other is deleted.
   8. **Fewer words?** The same rule, shorter → **shorten**: every session loads the lessons whole.
   None settles it → **keep**.
4. **One plan, to the owner, in the chat:** every entry on a line, grouped by action (delete, move, merge, shorten,
   keep), each with its id and title, its action, the question that settled it, and its facts (last cited; the check
   or doc that holds it). Then ask, in words: the plan as it stands, or which lines to change ("keep L-5", "shorten
   Q-3"). An entry the owner changes takes the owner's action; the rest follow the plan once the owner says yes. No
   yes, nothing changes.
5. **Apply the plan.** An entry moved or deleted leaves its file, and the commit says where it went (`Q-3 archived:
   <why>`, `Q-4 moved to README.md`, `L-4 merged into L-2`): git keeps its words and its reason, `items.sh show <id>`
   prints it, and the board shows it as archived. A move into the code, or a check to write, is a backlog item (the
   row "Add an item to the backlog"), built once the owner approves it; its entry stays until it lands. Then
   `bash .claude/skills/session-start/items.sh check` until it exits 0.
6. **Still above its size** after the trim: propose a new size to the owner (the length now plus a quarter), so the
   next brief does not ask again; with a yes, change its line in `.claude/ground-truth.conf`.
7. **Commit and push** as `CLAUDE.md`'s "What Claude does alone" allows (the rows "Commit the docs" and "Push the
   docs"), and tell the owner what was kept, shortened, moved, merged and deleted, each by its id and title.
