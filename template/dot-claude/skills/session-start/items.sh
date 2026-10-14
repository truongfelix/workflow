#!/usr/bin/env bash
#
# items.sh — the parser of BACKLOG.md, questions.md and notes/lessons.md, which follow the item format
# (notes/item-format.md), and of the handoffs in notes/handoff/ (notes/handoff-format.md).
#
# The trackers are read by a person, written by Claude and parsed by scripts, so every item has one shape: `### <state>
# [⚠ ]<id> <title>`, its fields, a body, and in BACKLOG `Done when:`; a lesson has no state, `### L-<n> <title>`.
# `check` lists each place a tracker departs from it, with its file and line: /session-start runs it after the ground
# truth, /handoff before committing the trackers. A handoff is checked for its heading, its six sections in order, and
# the B- or Q- id that each task in Next and Waiting for the user starts with: an id that is in no tracker read in the
# same run, and that its tracker never gave (at or above its `next id`), is reported; one given, then closed since the
# handoff, is not: the next /handoff moves it under Done. `list` prints the items themselves, for board.sh, ground-truth.sh and claim.sh. `show` prints
# one item, live or deleted, from the files and git: a session finds it without the board.
#
# Generic (from the workflow repo): upgrade this file from there; never put project data in it.
#
# Usage: bash .claude/skills/session-start/items.sh check|list [file...]
#        bash .claude/skills/session-start/items.sh show <B-, Q-, L- or H- id>
#   No file: BACKLOG.md, questions.md, notes/lessons.md and notes/handoff/*.md at the project root. A file named
#   BACKLOG*.md holds B- items, one named questions*.md Q- items, one named lessons*.md L- items; in a handoff/
#   folder, README.md holds the handoffs' `next id` and every other *.md file is one handoff (H-).
#   list prints one record per line, tab-separated; in each field a backslash, a tab and a newline are written \\,
#   \t and \n:
#     I <file> <line> <id> <state> <cross> <section> <title> <fields> <body>   an item. state: open, waiting,
#                                       question, ruling, lesson or handoff; cross: 1 for ⚠; fields: its
#                                       `key: value` lines; a handoff's title is its date, time, zone and session
#     U <file> <line> <text>            a block under a `###` heading that is not an item: never dropped
#     P <file> <line> <problem>         what check would report
# Exit 0 = every item follows the format. Exit 2 = a problem was found, or a file could not be read (UNKNOWN, never
# a pass). Exit 1 on a usage error only.
#   show prints the item: its text (live, or its last version in git and the commit that closed it, or archived it
#   for a ruling), its history
#   (each commit that added, changed, closed or reopened it), and the handoffs that name it, live or replaced. Exit 0
#   = shown; 1 = no item has this id, in the files or in git, or a usage error; 2 = UNKNOWN: a shallow clone or no git
#   holds only part of the past (what is there is shown first).

set -uo pipefail

