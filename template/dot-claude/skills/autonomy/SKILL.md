---
name: autonomy
description: Show and change what Claude does alone in this project, step by step - for each step (start the day's task, commit, push, add or claim a backlog item, open or merge a pull request, delete a merged branch, release, message), whether Claude asks the owner first or does it and then tells. Switch to a preset (Careful, Balanced, Hands-off) or pick the steps to switch from a list. Use it when the user types /autonomy (with or without a preset's name), asks to see or change what Claude may do without asking ("ask me before pushing", "stop asking before commits", "switch to Balanced", "what do you do without asking?"), and at setup (SETUP.md, step 4).
---

# Autonomy

The table "What Claude does alone" in `CLAUDE.md` answers, for each step where a session could stop and ask: **ask
first** or **do, then tell**. This skill shows it and changes it with the owner's picks. `autonomy.sh` reads and
writes the rows, so nothing else in `CLAUDE.md` moves.

Ask as `CLAUDE.md`'s rule "A question to the owner" says: the owner may never have opened `CLAUDE.md`. A question
tool cannot show a box already ticked, so each step's question says its answer now.

## Steps

1. **Read the table:** `bash .claude/skills/autonomy/autonomy.sh show`. It prints each step with its answer, then the
   preset the steps make, or the closest one and the steps that differ. Exit 2: say what it printed (no table, or a
   row answered neither way) and stop; the table is fixed by hand first.
2. **What the request names**, then step 5 (with none of these, step 3):
   - **A preset's name** (`/autonomy balanced`, "switch to Careful"): `autonomy.sh preset <name>`.
   - **Steps, with their answer** ("ask me before pushing a work branch", "stop asking before commits"): `autonomy.sh
     ask <step>...` or `autonomy.sh tell <step>...`, with no question. When the words fit more than one step
     ("pushing": the docs, a work branch), ask which first: one question with those steps and "None of these".
   - **Steps to ask about**, with no answer (the upgrade from 1.x names its six new steps; "ask me about the backlog
     steps"): the questions of "Change some steps" (step 4) with those steps alone, at most three to a question.
3. **Show it** in a few lines: the preset ("Careful, with 2 steps switched"), the steps Claude asks you about first,
   and the steps it does, then tells you. Each step in plain words ("Commit code"), never a row number. At setup,
   the preset by what it does ("asks before every step, with 2 steps switched"), as in step 4.
4. **Ask.** At setup there is nothing to keep yet: start with the preset question, then ask whether to keep that
   preset as it is or change some steps (two options). Otherwise ask first, with three options: keep it as it is,
   switch to a preset, change some steps.
   - **The preset question**, three options, each saying which steps Claude asks about first and which it does, then
     tells. **Careful** asks first for every step. **Balanced** asks first to start the day's task, to build
     something that is not an approved backlog item, to open or merge a pull request, to release, and to comment or
     message; it does the rest, then tells. **Hands-off** asks first only to build something that is not an approved
     backlog item, to release, and to comment or message. At setup the owner has not met these names, so each option
     is labelled by what it does, with no name: "Ask before every step", "Ask before the big steps", "Ask only before
     new work, a release or a message" (SETUP.md, step 4). Before the options, list the steps
     in plain words: start the day's task, commit the docs (the notes and trackers), push them, add an item to the
     backlog, claim one, build something that is not an approved backlog item, commit code, push a work branch, open
     a pull request, merge one (or push code to the default branch), delete a branch whose work has landed, stop a
     background job it started, release, comment or message anyone. Then `autonomy.sh preset <name>`.
   - **Change some steps:** one option per step, which the owner picks or not, showing its answer now ("Commit code,
     now: does it, then tells you"); a picked step takes the other answer. Five questions, at most three steps each
     next to "None of these": the docs (commit the docs, push the docs), the backlog (add an item, claim one, build something not approved), code
     (commit code, push a work branch, delete a branch whose work has landed), sharing (open a pull request, merge
     one, release), and the rest (start the day's task, stop a background job, comment or message). Four are asked
     at once, then the fifth; a row of the project's own (`show` names them) goes in a sixth. Then
     `autonomy.sh ask <step>...` for the picked steps that did not ask first, and `autonomy.sh tell <step>...` for
     those that did: a step by its text, as `show` prints it.
   - **Keep it**, or "None of these" in every question: nothing changes.
5. **Say what changed**, a line per step ("Commit code: now does it, then tells you"), or that nothing did, and that
   it holds from the next action on. Plain words still work later too: "from now on, push the docs without asking".
6. **Commit `CLAUDE.md`** as its row "Commit the docs" now says, and push as "Push the docs" says: ask first, or do it
   and say so. At setup, the setup commits it with the rest.
