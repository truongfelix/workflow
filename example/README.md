# Example: a project on Monday morning

Pantry is a made-up project: a self-hosted recipe box, two weeks after it adopted the workflow. It is a workspace
holding two code repos, `api/` and `web/`, with a docs repo at its root. This folder is that docs repo as Friday's
session left it, then what happened on Monday at 09:14 when a new session ran `/session-start`.

Read in this order:

1. [`notes/handoff.md`](notes/handoff.md): what Friday's `/handoff` wrote at 18:40.
2. [`ground-truth-output.txt`](ground-truth-output.txt): what `ground-truth.sh` found on Monday.
3. [`session-start-brief.md`](session-start-brief.md): what Claude told the owner.

Between Friday evening and Monday, three things happened that the handoff could not know: the backfill job ran out
of disk at 01:12 on Saturday, the owner kept working after the handoff and committed twice without pushing, and CI
went red on the open PR. One more thing was never in any note: a spike branch that existed only on the laptop.

The other files are the trackers as they stand:

| file | shows |
|---|---|
| [`BACKLOG.md`](BACKLOG.md) | open work cut by repo, each item with its id; a ⏸️ item waiting on a trigger, a ⚠ cross-repo item |
| [`questions.md`](questions.md) | an open decision with options and a recommendation; two rulings, one of them a branch that must never be pushed |
| [`notes/lessons.md`](notes/lessons.md) | lessons promoted from earlier handoffs, each with its id; the handoff cites one |
| [`notes/handoff-archive.md`](notes/handoff-archive.md) | Thursday's handoff, archived after its "Learned" line went into `lessons.md` |
| [`CLAUDE.example.md`](CLAUDE.example.md) | the template's `CLAUDE.md`, filled in (renamed here, so that Claude Code does not load Pantry's rules in a session working on the workflow) |
| [`.claude/ground-truth.conf`](.claude/ground-truth.conf) | the two repos, and the branch kept local on purpose |

The skills, the script and `notes/item-format.md` are the template's, unchanged, so they are not repeated here.

The ground-truth output is real: it comes from repos built to match this story. Only the open-PR lines and the
background unit were written by hand, in the script's format, because they need GitHub and systemd.
