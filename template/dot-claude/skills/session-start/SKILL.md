---
name: session-start
description: Start-of-session brief. Runs the ground-truth script (repos, worktrees, open PRs + CI, background jobs), reads the handoffs in notes/handoff/ and reconciles them against those facts, checks deadlines, then proposes the task of the day from the handoff, BACKLOG.md and questions.md. Use it at the start of every session, right after /clear, or whenever the user asks where things stand ("where are we", "what's next", "continue the work", "what's running", "resume", "start the day", "what did we do last time").
---

# Session start

Rebuild just enough context to pick the day's work, from the files and the machine alone: the last session's
conversation is gone. CLAUDE.md and the memory index are already loaded, so don't read them again.

The inverse of `/handoff`. Don't just execute the top item: tracker statuses drift in both directions (items still
open that already shipped, "done" items whose code changed since).

## Steps

1. **Ground truth first:** `bash .claude/skills/session-start/ground-truth.sh` (repos and their worktrees against
   the remote, LOCAL ONLY and uncommitted work, branches no worktree holds, open PRs with a CI verdict, the claims
   on BACKLOG items and their branches, what checks the code (each repo's gate and GitHub CI, the rules kept) and
   where each default branch stands with them, background jobs; what it looks at is in `.claude/ground-truth.conf`).
   Exit 2 means a probe failed: that section is UNKNOWN, never "clean". An open PR is usually the active thread.
   Then `bash .claude/skills/session-start/items.sh check`: the format of the trackers, the lessons and the
   handoffs (`notes/item-format.md`, `notes/handoff-format.md`). Exit 2
   lists each item that breaks it, with its line (a hand edit, or a merge that gave one id twice): that goes in the
   brief, and an id given twice is fixed before any work cites it.
   Then `bash .claude/skills/session-start/board.sh --no-open`: the board rebuilt, with the PRs, never a new tab.
2. **Read the handoffs**, one per live session in `notes/handoff/<session>.md` (`notes/handoff-format.md`): this
   session's own first (`<session>`: the worktree's folder name unless the owner names it), in full; then each
   other one's Next, Running and Unfinished, a line each: another session's work, never taken without the owner.
   A project still on 1.x has one `notes/handoff.md`: read it; its next `/handoff` moves it.
   - If there is none for this session, the latest handoff stands in for it when its session is not running
     (`ListAgents`): say so, and read it in full; its work is still taken over only with the owner's yes. A handoff
     older than the latest activity in git or on GitHub: say so, and lean on `BACKLOG.md`, `questions.md` and the
     ground truth.
   - Earlier handoffs, closed items and dropped lessons are in git, not in archive files: when a handoff or a
     question points to one, `bash .claude/skills/session-start/items.sh show <id>` prints it, with its history and
     the handoffs that name it.
   - Beyond the Next list, open work is in `BACKLOG.md` and the user's open questions in `questions.md` §1. Read them
     when the Next list is done or the user asks for something else. `questions.md` §2 holds rulings and deliberate
     non-fixes: never propose "fixing" one of those.
3. **Reconcile the handoff against the ground truth** (the step everyone skips). The handoff is a claim; check each
   claim the brief will repeat:
   - "merged", "pushed", "nothing uncommitted" → the repo sections. A LOCAL ONLY commit or an uncommitted worktree
     the handoff does not mention goes in the brief: work that exists only on this disk.
   - **Each item in "Running"** → the background section. If it finished, read the last lines of its log and note
     the outcome: done, failed, timed out. Analyze results only once the user picks that task.
   - **Failing CI** (`CI red`) → `gh pr checks <n> -R <owner/repo>` for the failing job.
   - **Today's date and time** against deadlines (expiries, scheduled jobs, events). Anything due within a day goes
     first.
   - Before proposing a `BACKLOG.md` item, re-confirm it in the code: is it still broken or missing? If it is done
     already, say so and delete it at the handoff. A fix you *depend on*: spot-check that it still holds.
   - **Claims** → the claims section (`notes/item-format.md`, Claims), with the sessions running now: `ListAgents` says
     this session's name ("This session is <name>") and lists the others. A claim names its session by that name, so
     Claude sees at once who works on what: a claim whose session is listed is work in flight there. A claim kept by
     this session's handoff ("Unfinished") names the session before this one: this session takes it over when it goes on
     with that work (step 5). An item another session claimed is not proposed: it is taken. A claim marked ⚠ STALE,
     GONE, NOT HERE or NOT PUSHED goes in the brief: only the owner releases another session's claim.
   - **The checks** → the checks section: a ⚠ NO RECEIPT or a CI not green (the rule "merge": a default branch not
     checked since it last changed) or a ⚠ NO HOOK (the rule "receipt") goes in the brief, with the command the
     section names.
   - **A trim due** → the `questions.md` or `notes/lessons.md` section says `⚠ TRIM` (the file passed its own size in
     `.claude/ground-truth.conf`): the brief suggests `/trim`, in a session of its own, and trims nothing itself.
   - **Landed work**: an item whose work is pushed with its checks passed and CI green, or merged, is deleted now
     (the commit says where it landed) and named in the brief; the owner is not asked whether it is done. Not when its
     `Done when:` needs a trial or a decision the work did not give.
   - <!-- FILL: project-specific checks (a device, a server, a dashboard), and what is EXPECTED and not news
     (a main checkout that lags on purpose, patched build worktrees). Delete this item if there is none. -->
