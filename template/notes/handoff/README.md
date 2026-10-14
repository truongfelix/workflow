# Handoffs

One file per live session, `<session>.md`, written by that session's `/handoff` and read by every
`/session-start`. The format: `notes/handoff-format.md`. A session writes only its own file, and deletes it when its
work has landed or another session took it over (`continues:`); a new session takes the last one over, and the last
handoff is never deleted. Earlier handoffs are in git, never in an archive file:
`bash .claude/skills/session-start/items.sh show H-<n>` prints one.

next id: H-1 (none given yet)
