---
name: checks
description: Show and change how the code is checked before a merge in this project - by its own check (a command whose exit code says the code is ready, such as its tests, run on this machine), by GitHub CI, both, or nothing yet - with each repo's check command and the rules kept (a release needs a pass on its exact commit, each bug fix comes with a check that fails without it, the main branch is checked again after a merge). Use it when the user types /checks, asks how the code is checked or wants it changed ("use GitHub CI as the check", "our tests are make check", "stop checking releases"), when a project gets its first test command, and at setup (README, "Adopt in a new project", step 4).
---

# Checks

How the code is checked before a merge is the owner's choice, in `.claude/ground-truth.conf`: by the project's own
check, its gate (`GATES`: each repo's command, run by `gate.sh run`, which keeps a receipt of each commit that
passed), by GitHub CI (`GITHUB_CI`: the repos whose CI on GitHub counts), both, or nothing yet (both empty). The
rules kept (`GATE_RULES`) hold for whichever checks a repo, and the board shows only what applies. A repo can keep
other rules than the project's (`REPO_RULES`: its own list, which replaces `GATE_RULES` for that repo alone). This
skill shows those lines and changes them with the owner's answers.

Ask as `CLAUDE.md`'s rule "A question to the owner" says. The gate is "the check that says the code is ready" (its
tests), never a bare "gate".

## Steps

1. **Read** `REPOS`, `GATES`, `GATE_PASS`, `GITHUB_CI` and `GATE_RULES` and `REPO_RULES` in `.claude/ground-truth.conf`, then look in
   each code repo for what it already has: a `.github/workflows/` folder (GitHub CI), a test command or a local CI
   script (its own check). Outside setup, say in a few lines what checks each repo now and the rules kept (each as
   its sentence in step 4), then ask: keep it as it is, or change it.
2. **How is the code checked:** "How is your code checked before a merge?", four options, the one the repos already
   have recommended:
   - *Its own check:* a command run on this machine, such as its tests; a release needs it to have passed here.
   - *GitHub CI:* the checks GitHub runs on each push and pull request, read with `gh` (installed and logged in).
   - *Both:* both must pass.
   - *Nothing yet:* no check exists (a new project). No rule holds; run this skill again once there is one.

   One answer for every code repo of a workspace (never its docs repo), unless the owner says they differ.
3. **Its own check, for each repo:** the command found in step 1, in a question of its own: "Is `<command>` the check
   that says the code is ready?" (another one is typed in the chat). A local CI script the project already has is
   that command: from then on it runs through `gate.sh run`, never beside it, so one run gives both records, and the
   workflow never reads the script's own. A script that exits 0 once it has run, green or not (stages skipped, a
   partial run), says it passed in a line it prints: ask "How do I know it passed: its exit code, or a line it
   prints?", and set that line in `GATE_PASS`.
4. **The rules** (not with nothing yet), one question where the owner picks any or "None of these", each rule
   (`receipt`, `regression`, `merge`) in the plain words `rule_text` gives in `.claude/skills/session-start/lib.sh`,
   as the board's Settings tab shows them. Name no preset: Production, Steady and Prototype are what the ground truth
   and the board call the result. This is the project's rules, for every repo. Then, when the project has more than one
   code repo: "Does any repo keep other rules than these?", and for each one the owner names, the same question for that
   repo alone; a repo the owner does not name follows the project's. A repo the owner changes later is changed alone.
5. **Write** the four lines, each repo by its name in `REPOS`: `GATES=("api|make check")`, `GATE_PASS=("api|^All
   checks passed")`, `GITHUB_CI=("api")`, `GATE_RULES="receipt regression merge"`; nothing yet empties all four. A repo with rules of its own gets an entry in
   `REPO_RULES=("docs|" "web|regression merge")` (an empty list: it keeps none); a repo given the project's rules again
   loses its entry.
   With `receipt` kept for a repo (its own rules, else the project's), run `bash .claude/skills/session-start/gate.sh hook
   <repo>` for each such repo checked. Exit 1: the repo
   has a pre-push hook of its own; add the lines printed to it, with the owner's yes.
6. **Verify:** `bash .claude/skills/session-start/ground-truth.sh --no-fetch`, its section `== checks`. A ⚠ NO
   RECEIPT goes away with `gate.sh run <repo>` on the default branch, once committed (a receipt is for a commit: at
   setup, after the setup's commit); a ⚠ CI that is not green is news for the owner;
   an UNKNOWN on CI means `gh` cannot read it (not installed, not logged in, no GitHub repo): fix that, or drop GitHub
   CI for that repo.
7. **Say what changed** in plain words, and commit `.claude/ground-truth.conf` as the row "Commit the docs" says,
   then push as "Push the docs" says. At setup, the setup commits it with the rest.
