# workflow — Claude Code sessions that pick up where the last one left off

[![test](https://github.com/truongfelix/workflow/actions/workflows/test.yml/badge.svg)](https://github.com/truongfelix/workflow/actions/workflows/test.yml)

Every Claude Code session starts with an empty context. The usual fix is a notes file that the agent updates at the
end of the day and reads the next morning. It works until the notes are wrong: a branch marked "pushed" that never
reached the remote, a job "still running" that died at 1 a.m., a to-do that shipped last week. The next session
believes them and builds on them.

This template keeps a project going across sessions, machines and weeks with four skills and a script:

- **`/session-start`** runs `ground-truth.sh`, which reads the facts from git, GitHub and the machine: every repo and
  worktree against its remote (or the branch it tracks on another one), open PRs and their CI, the items other
  sessions claimed and their branches, background jobs. Then it reads the last handoff, reports where the two
  disagree, proposes the day's task, and waits for you (or starts it, if you told it to). When an agent starts working
  on the task, it claims it: `claim.sh` pushes a `claimed:` line that names the agent, so two sessions in parallel
  never take the same item.
- **`/handoff`** runs the same script, rewrites the handoff from it, updates the trackers (open work, your pending
  decisions, lessons learned), and commits. When `questions.md` grows past a size you set, it goes through the
  rulings with you: keep, shorten, move to its doc, or delete (git keeps it).
- **`/board`** opens the trackers, lessons and handoffs as one page, with filters and each item's history, and for
  each claimed item where its work is (on which machine, pushed or not, in an open PR with its CI, or merged) and
  whether it passed the project's own gate on this machine. A hook rebuilds it after each change, and an open tab
  updates itself. Where no browser can show it (a cloud session, SSH), it prints the open items instead.
- **`/autonomy`** shows what Claude does without asking you, step by step (commit, push, open or merge a PR,
  release, …), and changes it: a preset, or the steps you pick from a list.

The handoff is a claim; the script is the fact. Both skills run the same script, so the session that writes the
note and the session that reads it look at the same picture.

## What it looks like

Monday morning, `/session-start` on a project whose last session ended on Friday:

```text
Since last session (Fri 9 Oct, 18:40)
- ⚠ The ingredient backfill failed on Saturday at 01:12, at batch 212 of 340: "No space left on
  device" on /var/lib/pantry. The handoff expected it to finish around 03:00.
- ⚠ web: feat/offline-list has 2 commits that were never pushed (Fri 19:05 and 19:20, after the
  handoff). The handoff calls the branch pushed and the edit queue "not started": those commits
  are the queue and its replay.
- ⚠ web: spike/pwa-cache exists only on this laptop, and no note mentions it.
- api: PR #41 (unit conversion) is CI RED: test_round_to_5g, a pinch of salt rounds to 0 g.
- #39 (search by ingredient) is merged, as the handoff says.

Today
1. [api] Fix the rounding in #41 so small quantities keep at least 1 g. Thursday's release needs
   it. Done when CI is green and you have merged it.
2. [ops] Free space on /var/lib/pantry and resume the backfill from batch 212. Done when the
   unit exits 0 and 20 recipes check out on staging.
3. [web] Push the 2 commits, then finish "Shopping list works offline": conflict handling and
   the phone test are left.

Waiting for you
- "Metric only on the shopping list?" I recommend metric only: it matches #41, and a switch can
  come later.
- spike/pwa-cache: push it, keep it local on purpose, or delete it?
- "Import rejects recipes with no yield" was claimed on 1 Oct by another session (api-yield-3),
  and its branch has had no commit since: release it, so a session can take it?

I'd start with 1: it is small, and the release waits on it. Which one?
```

A session that trusted Friday's note alone would have asked for a red PR to be merged, reported the backfill as
done, and rewritten code that already existed. The whole scenario, with every file behind this brief and the
script's output, is in [`example/`](example/).

## Quick start

You need bash, git and a remote for your project (on GitHub or any git host): the workflow keeps its state in git.
Optional: the GitHub CLI `gh` (open PRs and CI) and systemd (background jobs, Linux only).
Runs on Linux, macOS and Windows: in Git Bash, which Claude Code uses on Windows, or in WSL. CI tests all three.

```bash
git clone https://github.com/truongfelix/workflow.git
workflow/bin/adopt.sh ~/code/my-project     # copies the template; never overwrites a file
```

Then open Claude Code in your project and ask:

> Set up the workflow: follow "Adopt in a new project" in /path/to/workflow/README.md

Claude first asks for your project's git remote, then what it may do without asking you (commit, push, open a PR,
merge, …: a preset, then any change), then fills in the blanks (what the project is, its repos, its rules), runs
the ground truth until it comes back clean, and runs `/handoff` once to write the first handoff. You change any of
those answers whenever you want, in words ("from now on, push the docs without asking") or with `/autonomy`. From
then on: `/session-start` when you sit down, `/handoff` before you stop, `/board` whenever you want to see the work
at a glance.

## What you get

```
session N:   /session-start ──► work ──► /handoff
                   ▲                         │
                   └──── git (trackers) ◄────┘   ← session N+1, any machine or cloud session
```

| file | holds |
|---|---|
| `notes/handoff/<session>.md` | today, one file per session: next tasks, what waits for you, what runs in the background, what is unfinished, done and learned. Short, rewritten at each handoff; earlier ones are in git |
| `BACKLOG.md` | open work only, one section per repo, each item with an id (`B-12`) that never changes. A finished item is deleted, not ticked: git keeps the history |
| `questions.md` | decisions only you can make, each with options and a recommendation; past rulings, so no session "fixes" them. Ids too (`Q-4`) |
| `notes/item-format.md` | the one shape of every item in both trackers and the lessons, and how a new item gets its id |
| `notes/handoff-format.md` | the one shape of a handoff, with its id (`H-12`) |
| `notes/lessons.md` | what the project learned the hard way, loaded into every session. Ids too (`L-3`) |
| `CLAUDE.md` | what the project is, what Claude does without asking you, its rules and commands. No to-dos, no history |
| `.claude/ground-truth.conf` | the repos the script checks, branches that must never be pushed, when a claim is stale, when `questions.md` needs a trim, each repo's gate (the command that says the code is ready, such as its tests) and the gate rules you keep |
| `.claude/skills/` | `/session-start` (with `ground-truth.sh`; `items.sh`, the parser and format check of the trackers, lessons and handoffs, whose `show <id>` prints any item, live or from git; `claim.sh`, which takes an item for a session, on its branch and machine; `gate.sh`, which runs a repo's gate and keeps a receipt of each commit that passed it; `board.sh`, the trackers, lessons and handoffs as one page, with the commits and PRs behind each item and where the work of each claimed item is), `/handoff` and `/board` |
| `.claude/settings.json` | the hook that rebuilds the board after each change to the trackers or the git history |

It fits a single repo, or a workspace folder holding several repos (a fork, an app, a backend) with a docs repo of
its own at the root. How Claude Code's machine-local memory fits next to these files: [`memory/README.md`](memory/README.md).

## The ideas behind it

[`PRINCIPLES.md`](PRINCIPLES.md) explains why each piece exists. Every rule in it comes from something that went
wrong. A few:

- **Claims and facts are different things.** A note written by a past session is a claim. Check it against git and
  the machine before acting on it or repeating it.
- **Finished work is deleted, not ticked.** A done entry rots while it still reads as true, and it buries the open
  ones. Git keeps the history.
- **An unreadable result is UNKNOWN, never a pass.** A check that crashes prints nothing, which reads as "found
  nothing". The script says UNKNOWN and exits 2.
- **Nothing exists only on one disk without being named.** Uncommitted work on a dead laptop does not exist.
- **Propose, then wait.** The session recommends; you pick the day's work.
- **Only approved items are built.** A new idea or a bug met on the way becomes a backlog item first, and is built
  once you approve it. So the backlog does not drift: it stays the whole list of the work.
- **You choose what Claude does alone.** One table: for each step (the day's task, commit, push, PR, merge, release,
  messages), ask you first, or do it and tell you. Set at setup, changed whenever you say so.

## Adopt in a new project

The detailed steps, written for the Claude session doing the setup (you can follow them by hand too). Read
`PRINCIPLES.md` first; then:

1. **Get the workflow:** a clone of this repo on the machine. **Then a git remote, before any other question:** the
   workflow does not work without one (the ground truth compares each branch with it, a claim is a push to it, and
   the next session, on any machine, starts from what it holds). Ask the owner for the remote this folder is pushed
   to (a private one if the folder will hold other repos: step 2). A folder that is not a git repo yet gets
   `git init`; with no remote yet, offer to create one (`gh repo create <name> --private`) and wait for the
   owner's yes. Set it as `origin`. On GitHub, before the first commit: GitHub refuses a push whose commits show an
   email address the owner keeps private. Unless `git config user.email` is already a `users.noreply.github.com`
   address, ask: "GitHub can refuse pushes that show your email address. Use your GitHub no-reply address as this
   project's commit email?" On a yes, set it for this repo alone (another clone needs the same line):
   `git config user.email "$(gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"')"`
2. **Choose the shape.** Ask the owner which one, as a multiple-choice question that recommends neither: both are
   valid, and the owner knows what the folder holds or will hold.
   - *One repo:* the project root is the repo; the trackers are committed with the code.
   - *Multi-repo workspace:* a folder holding several code repos (forks, an app, a backend). The root becomes a
     docs-only repo of its own (CLAUDE.md, trackers, `notes/`, `.claude/`), with a whitelist `.gitignore` so the
     nested repos, data and keys stay out, and a PRIVATE remote.
3. **Install:** `bin/adopt.sh <project-root>` (add `--workspace` for the second shape). It copies only missing files,
   prints the ones it skipped with a diff command, and lists the FILL markers.
4. **Fill**, in this order. The owner has not read these files: all the setup says or writes for the owner (its
   questions, its summary at the end, the items it adds) is in plain words, with no file, table, setting or preset
   name, and a question says what each choice does. The gate is "the check that says the code is ready" (its tests),
   never a bare "gate". Free text (what the project is, its rules) is asked in the chat, as an open question: never an
   option that only says "I'll type it", which returns no text when picked. A question that fails, or a free-text one
   left unanswered, is asked again in the chat: never write an answer the owner did not give (a folder's name is not
   what the project is). A question where the owner can pick several has an option "None of these": with nothing
   picked, it returns no answer at all, which reads as a skip.
   - `CLAUDE.md`, **What Claude does alone**, first: the steps below follow it. Follow the `/autonomy` skill
     (`.claude/skills/autonomy/SKILL.md`): the owner picks a preset, with each step listed in plain words, then keeps
     it or picks the steps to switch. Its script sets the rows and deletes the FILL comment.
   - `.claude/ground-truth.conf`: one line per repo (the remote that counts as "pushed" is YOURS in a fork, not
     upstream), and KEEP_LOCAL for branches that must never be pushed.
   - Run `bash .claude/skills/session-start/ground-truth.sh` until it ends with `GROUND TRUTH: complete`.
   - The gate, in `.claude/ground-truth.conf`: `GATES`, each repo's gate command (the one whose exit code says
     "ready": a test script, `make check`, what CI runs). Look for it in the repo, then ask the owner about it in a
     question of its own: "Is `<command>` the check that says the code is ready?" A local CI script the project
     already has (one that runs its checks, maybe keeping its own record of passes) is that command: from then on it
     runs through `gate.sh run`, never beside it, so one run gives both records, and the workflow never reads the
     script's own. A project with no such check yet (a new one) has no gate: say so and skip the rest of this
     bullet; this step runs again when the project has one.
     With a gate, ask which rules to keep, as one question where the owner picks any or "None of these", each rule a
     plain sentence: "A release needs this check to have passed on its exact commit" (`receipt`), "Each bug fix comes
     with a check that fails without the fix" (`regression`), "After a merge, the check runs again on the main branch"
     (`merge`). Name no preset: Production, Steady and Prototype are what the ground truth calls the result, not
     options to explain. Set `GATE_RULES`; with `receipt`, run `bash .claude/skills/session-start/gate.sh hook <repo>`
     for each repo with a gate.
   - The rest of `CLAUDE.md`: what the project is, repos and layout, commands, and the project's rules. A rule is
     what Claude must always or never do in this project ("greet.sh stays plain bash", "never touch `migrations/`",
     "a change is done when `make test` passes"). Ask the owner with such examples, and say that it is not the table
     above and that none is fine: rules come as the project meets them. Move any existing to-do list out of
     `CLAUDE.md` into `BACKLOG.md`.
   - `BACKLOG.md`: one section per repo or file tree, filled from what the project already tracks (issues, notes, an
     old TODO). Each item in the shape of `notes/item-format.md`: an id from `next id`, what is wrong or missing, a
     pointer, `Done when:`.
   - `questions.md`: decisions the owner still has to make, and rulings already made that a newcomer would undo,
     in the same shape. Then `bash .claude/skills/session-start/items.sh check` until it exits 0.
   - The skills' FILL item (project-specific checks, what is expected and not news).
   - `.claude/settings.json`, only when `adopt.sh` listed it as skipped (the project had its own): add the
     template's `PostToolUse` hook to it, which rebuilds the board after each change. When `adopt.sh` installed it,
     the hook is there and there is nothing to do or report.
5. **Workspace shape only:** at the root, the repo of step 1, check `git status --ignored` and the staged list
   before the first commit; scan for secrets (`gitleaks`); never track a datadir, a key or a binary. Push to the
   remote of step 1 as the table allows.
6. **Close the loop:** run `/handoff` once, so the first handoff (`notes/handoff/<session>.md`) is written from the
   ground truth. Then end the setup with one sentence for each skill, when to use it and what it is for:
   `/session-start` when you sit down (it checks git and the machine, reads the last handoff and proposes the day's
   task), `/handoff` before you stop or switch machines (it records where things stand, so the next session picks
   up from there), `/board` whenever you want to see the work (the backlog, your decisions, the lessons and the
   handoffs as one page), `/autonomy` whenever you want Claude to ask you more or less often (it shows each step
   and what Claude does there, and changes the ones you pick).

Existing project with its own session docs: adopt anyway (nothing is overwritten), then merge by hand, keeping the
project's content and the template's structure.

## Upgrade a project from here

`bin/adopt.sh <project-root>` again lists every skipped file with its `diff -u` command against the current
template. Merge the generic parts; keep the project's FILL answers. `.claude/workflow-version` records which release
the project last took, as the releases page names it: `v1.0.0`, or `v1.0.0-3-gabc1234` three commits after it.

From 1.x: the trackers' items and the lessons moved from bullets cited by title to one shape with ids, and the one
`notes/handoff.md` with its archive became one handoff per session, with git as the archive
(`notes/handoff-format.md`, "Moving a project to it"). `adopt.sh` installs the new
`notes/item-format.md`, and its last section, "Moving a project to it", is the conversion, done once;
`.claude/skills/session-start/items.sh check` lists what is left. In `CLAUDE.md`, the "outward actions" rule and the
handoff rule became the table "What Claude does alone": copy it from the template, every row "ask first", then set
what the old handoff rule allowed to "do, then tell" (the docs: "Commit the docs" and "Push the docs"; everything:
"Commit code" and "Push a work branch" too), and ask the owner about the other rows.

`/handoff` gained a trim pass of `questions.md` (step 3), set by `QUESTIONS_TRIM_LINES` in `ground-truth.conf` (150
lines when the line is missing): merge the skill by hand, and add the line to set another size.

## Improve the workflow

When a project's session improves a generic piece (a skill step, a ground-truth check, a principle learned the hard
way), port the generic part back here in its own commit, with the reason. Project-specific content never comes back
here, and neither do lessons: a lesson stays in the `notes/lessons.md` of the project that learned it.

