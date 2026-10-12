# Principles — why each piece exists

Each rule here was paid for: a session that acted on a stale tick, a check that kept passing after it had stopped
checking, work that existed only on a disk that died. Cite a principle by its title.

## The session loop

**Every session starts from zero.** The next session sees the repo, CLAUDE.md and the memory index, nothing else.
The contract: a fresh clone plus the trackers is enough to resume, with no verbal context. `/handoff` writes that
state; `/session-start` reads it.

**Claims and facts are different things.** The handoff and the trackers are claims written by a past session. Git,
GitHub and the machine are facts. `ground-truth.sh` prints the facts, both skills run it, and a contradiction is
reported first. Writer and reader share one script so they cannot see different pictures.

**Ticks age in both directions.** An item still marked open may have shipped; a "done" item's code may have changed
since; a "pushed" branch may never have reached the remote. Re-confirm a claim in the code before acting on it or
repeating it to the owner.

**Propose, then wait.** The session brief ends with a recommendation and a question. The owner sets the day's
priorities; the handoff can be stale. Reading and checking need no permission; long work and outward actions do.

## The trackers

**One place for each kind of information.** Today's tasks and running jobs: the handoffs. Open work:
`BACKLOG.md`. Owner decisions and rulings: `questions.md`. Rules and how-tos: `CLAUDE.md`. History: git. When the
same fact lives in two places, one of them goes stale and still reads as authoritative.

**Finished work is deleted, not ticked.** A done entry rots while reading as true, and a list of done entries buries
the open ones. Git keeps the narrative with dates. That is also why the docs of a multi-repo workspace must be a
git repo: pruning is only safe when the history is kept.

**Live, git, distilled.** One short live file beats an ever-growing log. At each handoff the old live file is
replaced, and git keeps it word for word, but only after it is distilled: each lesson still true is promoted to
where it acts, each still-live item carried forward. Nobody reads the history whole, so a lesson left only there is
lost. No archive file copies what git already holds: a copy can disagree with its source, and two sessions adding
to one file at once conflict.

**One handoff per session.** Two sessions working at once each write their own handoff, so neither overwrites the
other's. Each task in it starts with the id of its item: the handoff orders the trackers and holds no work of its
own, so nothing waits in a place the trackers do not show.

**Lessons stay with the project that learned them.** A lesson comes from one project's tools, owner and machines, so
it goes into that project's `notes/lessons.md` and travels with its repo. The workflow carries no lessons: it stays
independent of any project, session, machine or owner.

**Cut the backlog along file trees.** One section per repo or tree, so parallel sessions or worktrees each take a
section and merge cleanly. An item that spans trees is marked ⚠ and runs alone, producer first.

**Decisions are never self-serve.** An owner question carries the options and a recommendation, and names things by
what the owner sees (a screen's title), not by a code name the owner never saw. A list of concrete choices gets
answered; a vague "what do you think about X" does not.

**Record deliberate non-fixes.** A ruling not written down is "rediscovered" as a bug by the next session, or a
private branch is "rescued" with a push. `questions.md` §2 and the ground truth's KEEP_LOCAL exist for that.

**Cite by id, never by position.** Every tracker item has an id that never changes and is never reused (`B-12`,
`Q-4`); its place in a list moves, and its title gets reworded. Give the title next to the id, for the reader. One
shape for every item (`notes/item-format.md`) is what lets a person, Claude and a script read the same trackers.

## Verification

**A document is not a gate.** If a check must hold, it is a script with an exit code that the gate runs. A skill or a
paragraph is a procedure someone may skip, and an agent told to run a documented check that does not exist has every
reason to report it as done.

**An unreadable result is UNKNOWN, never a pass.** A parser that dies prints nothing, which reads as "found nothing".
Distinguish empty from broken, and cross-check against the tool's own exit code.

**Never key a verdict on English words.** Test output is full of "failed" and "passed" in passing tests. Match the
emitter's own marker (a line prefix only the runner prints).

**Never pipe a gate into `head` or `tail`.** The exit status becomes the pager's. Write the real status into the log
(`cmd > log 2>&1; echo "REAL_EXIT=$?" >> log`) and read it from there.

**Wait on an artifact, never on a name.** `pgrep -f` matches the watcher's own command line, so a finished run looks
like a running one forever. Key the end of a background job on a line it writes, or on a PID captured at launch.

**Prove a check can fail.** Run it once against a control where it must go red (a virgin database, a bare clone, a
stale install). Production passes either way, so a green there proves nothing.

**Measure before proposing.** Estimates of CPU, storage or scaling get rejected; a sampled experiment with a control
settles the question in one reply.

## Working tree and machine

**Nothing exists only on one disk without being named.** Uncommitted work and local-only commits are either
committed and pushed (a `wip:` commit says what is unfinished) or listed in the handoff with their path. Uncommitted
work on a dead laptop does not exist.

**Stage the paths you touched.** `git add -A` sweeps in whatever the owner dropped into the tree; a clean status
afterwards cannot catch it, because it is clean BECAUSE everything was staged.

**Outward actions need an OK, one at a time.** Push, PR, merge, release, comments, messages. Approval for one does not
extend to the next.

**Background jobs must be findable.** Launch long jobs as named transient units (`systemd-run --user --unit <name>`)
so the ground truth lists them, and record each one in the handoff's Running table with how to check and stop it.

**Share the machine politely.** Cap heavy runs (`nice -n 19`, a cgroup memory cap), never kill by name match, and
check the other workloads after a heavy run.
