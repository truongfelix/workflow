# Adopt in a new project

The setup, step by step, written for the Claude session doing it (you can follow it by hand too). The owner starts it
with one sentence in a Claude Code session opened in the project: *Set up the workflow: follow
/path/to/workflow/SETUP.md*. Read [`PRINCIPLES.md`](PRINCIPLES.md) first; then:

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
2. **Choose where the docs live.** Ask the owner this, as a multiple-choice question that recommends neither: both
   are valid, and the owner knows what the folder holds or will hold. Ask it in these words (they follow the rule "A
   question to the owner" of `CLAUDE.md`), changing only what the owner has told you:
   > **Where should this project's notes and to-do lists live?**
   > 1. **With the code, in one repo.** The notes are saved in the same repo as your code. This is simpler. You can
   >    add other repos to the project later. The notes stay with that repo and can't be moved out afterwards.
   > 2. **In a separate repo of their own.** The notes get a private repo, and every code repo is attached to it. This
   >    takes one more repo to set up. Pick it if your code may become public and your notes must stay private. It
   >    also suits a project with several repos from the start.

   What the answer does: the first makes the project root the repo that holds the docs, committed with its code, and
   other repos are attached later with `attach.sh`. The second makes the root a folder that holds only the docs
   (CLAUDE.md, trackers, `notes/`, `.claude/`), with a whitelist `.gitignore` so the code repos inside it, data and keys
   stay out, and a PRIVATE remote; every code repo is attached to it.
3. **Install:** `bin/adopt.sh <project-root>` (add `--workspace` when the docs have their own repo). It copies only missing files,
   prints the ones it skipped with a diff command, and lists the FILL markers.
4. **Fill**, in this order. The owner has not read these files: all the setup says or writes for the owner (its
   questions, its summary at the end, the items it adds) is in plain words, with no preset name either, and each
   question follows `CLAUDE.md`'s rule "A question to the owner". Free text (what the project is, its rules) is an
   open question in the chat, never an option that only says "I'll type it", which returns no text when picked; a
   folder's name is not what the project is.
   - `CLAUDE.md`, **What Claude does alone**, first: the steps below follow it. Follow the `/autonomy` skill
     (`.claude/skills/autonomy/SKILL.md`): the owner picks a preset, with each step listed in plain words, then keeps
     it or picks the steps to switch. Its script sets the rows and deletes the FILL comment.
   - `.claude/ground-truth.conf`: one line per repo (the remote that counts as "pushed" is YOURS in a fork, not
     upstream), and KEEP_LOCAL for branches that must never be pushed. The docs repo is `.`, first in the list: give
     it a name in place of the template's `project` (the project's, or `docs` when the docs have a repo of their
     own). Attach every other repo with `bash .claude/skills/session-start/attach.sh <name> <path>`, which adds its
     line and writes its pointer (below), also later, whenever a repo joins the project; a repo attached later also
     gets its check (`/checks`) and its line in `CLAUDE.md` (what the project is, repos and layout), with the owner's
     answer to whether it is public. The line holds the repo's path relative to the project root when the repo is
     inside it or beside it (`../web`), so another machine with the same layout reads it as it is; a repo elsewhere
     gets its absolute path, a folder of this machine, in a tracked file. With the docs in the code's repo, the item
     and the notes about a private repo attached later are saved in that code repo: when that code may become public,
     tell the owner so before the item is written, and wait for a go-ahead. What `attach.sh` prints last is what is
     left (the repo's check, its line in `CLAUDE.md`) and, for a repo outside the project's folder, what to tell the
     owner: allow the import at the first session opened there, and run `attach.sh` again on another machine (below).
   - How the code is checked before a merge: follow the `/checks` skill (`.claude/skills/checks/SKILL.md`): the
     project's own check, GitHub CI, both or nothing yet, each repo's check command, and the rules kept. It sets
     their lines in `.claude/ground-truth.conf` and installs the hook that holds the release rule.
   - Delete the two FILL lines at the top of `.claude/ground-truth.conf`, then run
     `bash .claude/skills/session-start/ground-truth.sh` until it ends with `GROUND TRUTH: complete`.
   - The rest of `CLAUDE.md`: what the project is, who owns it (ask: a commit's author is only a guess), what is
     public and what must stay private, repos and layout (where worktrees go: beside their repo, `<repo>-<topic>/`,
     unless the owner says otherwise), commands (what a release publishes besides its tag, too), and the project's
     rules. A rule is
     what Claude must always or never do in this project ("greet.sh stays plain bash", "never touch `migrations/`",
     "a change is done when `make test` passes"). Ask the owner with such examples, and say that it is not the table
     above and that none is fine: rules come as the project meets them. Move any existing to-do list out of
     `CLAUDE.md` into `BACKLOG.md`.
   - `BACKLOG.md`: one section per repo or file tree, filled from what the project already tracks (issues, notes, an
     old TODO). Each item in the shape of `notes/item-format.md`: an id from `next id`, what is wrong or missing, a
     pointer, `Done when:`. An old to-do file whose lines are now items: ask the owner whether to delete it (git keeps
     it); it is not the docs, so a commit that deletes it is pushed as code (the table's rows for code).
   - `questions.md`: decisions the owner still has to make, and rulings already made that a newcomer would undo,
     in the same shape. Then `bash .claude/skills/session-start/items.sh check` until it exits 0.
   - The skills' FILL item (project-specific checks, what is expected and not news).
   - `.claude/settings.json`, only when `adopt.sh` listed it as skipped (the project had its own): add the
     template's `PostToolUse` hook to it, which rebuilds the board after each change. When `adopt.sh` installed it,
     the hook is there and there is nothing to do or report.
5. **Commit and push the setup**, in either shape. Stage the setup's paths by name (`git add <paths>`, never `-A`)
   and read the staged list (`git diff --cached --name-only`). Docs in a repo of their own: at the root, the repo of
   step 1, check `git status --ignored` too; never track a datadir, a key or a binary. Scan the staged files for
   secrets: `gitleaks git --staged` (gitleaks 8.19 and later; before: `gitleaks protect --staged`). Commit, then push
   to the remote of step 1 as the table allows: the setup's files are the docs. Then run each repo's own check once on
   its default branch, `bash .claude/skills/session-start/gate.sh run <repo>` for each repo of `GATES`: a receipt is
   for a commit, so none could be kept before this one, and with the rule "merge" the ground truth flags a default
   branch that has none. A check that fails is the first thing to tell the owner.
6. **Close the loop:** run `/handoff` once, so the first handoff (`notes/handoff/<session>.md`) is written from the
   ground truth. The setup itself is no backlog item, as there was no backlog before it: the first handoff names it
   under Done, with no id. Then end the setup with one sentence for each skill, when to use it and what it is for:
   `/session-start` when you sit down (it checks git and the machine, reads the last handoff and proposes the day's
   task), `/handoff` before you stop or switch machines (it records where things stand, so the next session picks
   up from there), `/board` whenever you want to see the work (the backlog, your decisions, the lessons and the
   handoffs as one page), `/autonomy` whenever you want Claude to ask you more or less often (it shows each step
   and what Claude does there, and changes the ones you pick), `/checks` when the way the code is checked changes (a
   first test command, GitHub CI added, a rule kept or dropped), `/trim` when the brief says a trim is due (it proposes
   what to keep, shorten, move or delete in your rulings and lessons, and you decide).

Existing project with its own session docs: adopt anyway (it overwrites nothing but its version file), then merge by
hand, keeping the project's content and the template's structure.

## A session opened in a code repo

A session finds the project's rules in the `CLAUDE.md` of the folder it is opened in and of the folders above it. A code
repo inside the docs repo's folder is covered by the docs' `CLAUDE.md` above it; a repo elsewhere on the disk, or any
repo whose own `CLAUDE.md` loads alone, is not. So `attach.sh` writes a **pointer** in each attached repo: a short
`CLAUDE.md` (or `CLAUDE.local.md`, when the repo has a `CLAUDE.md` of its own, which is left alone) that says where the
docs are, to start the session there, and, for a repo outside the docs repo's folder, imports the docs' `CLAUDE.md` so its
rules load too (inside the folder they load already). It is kept out of the
repo's commits (`.git/info/exclude`), since it names a path on this machine, and `ground-truth.sh` reports an attached repo
that has none (`NO POINTER`). The first time a session opens in a repo outside the folder, after asking whether you
trust the folder, Claude Code asks whether to allow that import, files outside the repo (the docs' lessons too):
allow it. It keeps the answer for that folder and never asks again (`hasClaudeMdExternalIncludesApproved` in
`~/.claude.json`), and a session that cannot ask (`claude -p`, a script) loads the import only where an interactive
session allowed it. Where it did not load, the pointer tells the session to read the docs' `CLAUDE.md` and its imports
before any work, or to stop and say so when it cannot: an interactive session reads them (asking you first when its
permission mode does), and `claude -p` reads them with `--add-dir <the docs folder>`.

Two limits. The pointer exists on the machine where `attach.sh` ran: a clone on another machine needs the script run
again there. And a cloud session works on one repo, so it cannot work on a project with several: the docs repo and the
code repos are cloned side by side only on your own machines.
