# Handoffs

One file per live session, `<session>.md`, written by that session's `/handoff` and read by every
`/session-start`. The format: `notes/handoff-format.md`. A session writes only its own file, and deletes it when its
work has landed or another session took it over (`continues:`). Earlier handoffs are in git, never in an archive
file: `git log -p -S'H-<n> ' -- notes/handoff/`.

next id: H-10 (last given to claude@pantry)
