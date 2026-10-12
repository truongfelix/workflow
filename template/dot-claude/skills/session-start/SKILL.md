---
name: session-start
description: Start-of-session brief. Runs the ground-truth script (repos, worktrees, open PRs + CI, background jobs), reads notes/handoff.md and reconciles it against those facts, checks deadlines, then proposes the task of the day from the handoff, BACKLOG.md and questions.md. Use it at the start of every session, right after /clear, or whenever the user asks where things stand ("where are we", "what's next", "continue the work", "what's running", "resume", "start the day", "what did we do last time").
---

# Session start

Rebuild just enough context to pick the day's work, from the files and the machine alone: the last session's
conversation is gone. CLAUDE.md and the memory index are already loaded, so don't read them again.

The inverse of `/handoff`. Don't just execute the top item: tracker statuses drift in both directions (items still
open that already shipped, "done" items whose code changed since).

## Steps

1. **Ground truth first:** `bash .claude/skills/session-start/ground-truth.sh` (repos and their worktrees against
   the remote, LOCAL ONLY and uncommitted work, branches no worktree holds, open PRs with a CI verdict, background
   jobs; what it looks at is in `.claude/ground-truth.conf`). Exit 2 means a probe failed: that section is UNKNOWN,
   never "clean". An open PR is usually the active thread.
   Then `bash .claude/skills/session-start/items.sh check`: the format of the trackers and the lessons
   (`notes/item-format.md`). Exit 2
   lists each item that breaks it, with its line (a hand edit, or a merge that gave one id twice): that goes in the
   brief, and an id given twice is fixed before any work cites it.
2. **Read `notes/handoff.md`**: Next, Waiting for the user, Running, Last session.
   - If it is missing, or older than the latest activity in git or on GitHub, say so, and build the brief from
     `BACKLOG.md`, `questions.md` and the ground truth instead.
   - `notes/handoff-archive.md` holds the earlier handoffs: never read it whole; search it when the handoff or a
     question points there.
   - Beyond the Next list, open work is in `BACKLOG.md` and the user's open questions in `questions.md` §1. Read them
     when the Next list is done or the user asks for something else. `questions.md` §2 holds rulings and deliberate
     non-fixes: never propose "fixing" one of those.
3. **Reconcile the handoff against the ground truth** (the step everyone skips). The handoff is a claim; check each
   claim the brief will repeat:
   - "merged", "pushed", "nothing uncommitted" → the repo sections. A LOCAL ONLY commit or an uncommitted worktree
     the handoff does not mention goes in the brief: work that exists only on this disk.
   - **Each item in "Running"** → the background section. If it finished, read the last lines of its log and note
     the outcome: done, failed, timed out. Analyze results only once the user picks that task.
   - **Failing CI** (`CI RED`) → `gh pr checks <n> -R <owner/repo>` for the failing job.
   - **Today's date and time** against deadlines (expiries, scheduled jobs, events). Anything due within a day goes
     first.
   - Before proposing a `BACKLOG.md` item, re-confirm it in the code: is it still broken or missing? If it is done
     already, say so and delete it at the handoff. A fix you *depend on*: spot-check that it still holds.
   - <!-- FILL: project-specific checks (a device, a server, a dashboard), and what is EXPECTED and not news
     (a main checkout that lags on purpose, patched build worktrees). Delete this item if there is none. -->
4. **Brief the user** in under about 20 lines:
   - **Since last session:** what finished or changed (jobs, CI, merged PRs), contradictions first.
   - **Today:** at most 3 items, time-sensitive first. Each with its repo or area, its verified current state, one
     line on why now, and what "done" looks like. Default order when the user has no preference: work in flight,
     bugs users hit, decided-but-not-done (🟢), then deferred work.
     Items in different repos or `BACKLOG.md` sections can run side by side (one session or worktree each). An item
     marked ⚠ cross-repo runs alone, in its order (producer first, then each consumer).
   - **Waiting for you:** the `questions.md` §1 items that block today's work, each with a recommendation, named by
     what the user sees (a screen's title, a command), not by a code name. These are never self-serve.
   - End by recommending one task and asking which to start.
5. **Wait for the user's choice** before long work or anything outward (push, PR, merge, release, comments,
   messages). Reading and checking are fine. The user decides the day's priorities, and the handoff can be stale.

## Notes

- The brief is for a person: plain sentences, no internal IDs unless they help (PR numbers, paths, unit names do).
- If the ground truth contradicts the handoff (a job that failed, a branch never pushed), put it first and fix the
  handoff's claim when the session ends.
- Work started after the brief is recorded at the end of the session with `/handoff`.
