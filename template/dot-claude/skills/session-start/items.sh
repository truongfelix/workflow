#!/usr/bin/env bash
#
# items.sh — the parser of BACKLOG.md and questions.md, which follow the item format (notes/item-format.md).
#
# The trackers are read by a person, written by Claude and parsed by scripts, so every item has one shape:
# `### <state> [⚠ ]<id> <title>`, its fields, a body, and in BACKLOG `Done when:`. `check` lists each place a
# tracker departs from it, with its file and line: /session-start runs it after the ground truth, /handoff before
# committing the trackers. `list` prints the items themselves, for the board (board.sh).
#
# Generic (from the workflow repo): upgrade this file from there; never put project data in it.
#
# Usage: bash .claude/skills/session-start/items.sh check|list [file...]
#   No file: BACKLOG.md and questions.md at the project root. A file named BACKLOG*.md holds B- items, one named
#   questions*.md Q- items.
#   list prints one record per line, tab-separated; in each field a backslash, a tab and a newline are written \\,
#   \t and \n:
#     I <file> <line> <id> <state> <cross> <section> <title> <fields> <body>   an item. state: open, waiting,
#                                       question or ruling; cross: 1 for ⚠; fields: its `key: value` lines
#     U <file> <line> <text>            a block under a `###` heading that is not an item: never dropped
#     P <file> <line> <problem>         what check would report
# Exit 0 = every item follows the format. Exit 2 = a problem was found, or a file could not be read (UNKNOWN, never
# a pass). Exit 1 on a usage error only.

set -uo pipefail

case ${1:-} in
  check | list) mode=$1 ;;
  *) echo "usage: $0 check|list [file...]" >&2; exit 1 ;;
esac
shift
if [ $# = 0 ]; then
  cd "$(dirname "${BASH_SOURCE[0]}")/../../.." || { echo "UNKNOWN: cannot reach the project root"; exit 2; }
  set -- BACKLOG.md questions.md
fi

say() { if [ "$mode" = list ]; then echo "$*" >&2; else echo "$*"; fi; } # list keeps stdout for records

failed=0
files=0
args=()
for f in "$@"; do
  case $(basename "$f") in
    BACKLOG*.md) kind=B ;;
    questions*.md) kind=Q ;;
    *) say "UNKNOWN: $f: not a tracker (BACKLOG*.md or questions*.md)"; failed=1; continue ;;
  esac
  if [ -d "$f" ] || [ ! -r "$f" ]; then say "UNKNOWN: $f: cannot be read"; failed=1; continue; fi
  if [ ! -s "$f" ]; then say "$f:1: empty: a tracker holds at least its \`next id\` line"; failed=1; continue; fi
  args+=("kind=$kind" "$f")
  files=$((files + 1))
done
[ "$files" = 0 ] && exit 2

# macOS awk reads non-ASCII text only in a UTF-8 locale: in C it stops ("towc: multibyte conversion failure").
if [ "$(uname -s)" = Darwin ] && [ "$(locale charmap 2>/dev/null)" != UTF-8 ]; then export LC_ALL=en_US.UTF-8; fi

# One pass per file. An item runs from its `###` heading to the next heading of any level, a `---` line, or the end
# of the file. Fenced code and multi-line HTML comments are skipped: they hold examples, not items. A state is kept
# by an ASCII name, never compared as an emoji: macOS awk compares strings with strcoll, and its UTF-8 collation
# finds all these emoji equal. Exit 3 = problems found, so that awk failing on its own (exit 2) reads as UNKNOWN.
awk -v mode="$mode" '
function problem(ln, msg) {
  problems++
  if (mode == "list") print "P\t" file "\t" ln "\t" esc(msg)
  else printf "%s:%d: %s\n", file, ln, msg
}
function esc(s) { return swap(swap(swap(s, "\\", "\\\\"), "\t", "\\t"), "\n", "\\n") }
function swap(s, a, b,   out, i) { # every a in s becomes b: index(), not gsub(), whose "\\" differs between awks
  out = ""
  while ((i = index(s, a)) > 0) { out = out substr(s, 1, i - 1) b; s = substr(s, i + length(a)) }
  return out s
}
function keep() { if (mode == "list" && (id != "" || bad_ln)) body = body (body == "" ? "" : "\n") $0 }
function starts(p) { if (index(R, p) != 1) return 0; R = substr(R, length(p) + 1); return 1 }