# show: one item, live or from git, with its history and the handoffs that name it (notes/handoff-format.md, "Git is
# the archive"). Every version of its file is read from git (first parent, oldest first), then the file on disk; the
# handoffs too, those on disk and those git has seen, for the ones that name it. A shallow clone, or no git, holds
# only part of the past: the history is UNKNOWN then, never "none".
show() { # <id>
  local id=$1 self sh tab n f v git_ok=0 shallow="" idre gone
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  sh=${BASH:-bash} tab=$(printf '\t')
  cd "$(dirname "${BASH_SOURCE[0]}")/../../.." || { echo "UNKNOWN: cannot reach the project root"; return 2; }
  T=$(mktemp -d "${TMPDIR:-/tmp}/items-show.XXXXXX") || { echo "UNKNOWN: mktemp failed"; return 2; }
  trap 'rm -rf "$T"' EXIT
  if [ "$(uname -s)" = Darwin ] && [ "$(locale charmap 2>/dev/null)" != UTF-8 ]; then export LC_ALL=en_US.UTF-8; fi
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_ok=1
    [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = true ] &&
      shallow=$(git log --format=%cd --date=short 2>/dev/null | tail -n 1)
  fi
  # The files: the item's tracker, and every handoff (an H item is one; the others name items).
  {
    case ${id%%-*} in B) echo BACKLOG.md ;; Q) echo questions.md ;; L) echo notes/lessons.md ;; esac
    for f in notes/handoff/*.md; do [ -e "$f" ] && echo "$f"; done
    [ "$git_ok" = 1 ] && git log --format= --name-only --relative -- notes/handoff/ 2>/dev/null
    echo notes/handoff.md # a 1.x handoff, read for the ids it names
  } | grep -v '/README\.md$' | grep '\.md$' | awk '!seen[$0]++' >"$T/files"
  : >"$T/versions"
  n=0
  version() { # <file> <sha or ""> <day> <subject>
    n=$((n + 1))
    mkdir -p "$T/v/$n/$(dirname "$1")"
    if [ -n "$2" ]; then git show "$2:./$1" >"$T/v/$n/$1" 2>/dev/null || : >"$T/v/$n/$1"
    elif [ -f "$1" ]; then cp "$1" "$T/v/$n/$1"
    else : >"$T/v/$n/$1"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$1" "$2" "$3" "${4//$tab/ }" >>"$T/versions"
  }
  while IFS= read -r f; do
    if [ "$git_ok" = 1 ]; then
      git log --first-parent --reverse --date=short --format="%H$tab%cd$tab%s" -- "$f" >"$T/log" 2>/dev/null
      while IFS="$tab" read -r sha day subject; do version "$f" "$sha" "$day" "$subject"; done <"$T/log"
    fi
    version "$f" "" "$(date +%Y-%m-%d)" "not committed yet" # the file now: an event only where it differs
  done <"$T/files"
  awk -F '\t' '$2 != "notes/handoff.md" { print $1 "/" $2 }' "$T/versions" >"$T/paths"
  : >"$T/list"
  [ -s "$T/paths" ] && (cd "$T/v" && xargs "$sh" "$self" list <"$T/paths" >"$T/list" 2>/dev/null)
  idre="(^|[^A-Za-z0-9-])$id([^0-9]|\$)"
  # 1.x handoffs (one notes/handoff.md, no id) that name it: by the date in their heading.
  awk -F '\t' '$2 == "notes/handoff.md" { print $1 }' "$T/versions" | while IFS= read -r v; do
    f="$T/v/$v/notes/handoff.md"
    [ -s "$f" ] && grep -Eq "$idre" "$f" && sed -n '1s/^# *Handoff *(\(.*\))[[:space:]]*$/\1/p' "$f"
  done | awk '$0 != "" && !seen[$0]++ { print "a 1.x handoff of " $0 " (before handoffs had ids)" }' >"$T/old"
  # A deleted ruling is archived, a deleted question closed: the awk program tells them apart by the last state.
  case ${id%%-*} in L) gone=dropped ;; H) gone=replaced ;; *) gone=closed ;; esac # not in $( ): bash 3.2 misreads it
  awk -F '\t' -v id="$id" -v gone="$gone" -v idre="$idre" -v vdir="$T/v" -v oldf="$T/old" -v shallow="$shallow" -v git_ok="$git_ok" '
function swap(s, a, b,   out, i) {
  out = ""
  while ((i = index(s, a)) > 0) { out = out substr(s, 1, i - 1) b; s = substr(s, i + length(a)) }
  return out s
}
function unesc(s) { return swap(swap(swap(swap(s, "\\\\", "\001"), "\\n", "\n"), "\\t", "\t"), "\001", "\\") }
function short(n) { return vsha[n] == "" ? "-------" : substr(vsha[n], 1, 7) }
function has_claim(fields) { return index("\n" fields, "\nclaimed: ") > 0 }
function how(a, b,   A, B, out) { # state, cross, section, title, fields, body
  split(a, A, "\t"); split(b, B, "\t"); out = ""
  if (A[1] != B[1]) out = out ", " A[1] " → " B[1]
  if (has_claim(A[5]) != has_claim(B[5])) out = out (has_claim(B[5]) ? ", claimed" : ", claim released")
  if (A[4] != B[4]) out = out ", renamed"
  if (A[3] != B[3]) out = out ", moved to " B[3]
  if (out == "" || A[2] != B[2] || A[6] != B[6]) out = out ", edited"
  return substr(out, 3)
}
function event(n, what) { ev[++ne] = vday[n] "  " short(n) "  " what ": " vsubj[n] }
function text(n, ln, f,   path, line, i, fence, out) { # the item as written in version n, from its heading
  path = vdir "/" n "/" f; i = 0; fence = 0; out = ""
  while ((getline line < path) > 0) {
    sub(/\r$/, "", line)
    if (++i < ln) continue
    if (i > ln && !fence && f !~ /handoff\// && (line ~ /^#+ / || line ~ /^---+[ \t]*$/)) break
    if (line ~ /^[ \t]*(```|~~~)/) fence = !fence
    out = out line "\n"
  }
  close(path); sub(/\n+$/, "", out); return out
}
FILENAME ~ /versions$/ { vfile[$1] = $2; vsha[$1] = $3; vday[$1] = $4; vsubj[$1] = $5; N = $1 + 0; disk[$2] = $1 + 0; next }
$1 != "I" { next }
{ n = substr($2, 1, index($2, "/") - 1) + 0 }
$4 == id && (n in rec) { if (!twice) twice = "two items hold it in " short(n) " (" vday[n] ")"; next }
$4 == id { rec[n] = $5 "\t" $6 "\t" $7 "\t" $8 "\t" unesc($9) "\t" unesc($10); line[n] = $3; title[n] = $8; next }
$5 == "handoff" { inv[$4, n] = 1 }
$5 == "handoff" && match(" " unesc($10) " ", idre) { cites[$4] = $8; cn[$4] = n; if (!($4 in corder)) corder[$4] = ++nc }
END {
  for (n = 1; n <= N; n++) {
    f = vfile[n]; p = prev[f] + 0
    if (n in rec) {
      if (!p || !(p in rec)) {
        if (!p && shallow != "" && vsha[n] != "") event(n, "here in the oldest commit of this shallow clone: its past is UNKNOWN")
        else if (!seen) event(n, "added")
        else if (title[n] != lasttitle) {
          event(n, "given again, to another item")
          twice = (twice ? twice "; " : "") "closed as \"" lasttitle "\", given again in " short(n) " (" vday[n] ") to \"" title[n] "\""
        } else event(n, "reopened")
        seen = 1
      } else if (rec[p] != rec[n]) event(n, how(rec[p], rec[n]))
      lastn = n; lasttitle = title[n]
    } else if (p && (p in rec)) {
      split(rec[p], P, "\t"); closedas = (P[1] == "ruling") ? "archived" : gone
      event(n, closedas); closedn = n
    }
    prev[f] = n
  }
  if (!seen) {
    if (git_ok && shallow == "") { print id ": no item has this id, in the files or in their history in git"; exit 1 }
    print "UNKNOWN: " id " is in no file here" (git_ok ? ", and this shallow clone holds the history since " shallow \
      " only (git fetch --unshallow)" : ", and with no git its past is unknown")
    exit 2
  }
  f = vfile[lastn]; split(rec[lastn], R, "\t")
  print id " " title[lastn]
  if (lastn == disk[f]) print "  " R[1] (R[2] == 1 ? " ⚠ cross-repo" : "") ", " f ":" line[lastn]
  else print "  " closedas " on " vday[closedn] " by " short(closedn) " " vsubj[closedn] "; its last version, " f " in " short(lastn) ":"
  if (twice) print "  ⚠ " id " is given twice in git: " twice
  print ""; print text(lastn, line[lastn], f); print ""
  print "History (" f ", first parent):"
  if (!git_ok) print "  UNKNOWN: not a git repo"
  else if (shallow != "") print "  UNKNOWN before " shallow ": a shallow clone (git fetch --unshallow)"
  for (i = 1; i <= ne; i++) print "  " ev[i]
  print "Handoffs that name it:"
  for (h in corder) order[corder[h]] = h
  for (i = 1; i <= nc; i++) {
    h = order[i]
    print "  " h " " cites[h] (((h, disk[vfile[cn[h]]]) in inv) ? " (live: " vfile[cn[h]] ")" : " (replaced)")
  }
  while ((getline l < oldf) > 0) { print "  " l; nc++ }
  if (!nc) print "  none"
  exit (git_ok && shallow == "") ? 0 : 2
}' "$T/versions" "$T/list"
}

case ${1:-} in
  check | list) mode=$1 ;;
  show)
    [ $# = 2 ] && [[ $2 =~ ^[BQLH]-[1-9][0-9]*$ ]] || { echo "usage: $0 show <B-, Q-, L- or H- id>" >&2; exit 1; }
    show "$2"
    exit $? ;;
  *) echo "usage: $0 check|list [file...] | show <id>" >&2; exit 1 ;;
esac
shift
legacy="" # a 1.x handoff not moved yet: the next /handoff moves it (notes/handoff-format.md, "Moving a project to it")
if [ $# = 0 ]; then
  cd "$(dirname "${BASH_SOURCE[0]}")/../../.." || { echo "UNKNOWN: cannot reach the project root"; exit 2; }
  set -- BACKLOG.md questions.md notes/lessons.md notes/handoff/README.md
  for f in notes/handoff/*.md; do
    [ "$f" = notes/handoff/README.md ] || [ ! -e "$f" ] || set -- "$@" "$f"
  done
fi
# Beside the handoffs read (their README), the 1.x handoff: given the files or not, as the board gives them.
for f in "$@"; do
  case $f in
    handoff/README.md | */handoff/README.md)
      if [ -f "${f%handoff/README.md}handoff.md" ]; then legacy="${f%handoff/README.md}handoff.md"; fi ;;
  esac