## Layout of this repo

```
template/                     copied into a project's root by bin/adopt.sh
  CLAUDE.template.md          skeleton with FILL markers, installed as CLAUDE.md
  BACKLOG.md  questions.md  notes/lessons.md
  notes/handoff/README.md     the handoffs' folder, one file per session, and their next id
  notes/item-format.md        the shape of a tracker item and its id
  notes/handoff-format.md     the shape of a handoff
  dot-claude/                 installed as .claude/
    ground-truth.conf         what the ground truth looks at: the project's repos, gates and gate rules
    settings.json             the hook that rebuilds the board after each change
    skills/session-start/{SKILL.md,ground-truth.sh,items.sh,claim.sh,gate.sh,board.sh}
    skills/handoff/SKILL.md
    skills/board/SKILL.md
    skills/autonomy/{SKILL.md,autonomy.sh}
workspace/gitignore           whitelist .gitignore for a multi-repo workspace's docs repo
bin/adopt.sh                  installs the template, never overwrites, lists what is left to FILL
example/                      a filled-in project, and the brief /session-start gave on it
test/run.sh                   tests adopt.sh, ground-truth.sh, items.sh (show too), claim.sh, gate.sh, board.sh, autonomy.sh and the table "What Claude does alone"; CI runs it on Linux, macOS and Windows
test/fixtures/broken/         trackers, lessons and a handoff that break their format in every way items.sh reports
test/fixtures/two-sessions/   two sessions' handoffs that pass the check
memory/README.md              how the memory layer is used
PRINCIPLES.md                 the why
```

`CLAUDE.template.md` and `dot-claude/` get their real names only in a project. Under those names, Claude Code
would load them (and the example's `CLAUDE.example.md`) as instructions and skills in a session working on this
repo.

The skills, their scripts and `notes/item-format.md` hold no project data, so a project can upgrade them from
here. Project data lives in `ground-truth.conf`, `CLAUDE.md`, the trackers and the other notes. Nothing here
depends on a machine, a session or an owner.

## License

MIT, see [`LICENSE`](LICENSE).