function start_file() {
  file = FILENAME; fk = kind; fence = 0; in_comment = 0; id = ""; bad_ln = 0; section = ""
  nid = 0; nid_ln = 0; nid_seen = 0; maxid = 0; items_here = 0; split("", seen)
  if (fk == "B") { states = "🔲 ⏸️ ⏸"; names = "open waiting waiting"; shown = "🔲 ⏸️"; fields = " repos waits " }
  else {
    states = "💬 🟢 ⏸️ ⏸"; names = "question ruling waiting waiting"; shown = "💬 🟢 ⏸️"
    fields = " repos waits blocks ruled replaces "
  }
}

function end_file() {
  if (file == "") return
  end_item()
  if (!nid_seen) problem(1, "no `next id: " fk "-<n> (last given to <agent>@<session>)` line in the header")
  else if (nid && maxid >= nid) problem(nid_ln, "`next id` is " fk "-" nid ", not above the highest id here, " fk "-" maxid)
}

function next_id(   tok, rest) {
  if (nid_seen) { problem(FNR, "a second `next id` line: a tracker has one, in its header"); return }
  nid_seen = 1; nid_ln = FNR
  if (items_here) problem(FNR, "`next id` is below an item: it belongs in the header, above every item")
  if (!match($0, /^next id: [A-Za-z]+-[0-9]+ \(/)) {
    problem(FNR, "`next id` is not `next id: " fk "-<n> (last given to <agent>@<session>)`"); return
  }
  tok = substr($0, 10, RLENGTH - 11); rest = substr($0, RLENGTH + 1)
  if (tok !~ ("^" fk "-[1-9][0-9]*$")) { problem(FNR, "`next id` " tok " is not a " fk "- id"); return }
  nid = substr(tok, 3) + 0
  if (rest ~ /^none given yet\)$/) {
    if (nid != 1) problem(FNR, "`next id` says none given yet, but is not " fk "-1")
  } else if (rest !~ /^last given to [^ @()]+@[^ @()]+\)$/) {
    problem(FNR, "`next id` does not end with `(last given to <agent>@<session>)`")
  }
}

function heading(   n, i, st, nm, tok, tid) {
  end_item(); items++; items_here++
  R = substr($0, 5); state = ""; bad_ln = FNR; body = $0
  n = split(states, st, " "); split(names, nm, " ")
  for (i = 1; i <= n; i++) if (starts(st[i] " ")) { state = nm[i]; break }
  if (state == "") {
    split(R, tok, " ")
    problem(FNR, "`### " tok[1] "`: not a state of this tracker (" shown "); an item is `### <state> [⚠ ]<id> <title>`")
    return
  }
  cross = 0
  if (starts("⚠️ ") || starts("⚠ ")) {
    if (fk == "B") cross = 1
    else problem(FNR, "⚠ marks a cross-repo BACKLOG item, not a question")
  }
  if (!match(R, /^[A-Za-z]+-[0-9]+/)) { problem(FNR, "no id after the state: expected `" fk "-<n>`"); return }
  tid = substr(R, 1, RLENGTH); R = substr(R, RLENGTH + 1)
  if (tid !~ ("^" fk "-[1-9][0-9]*$")) {
    problem(FNR, "`" tid "` is not a " fk "- id (`" fk "-<n>`, no leading zero)"); return
  }
  if (R !~ /^ +[^ ]/) problem(FNR, tid ": no title after the id")
  title = R; sub(/^ +/, "", title); bad_ln = 0; body = ""; flds = ""
  if (tid in seen) problem(FNR, tid " is given twice: also at line " seen[tid])
  else seen[tid] = FNR
  n = substr(tid, 3) + 0
  if (n > maxid) maxid = n
  id = tid; item_ln = FNR; zone = "fields"; split("", f); done_ln = 0; gap = 0; after_ln = 0
}