done

say() { if [ "$mode" = list ]; then echo "$*" >&2; else echo "$*"; fi; } # list keeps stdout for records

failed=0
files=0
args=()
for f in "$@"; do
  case $f in
    handoff/README.md | */handoff/README.md) kind=HR ;;
    handoff/*.md | */handoff/*.md) kind=H ;;
    *)
      case $(basename "$f") in
        BACKLOG*.md) kind=B ;;
        questions*.md) kind=Q ;;
        lessons*.md) kind=L ;;
        *)
          say "UNKNOWN: $f: not a tracker (BACKLOG*.md, questions*.md, lessons*.md or handoff/*.md)"
          failed=1; continue ;;
      esac ;;
  esac
  if [ -d "$f" ] || [ ! -r "$f" ]; then say "UNKNOWN: $f: cannot be read"; failed=1; continue; fi
  if [ ! -s "$f" ] && [ "$kind" = H ]; then
    say "$f:1: empty: a handoff starts with its \`# H-<n> …\` heading"; failed=1; continue
  fi
  if [ ! -s "$f" ]; then say "$f:1: empty: a tracker holds at least its \`next id\` line"; failed=1; continue; fi
  args+=("kind=$kind" "$f")
  files=$((files + 1))
done
[ "$files" = 0 ] && exit 2

# macOS awk reads non-ASCII text only in a UTF-8 locale: in C it stops ("towc: multibyte conversion failure").
if [ "$(uname -s)" = Darwin ] && [ "$(locale charmap 2>/dev/null)" != UTF-8 ]; then export LC_ALL=en_US.UTF-8; fi

# One pass per file. An item runs from its `###` heading to the next heading of any level, a `---` line, or the end
# of the file. Fenced code and multi-line HTML comments are skipped: they hold examples, not items. A state is kept
# by an ASCII name, never compared as an emoji: macOS awk compares strings with strcoll, and its UTF-8 collation finds
# all these emoji equal. A lesson outside an item (a bullet, as before lessons had ids) is reported, never skipped, and
# so is a BACKLOG or questions bullet that starts with a state and a bold title, as items were written before they had
# ids, and the line of a 1.x header that says to cite an item by its title. A handoff is read line by line apart (h_line), as it is one item made of sections. Exit 3 = problems found, so
# that awk failing on its own (exit 2) reads as UNKNOWN.
awk -v mode="$mode" -v legacy="$legacy" '
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
function same(a, b) { return index(a, b) == 1 && length(a) == length(b) } # non-ASCII text: never ==
function old_item(   r, st, n, i) { # an item as written before items had ids (1.x): `- <state> [⚠ ]**<title>**`
  r = $0; sub(/^[ \t]*[-*+][ \t]+/, "", r)
  n = split("🔲 ⏸️ ⏸ 💬 🟢", st, " ")
  for (i = 1; i <= n; i++) if (index(r, st[i]) == 1) { r = substr(r, length(st[i]) + 1); break }
  if (i > n) return 0
  sub(/^[ \t]+/, "", r)
  if (index(r, "⚠") == 1) { r = substr(r, length("⚠") + 1); sub(/^[ \t]+/, "", r) }
  return index(r, "**") == 1
}

function start_file() {
  file = FILENAME; fk = kind; fence = 0; in_comment = 0; id = ""; bad_ln = 0; section = ""
  nid = 0; nid_ln = 0; nid_seen = 0; maxid = 0; items_here = 0; split("", seen)
  hreadme = 0; hfile = 0
  if (fk == "HR") { fk = "H"; hreadme = 1; hreadme_file = file; fields = ""; return }
  if (fk == "H") {
    hfile = 1; if (!hfiles++) hfirst = file
    hstate = 0; hid = ""; hnum = 0; hsec = ""; hk = 0; hfence = 0; h_body = ""; h_flds = ""; h_title = ""
    h_ln = 0; h_last = 0; h_loose = 0
    return
  }
  read_kind[fk] = 1
  if (fk == "B") { states = "🔲 ⏸️ ⏸"; names = "open waiting waiting"; shown = "🔲 ⏸️"; fields = " claimed repos waits " }
  else if (fk == "L") { states = ""; fields = " repos " }
  else {
    states = "💬 🟢 ⏸️ ⏸"; names = "question ruling waiting waiting"; shown = "💬 🟢 ⏸️"
    fields = " repos waits blocks ruled replaces "
  }
}

function end_file() {
  if (file == "") return
  if (hfile) { h_end(); return }
  end_item()
  if (!nid_seen) problem(1, "no `next id: " fk "-<n> (last given to <agent>@<session>)` line in the header")
  else if (nid && maxid >= nid) problem(nid_ln, "`next id` is " fk "-" nid ", not above the highest id here, " fk "-" maxid)
  if (hreadme) { hnid = nid; hnid_ln = nid_ln; hreadme_seen = 1 }
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
  nid = substr(tok, 3) + 0; next_of[fk] = nid
  if (rest ~ /^none given yet\)$/) {
    if (nid != 1) problem(FNR, "`next id` says none given yet, but is not " fk "-1")
  } else if (rest !~ /^last given to [^ @()]+@[^ @()]+\)$/) {
    problem(FNR, "`next id` does not end with `(last given to <agent>@<session>)`")
  }
}

function heading(   n, i, st, nm, tok, tid) {
  end_item(); items++; items_here++
  R = substr($0, 5); state = ""; bad_ln = FNR; body = $0
  if (fk == "L") state = "lesson"
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
    else problem(FNR, "⚠ marks a cross-repo BACKLOG item, not a " (fk == "Q" ? "question" : "lesson"))
  }
  if (!match(R, /^[A-Za-z]+-[0-9]+/)) {
    split(R, tok, " ")
    if (fk == "L") problem(FNR, "`### " tok[1] "`: a lesson is `### L-<n> <title>`, with no state")
    else problem(FNR, "no id after the state: expected `" fk "-<n>`")
    return
  }
  tid = substr(R, 1, RLENGTH); R = substr(R, RLENGTH + 1)
  if (tid !~ ("^" fk "-[1-9][0-9]*$")) {
    problem(FNR, "`" tid "` is not a " fk "- id (`" fk "-<n>`, no leading zero)"); return
  }
  if (R !~ /^ +[^ ]/) problem(FNR, tid ": no title after the id")
  title = R; sub(/^ +/, "", title); bad_ln = 0; body = ""; flds = ""
  if (tid in seen) problem(FNR, tid " is given twice: also at line " seen[tid])
  else seen[tid] = FNR
  all[tid] = 1
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
  } else if (key == "claimed" && val !~ /^[^ @]+@[^ @]+ on [^ ]+( at [^ ]+)?$/) {
    problem(FNR, id ": `claimed:` is not `<agent>@<session> on <branch> at <machine>`: " val)
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

# A handoff (notes/handoff-format.md): its heading on the first line, `continues:` under it, then the six sections.
function hw() { return hid == "" ? "" : hid ": " }

function h_line() {
  h_last = FNR
  if (hstate == 0) { # the first line that is not blank
    if ($0 ~ /^[ \t]*$/) return
    hstate = 1; items++; h_ln = FNR; h_head = $0; h_heading(); return
  }
  if (hstate == 1 && !hfence && $0 ~ /^[a-z]+:( |$)/) { h_field(); return }
  hstate = 2
  h_body = h_body (h_body == "" ? "" : "\n") $0
  if ($0 ~ /^[ \t]*(```|~~~)/) { hfence = !hfence; h_content = 1; return }
  if (hfence) return
  if ($0 ~ /^## /) { h_section(); return }
  if ($0 ~ /^# /) { problem(FNR, hw() "a second `#` heading: a handoff has one, on its first line"); return }
  if ($0 ~ /^[ \t]*$/) return
  if (hsec == "") {
    if (!h_loose++) problem(FNR, hw() "text before `## Next`: a handoff is its heading, then its six sections")
    return
  }
  h_content = 1
  if (hsec == "Next" && match($0, /^[0-9]+\. +/)) h_cite(substr($0, RLENGTH + 1), "a task in Next")
  else if (hsec == "Waiting for the user" && match($0, /^[-*+] +/)) h_cite(substr($0, RLENGTH + 1), "a task waiting for the user")
}

function h_heading(   n, t, sess, fname) {
  n = split($0, t, " ")
  if (n != 7 || t[1] != "#" || t[2] !~ /^H-[1-9][0-9]*$/ || t[3] !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ ||
      t[4] !~ /^[0-9][0-9]:[0-9][0-9]$/ || t[5] !~ /^[A-Za-z0-9+:-]+$/ || !same(t[6], "·") || t[7] !~ /^[^@]+@[^@]+$/) {
    problem(FNR, "the first line is not `# H-<n> YYYY-MM-DD HH:MM <zone> · <agent>@<session>`")
    return
  }
  hid = t[2]; hnum = substr(hid, 3) + 0; h_title = t[3] " " t[4] " " t[5] " · " t[7]
  if (hid in hseen) problem(FNR, hid " is given twice: also in " hseen[hid])
  else hseen[hid] = file
  if (hnum > hmax) hmax = hnum
  sess = substr(t[7], index(t[7], "@") + 1)
  fname = file; sub(/^.*\//, "", fname); sub(/\.md$/, "", fname)
  if (!same(sess, fname)) problem(FNR, hid ": the file is not named after its session, `" sess ".md`")
}

function h_field(   p, key, val) {
  p = index($0, ":"); key = substr($0, 1, p - 1); val = substr($0, p + 1); sub(/^ +/, "", val)
  h_flds = h_flds (h_flds == "" ? "" : "\n") key ": " val
  if (key != "continues") { problem(FNR, hw() "unknown field `" key ":` (a handoff has one: continues)"); return }
  if (val !~ /^H-[1-9][0-9]*$/) problem(FNR, hw() "`continues:` is not an H- id: " val)
  else if (hnum && substr(val, 3) + 0 >= hnum) problem(FNR, hw() "`continues: " val "`: it names an older handoff, with a lower id")
}

function h_section(   name, j) {
  name = substr($0, 4); sub(/[ \t]+$/, "", name)
  h_close()
  for (j = 1; j <= 6; j++) if (name == hsecs[j]) break
  if (j > 6) { problem(FNR, hw() "`## " name "` is not a section of a handoff (" hsec_list ")"); hsec = "?"; return }
  if (j <= hk) problem(FNR, hw() "`## " name "` again, or out of order: the sections are " hsec_list)
  else {
    while (hk + 1 < j) { hk++; problem(FNR, hw() "no `## " hsecs[hk] "` before `## " name "`: a handoff has all six sections, in order") }
    hk = j
  }
  hsec = name; hsec_ln = FNR; h_content = 0
}

function h_close() { if (hsec != "" && hsec != "?" && !h_content) problem(hsec_ln, hw() "`## " hsec "` is empty: write `None.`") }

function h_cite(s, what,   cid, rest, k) {
  if (match(s, /^[A-Z]-[1-9][0-9]*/)) rest = substr(s, RLENGTH + 1) # the id ends at a space or a punctuation mark
  if (!RSTART || (rest != "" && rest !~ /^[ :,.;)]/)) {
    problem(FNR, hw() what " without an id: it starts with the B- or Q- id of its item (a new task becomes an item first)")
    return
  }
  cid = substr(s, 1, RLENGTH); k = substr(cid, 1, 1)
  if (k != "B" && k != "Q") { problem(FNR, hw() what " names " cid ": a task is a B- or Q- item"); return }
  ncite++; cite_file[ncite] = file; cite_ln[ncite] = FNR; cite_id[ncite] = cid; cite_h[ncite] = hw()
}

