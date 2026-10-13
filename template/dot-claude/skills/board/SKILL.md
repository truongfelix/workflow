---
name: board
description: Open the board, the trackers (BACKLOG.md, questions.md), the lessons and the handoffs as one page, with filters by repo, state, date and text, the closed items, and the commits and PRs behind each item, and a Settings tab (what Claude does alone, how the code is checked). Where no browser can show it (a cloud session, SSH, no display), print the open items as text instead. Use it when the user asks for the board, or to see the backlog, the open items or what is in flight at a glance ("show the board", "open the backlog", "what's open").
---

# Board

1. Run `bash .claude/skills/session-start/board.sh` (add what the user asked for: `--offline` to skip GitHub,
   `--text` for the open items as text too). It rebuilds the page from the trackers and git, reads the PRs, then:
   - opens it in the browser of this machine;
   - where no browser can show it, prints the open items as text and how to open the page from a clone.
2. Tell the user in a line or two: the page's path (`Board: …`), and that an open board tab updates itself after each
   change (the hook in `.claude/settings.json` rebuilds the page), so there is no need to open it again. A text
   board goes to the user as printed, not summarized.
3. Exit 2 (UNKNOWN): say what the script printed; there is no page. Problems in the trackers are on the page, not
   errors: name their count and `bash .claude/skills/session-start/items.sh check`.