function field(key, val) {
  if (index(fields, " " key " ") == 0) {
    problem(FNR, id ": unknown field `" key ":` (fields in this tracker:" substr(fields, 1, length(fields) - 1) ")"); return
  }
  if (key in f) problem(FNR, id ": `" key ":` given twice")
  f[key] = val
  if (val ~ /^[ \t]*$/) problem(FNR, id ": `" key ":` is empty")
  else if (key == "ruled" && val !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) {
    problem(FNR, id ": `ruled:` is not a YYYY-MM-DD date: " val)
  } else if (key == "replaces" && val !~ ("^" fk "-[1-9][0-9]* +[^ ]")) {
    problem(FNR, id ": `replaces:` is not `<id> <title>`: " val)
  }
}

function item_line(   p, key, val) {
  if (zone == "fields") {
    if ($0 ~ /^[a-z]+:( |$)/) {
      p = index($0, ":"); key = substr($0, 1, p - 1); val = substr($0, p + 1); sub(/^ +/, "", val)
      flds = flds (flds == "" ? "" : "\n") key ": " val
      field(key, val); return
    }
    zone = "body"
  }
  keep()
  if ($0 ~ /^[ \t]*$/) { if (done_ln) gap = 1; return }
  if ($0 ~ /^Done when:/) {
    if (done_ln) problem(FNR, id ": a second `Done when:` line")
    else done_ln = FNR
    return
  }
  text_line()
}

function text_line() {
  if (id == "") return
  zone = "body"
  if (done_ln && gap && !after_ln) after_ln = FNR
}

function end_item() {
  if (bad_ln && mode == "list") print "U\t" file "\t" bad_ln "\t" esc(trimmed(body))
  bad_ln = 0
  if (id == "") return
  if (fk == "B" && !done_ln) problem(item_ln, id ": no `Done when:` line: a BACKLOG item ends with it")
  else if (fk == "B" && after_ln) problem(after_ln, id ": text after the `Done when:` paragraph, which ends the item")
  if (state == "waiting" && !("waits" in f)) problem(item_ln, id ": ⏸️ without a `waits:` line")
  if (cross && !("repos" in f)) problem(item_ln, id ": ⚠ without a `repos:` line")
  if (state == "ruling" && !("ruled" in f)) problem(item_ln, id ": 🟢 without a `ruled:` line")
  if (mode == "list") {
    print "I\t" file "\t" item_ln "\t" id "\t" state "\t" cross "\t" esc(section) "\t" esc(title) "\t" esc(flds) "\t" \
      esc(trimmed(body))
  }
  id = ""
}

function trimmed(s) { sub(/^\n+/, "", s); sub(/\n+$/, "", s); return s }

FNR == 1 { end_file(); start_file() }
{ sub(/\r$/, "") }
in_comment { if (index($0, "-->")) in_comment = 0; next }
/^[ \t]*(```|~~~)/ { fence = !fence; keep(); text_line(); next }
fence { keep(); text_line(); next }
/^[ \t]*<!--/ && index($0, "-->") == 0 { in_comment = 1; next }
/^next id:/ { next_id(); next }
/^### / { heading(); next }
/^##? / || /^---+[ \t]*$/ { end_item(); if ($0 ~ /^#/) { section = $0; sub(/^#+ +/, "", section) }; next }
id != "" { item_line(); next }
bad_ln { keep() }

END {
  end_file()
  if (mode == "list") exit (problems ? 3 : 0)
  if (problems) { printf "%d problem(s) in %d item(s); the format: notes/item-format.md\n", problems, items; exit 3 }
  printf "OK: %d item(s), all in the format of notes/item-format.md\n", items
}
' "${args[@]}"
rc=$?
case $rc in
  0) ;;
  3) rc=2 ;;
  *) say "UNKNOWN: awk failed (exit $rc)"; rc=2 ;;
esac
[ "$failed" = 1 ] && rc=2
exit "$rc"