function h_end() {
  if (hstate == 0) { problem(1, "no `# H-<n> …` heading: the file holds no handoff"); return }
  if (hfence) problem(h_last, hw() "a code block is never closed")
  h_close()
  while (hk < 6) { hk++; problem(h_last, hw() "no `## " hsecs[hk] "` section: a handoff has all six, in order (an empty one says `None.`)") }
  if (mode == "list") {
    if (hid == "") print "U\t" file "\t" h_ln "\t" esc(trimmed(h_head "\n" h_body))
    else print "I\t" file "\t" h_ln "\t" hid "\thandoff\t0\t\t" esc(h_title) "\t" esc(h_flds) "\t" esc(trimmed(h_body))
  }
}

# After every file: the ids the handoffs name, against the trackers read in this run; the ids of the handoffs, against
# their `next id`.
function h_final(   i, k) {
  for (i = 1; i <= ncite; i++) {
    file = cite_file[i]; k = substr(cite_id[i], 1, 1)
    if (!(k in read_kind)) problem(cite_ln[i], cite_h[i] cite_id[i] ": not checked, no " (k == "B" ? "BACKLOG.md" : "questions.md") " given")
    else if (!(cite_id[i] in all) && !((k in next_of) && substr(cite_id[i], 3) + 0 < next_of[k]))
      problem(cite_ln[i], cite_h[i] cite_id[i] " is in no tracker: a task names an open item (one that landed goes under `## Done`)")
  }
  if (hfiles && !hreadme_seen) { file = hfirst; problem(1, "no handoff/README.md given: the ids of the handoffs are not checked against its `next id`") }
  else if (hreadme_seen && hnid && hmax >= hnid) { file = hreadme_file; problem(hnid_ln, "`next id` is H-" hnid ", not above the highest handoff, H-" hmax) }
}