4. **Brief the user** in under about 25 lines:
   - **Since last session:** what finished or changed (jobs, CI, merged PRs), contradictions first.
   - **Left by the last handoff** (this session's, or the one that stands in for it, step 2), named by its id: its
     Next and its Unfinished, a line each, what is not an item too (a brainstorm, a leftover to delete, a branch),
     each with what became of it since (done, in Today, waiting). Each other live handoff: one line, its session and
     its Next.
   - **Today:** at most 3 items, time-sensitive first. Each with its id and title, its repo or area, its verified
     current state, one line on why now, and what "done" looks like. Default order when the user has no
     preference: work in flight, bugs users hit, decided-but-not-done (🟢), then deferred work.
     Items in different repos or `BACKLOG.md` sections can run side by side (one session or worktree each). An item
     marked ⚠ cross-repo runs alone, in its order (producer first, then each consumer). An item another session
     claimed is not on the list.
   - **Waiting for you:** the `questions.md` §1 items that block today's work, each with a recommendation, named by
     its id and by what the user sees (a screen's title, a command). These are never self-serve.
   - The board's path in one line: `Board: <path> (/board opens it; an open board updates itself)`.
   - End by recommending one task and asking which to start; if the row "Start the day's task after the brief" in
     CLAUDE.md ("What Claude does alone") is "do, then tell", end by naming the task you start.
5. **Claim the task when the work on it starts** (the user's yes, or the row "Start the day's task after the
   brief"), as the row "Claim an item" in CLAUDE.md allows:
   `bash .claude/skills/session-start/claim.sh <B-id> <branch> claude@<name>`. `<name>` is this session's name
   from `ListAgents` (the worktree's folder name where there is none). The branch is where the work goes
   (`feat/B-12-offline-list`, or the branch an earlier session pushed). Going on with a claim the handoff kept: add
   `--from <its agent@session>` to take it over. Exit 0: the item is yours, say so. Exit 1: another session claimed
   it first, the item is not on the remote yet (push a new item first, the row "Add an item to the backlog"), or it
   waits for its trigger (⏸️): tell the user, and propose another. Exit 2: nothing was claimed, say why.
6. **Follow "What Claude does alone"** in CLAUDE.md from here on: a row set to "ask first" (commit, push, PR, merge,
   release, comments, messages, …) waits for the user's yes. Reading and checking need no OK. The user decides the
   day's priorities, and the handoff can be stale: a task the user names comes before the Next list.
   **The rules** the checks section lists hold too, each repo's own where its line says "its own rules", else the
   project's: a repo with a gate is checked with
   `bash .claude/skills/session-start/gate.sh run <repo>`, which keeps its receipt; with "regression", a bug fix lands
   with a check that fails without the fix (seen red once, then green with it); with "merge", the default branch is
   checked again after a merge (its gate run on it, its CI green).

## Notes

- The brief is for a person: plain sentences. Every item, question, lesson or handoff it mentions is named by its id and
  title (`B-12 Shopping list works offline`), here and in every later answer, so the user can follow it on the board.
- If the ground truth contradicts the handoff (a job that failed, a branch never pushed), put it first and fix the
  handoff's claim when the session ends.
- Work started after the brief is recorded at the end of the session with `/handoff`.