BEGIN {
  split("Next|Waiting for the user|Running|Unfinished|Done|Learned", hsecs, "|")
  hsec_list = "Next, Waiting for the user, Running, Unfinished, Done, Learned"
}
FNR == 1 { end_file(); start_file() }
{ sub(/\r$/, "") }
hfile { h_line(); next }
in_comment { if (index($0, "-->")) in_comment = 0; next }
/^[ \t]*(```|~~~)/ { fence = !fence; keep(); text_line(); next }
fence { keep(); text_line(); next }
/^[ \t]*<!--/ && index($0, "-->") == 0 { in_comment = 1; next }
/^next id:/ { next_id(); next }
/^### / { heading(); next }
/^##? / || /^---+[ \t]*$/ { end_item(); if ($0 ~ /^#/) { section = $0; sub(/^#+ +/, "", section) }; next }
id != "" { item_line(); next }
bad_ln { keep(); next }
fk == "L" && section != "" && /^[ \t]*[-*+] / { problem(FNR, "a lesson without an id: a lesson is `### L-<n> <title>`") }
(fk == "B" || fk == "Q") && section != "" && /^[ \t]*[-*+] / && old_item() {
  problem(FNR, "an item without an id, as before items had ids: an item is `### <state> <id> <title>` (notes/item-format.md, \"Moving a project to it\")")
}
(fk == "B" || fk == "Q") && /[Cc]ite an? (item|entry) by its \*\*title\*\*/ {
  problem(FNR, "a 1.x header, which says to cite an item by its title: take the header of the template (notes/item-format.md, \"Moving a project to it\")")
}

END {
  end_file()
  h_final()
  if (legacy != "") { file = legacy; problem(1, "a 1.x handoff: the next /handoff moves it to notes/handoff/ (notes/handoff-format.md, \"Moving a project to it\")") }
  if (mode == "list") exit (problems ? 3 : 0)
  if (problems) { printf "%d problem(s); the formats: notes/item-format.md, notes/handoff-format.md\n", problems; exit 3 }
  printf "OK: %d item(s), all in their format (notes/item-format.md, notes/handoff-format.md)\n", items
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
