#!/usr/bin/env bash
#
# board.sh — BACKLOG.md, questions.md, notes/lessons.md and the handoffs in notes/handoff/ as one read-only page:
# every item, filtered by repo, state, date and text, the closed ones included (from git), each with its history.
# A lesson that is deleted shows as dropped, a handoff that is replaced or deleted as replaced. Handoffs written
# before they had ids (one notes/handoff.md, workflow 1.x) are shown too, by their date.
#
# The page is rebuilt from the markdown at each run, by items.sh (the parser of the format check) and git. It never
# writes to the trackers, which stay the only source. One self-contained HTML file: plain JavaScript, no server, no
# library, no network.
#
# Always current: the project's Claude Code hook (.claude/settings.json) runs `board.sh --hook` after each tool call
# that edits a tracker, a lesson or a handoff, runs git (commit, pull, merge, rebase, push...) or claims an item,
# and the page is rebuilt, offline, with the PRs last read. An open page reloads itself when its file changes: its
# first lines, read as JavaScript, set the build's stamp (the rest of the file is a comment then), so the page loads
# its own file as a script every 2 s and compares. It keeps its filters (in its address), its scroll and the search
# being typed.
# Where no browser can show the page (a cloud session, SSH, no display), it prints a text board instead of opening.
#
# Repos: the names in .claude/ground-truth.conf. An item's repos are its `repos:` line, else its section's first word
# when that names a repo; with one repo configured, every item is in it.
# Dates: from the commits that changed each file (first parent only, so a merge counts once): added, last changed,
# closed (the commit that deleted the item). Edits not committed yet count as today's.
# Commits and PRs: each commit's whole message and the files it changed, for the commits in an item's history, the
# commits of every repo in ground-truth.conf that name an id, and every commit hash quoted in an item, a handoff, a
# commit message or a PR, looked up in those repos. PRs: one `gh pr list` per GitHub repo when the page is built
# (the page itself needs no network); a PR names an item by its id (title, description, branch), an item names a PR
# by `#<number>`. When gh cannot answer, the page says the PRs were not read, never that there are none. The PRs
# read are kept next to the page (<page>-prs.tsv), and an --offline build shows them with the time they were read.
#
# Generic (from the workflow repo): upgrade this file from there; never put project data in it.
#
# Usage: bash .claude/skills/session-start/board.sh [--out <file>] [--no-open] [--offline] [--text] [<project dir>]
#        bash .claude/skills/session-start/board.sh --hook      (the PostToolUse hook: the tool call as JSON on stdin)
#   <project dir>  default: the project this script is installed in
#   --out          where to write the page. Default: <temp folder>/<project>-board.html, the same file at each run
#   --no-open      only print the page's path
#   --offline      do not ask GitHub for the PRs: show the ones last read
#   --text         also print the open items as text (what it does instead of opening, where no browser can)
#   --hook         rebuild, offline, if the tool call on stdin touched the trackers or git; silent, always exit 0
#   --queue <online|offline>  what --hook runs: one rebuild at a time, the last change always in the page
# Exit 0 = the page is written (problems in the trackers are shown on it). 2 = no page (UNKNOWN). 1 = usage error.

set -uo pipefail

usage() { echo "usage: $0 [--out <file>] [--no-open] [--offline] [--text] [--hook] [<project dir>]" >&2; exit 1; }
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SH=${BASH:-bash}
out="" open=1 offline=0 text=0 hook=0 queue="" dir=""
while [ $# -gt 0 ]; do
  case $1 in
    --out) [ $# -ge 2 ] || usage; out=$2; shift 2 ;;
    --no-open) open=0; shift ;;
    --offline) offline=1; shift ;;
    --text) text=1; shift ;;
    --hook) hook=1; shift ;;
    --queue) [ $# -ge 2 ] || usage; queue=$2; shift 2 ;;
    -*) usage ;;
    *) [ -z "$dir" ] || usage; dir=$1; shift ;;
  esac
done
[ -n "$out" ] && case $out in /*) ;; *) out="$(pwd)/$out" ;; esac

# The hook: Claude Code passes the tool call as JSON. A path or a command that names a tracker, a lesson or a handoff,
# a git command that moves a branch, or a claim (claim.sh), rebuilds the page; a push or a `gh pr` also reads the
# PRs again. A false match costs one rebuild. Quiet, and never an error: a hook that fails would show in every session.
if [ "$hook" = 1 ]; then
  input=$(cat)
  printf '%s' "$input" | grep -Eq 'BACKLOG\.md|questions\.md|lessons\.md|handoff[/\\]|claim\.sh|git [^|;&]{0,80}(commit|pull|merge|rebase|reset|revert|cherry-pick|checkout|switch|stash|push)' ||
    exit 0
  want=offline
  printf '%s' "$input" | grep -Eq 'git [^|;&]{0,80}push|gh pr ' && want=online
  "$SH" "${BASH_SOURCE[0]}" --queue "$want" ${out:+--out "$out"} ${dir:+"$dir"} >/dev/null 2>&1
  exit 0
fi
cd "${dir:-$HERE/../../..}" 2>/dev/null || { echo "UNKNOWN: cannot reach the project folder ${dir:-}"; exit 2; }

trackers=() # what items.sh reads now: the trackers, the lessons, the handoffs and their README
for f in BACKLOG.md questions.md; do [ -f "$f" ] && trackers+=("$f"); done
[ ${#trackers[@]} -gt 0 ] || { echo "UNKNOWN: no BACKLOG.md or questions.md in $(pwd)"; exit 2; }
for f in notes/lessons.md notes/handoff/README.md notes/handoff/*.md; do
  case " ${trackers[*]} " in *" $f "*) continue ;; esac
  [ -f "$f" ] && trackers+=("$f")
done
T=$(mktemp -d "${TMPDIR:-/tmp}/board.XXXXXX") || { echo "UNKNOWN: no temp folder"; exit 2; }
trap 'rm -rf "$T"' EXIT

# The project's name: the trackers' title up to its dash ("# Pantry — Backlog"), else the folder's name (also while
# the title is still the template's FILL marker).
project=$(sed -n '1s/^# *\(.*\) — .*/\1/p' "${trackers[0]}" | tr -d '\r')
case $project in *FILL*) project="" ;; esac
[ -n "$project" ] || project=$(basename "$(pwd)")
[ -n "$out" ] || out="${TMPDIR:-/tmp}/$(printf '%s' "$project" | tr -c 'A-Za-z0-9._-' '-')-board.html"
cache="${out%.html}-prs.tsv" # the PRs last read, for an --offline build

# One rebuild at a time (--queue, from the hook): a call that finds one running leaves its mark, and the running one
# builds again, so the last change is always in the page.
if [ -n "$queue" ]; then
  mark="${out%.html}.dirty" lock="${out%.html}.lock"
  echo "$queue" >>"$mark"
  [ -d "$lock" ] && find "$lock" -maxdepth 0 -mmin +2 -exec rmdir {} \; 2>/dev/null # left by a killed run
  while [ -e "$mark" ] && mkdir "$lock" 2>/dev/null; do
    while [ -e "$mark" ]; do
      args=(--no-open --offline)
      grep -q online "$mark" 2>/dev/null && args=(--no-open)
      rm -f "$mark"
      "$SH" "$HERE/board.sh" "${args[@]}" --out "$out" "$(pwd)" >/dev/null 2>&1
    done
    rmdir "$lock"
  done
  exit 0
fi

repos=""
if [ -f .claude/ground-truth.conf ]; then
  repos=$(REPOS=(); . ./.claude/ground-truth.conf >/dev/null 2>&1
    for r in ${REPOS[@]+"${REPOS[@]}"}; do printf '%s ' "${r%%|*}"; done)
fi

# Every version of each file in git, oldest first, then what is on disk when it differs from the last commit. A file
# deleted from disk, or by a commit, gives an empty version: the items it held are closed there.
tab=$(printf '\t')
today=$(date +%Y-%m-%d)
head=""
mkdir "$T/v" && : >"$T/versions" && : >"$T/old"
versions=() # versions items.sh reads
oldv=()     # versions of a 1.x notes/handoff.md, read by old_handoff
add_version() { # <file> <sha or ""> <day> <subject>: one version of <file>, from git or from the disk
  local n=$((${#versions[@]} + ${#oldv[@]} + 1))
  mkdir -p "$T/v/$n/$(dirname "$1")"
  if [ -n "$2" ]; then git show "$2:./$1" >"$T/v/$n/$1" 2>/dev/null
  elif [ -f "$1" ]; then cp "$1" "$T/v/$n/$1"
  else : >"$T/v/$n/$1"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$1" "$2" "$3" "${4//$tab/ }" >>"$T/versions"
  if [ "$1" = notes/handoff.md ]; then oldv+=("$n/$1"); else versions+=("$n/$1"); fi
}
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  head=$(git rev-parse --short HEAD 2>/dev/null)
  {
    printf '%s\n' "${trackers[@]}" notes/handoff.md
    git log --format= --name-only --relative -- notes/handoff/ 2>/dev/null
  } | grep -v '^notes/handoff/README\.md$' | grep '\.md$' | awk '!seen[$0]++' >"$T/files"
  while IFS= read -r f; do
    git log --first-parent --reverse --date=short --format="%H$tab%cd$tab%s" -- "$f" >"$T/log" 2>/dev/null
    while IFS="$tab" read -r sha day subject; do add_version "$f" "$sha" "$day" "$subject"; done <"$T/log"
    if [ -f "$f" ]; then
      if ! git ls-files --error-unmatch -- "$f" >/dev/null 2>&1 || ! git diff --quiet HEAD -- "$f" 2>/dev/null; then
        add_version "$f" "" "$today" "not committed yet"
      fi
    elif git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
      add_version "$f" "" "$today" "not committed yet" # deleted, the deletion not committed
    fi
  done <"$T/files"
fi

# A 1.x handoff (`# Handoff (YYYY-MM-DD HH:MM <zone>)`, no id) as an items.sh record: its id is `H~` and its date, so
# two versions of the same handoff are one item, edited. One with no date ("not written yet") is no handoff.
old_handoff() { # <file> <record path>
  awk -v rec="$2" '
    function swap(s, a, b,   out, i) {
      out = ""
      while ((i = index(s, a)) > 0) { out = out substr(s, 1, i - 1) b; s = substr(s, i + length(a)) }
      return out s
    }
    function esc(s) { return swap(swap(swap(s, "\\", "\\\\"), "\t", "\\t"), "\n", "\\n") }
    { sub(/\r$/, "") }
    head == "" { if ($0 ~ /^# /) head = $0; next }
    { body = body "\n" $0 }
    END {
      t = head; sub(/^# *Handoff */, "", t); gsub(/[()]/, "", t)
      if (t !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]/) exit
      sub(/^\n+/, "", body); sub(/\n+$/, "", body)
      print "I\t" rec "\t1\tH~" substr(t, 1, 10) "T" substr(t, 12, 5) "\thandoff\t0\t\t" esc(t " · before handoffs had ids") "\t\t" esc(body)
    }' "$1"
}
: >"$T/hist"
[ ${#versions[@]} -gt 0 ] && (cd "$T/v" && "$SH" "$HERE/items.sh" list "${versions[@]}" >"$T/hist" 2>/dev/null)
for v in ${oldv[@]+"${oldv[@]}"}; do old_handoff "$T/v/$v" "$v" >>"$T/hist"; done
"$SH" "$HERE/items.sh" list "${trackers[@]}" >"$T/now" 2>"$T/now.err"
rc=$?
if [ "$rc" != 0 ] && [ "$rc" != 2 ]; then echo "UNKNOWN: items.sh failed (exit $rc)"; cat "$T/now.err"; exit 2; fi
if [ ! -s "$T/now" ] && [ -s "$T/now.err" ]; then echo "UNKNOWN: items.sh read nothing"; cat "$T/now.err"; exit 2; fi
awk '{ print "P\t\t0\t" $0 }' "$T/now.err" >>"$T/now" # its own complaints: no file, no line
[ -f notes/handoff.md ] && old_handoff notes/handoff.md notes/handoff.md >>"$T/now"

# The repos: each entry of ground-truth.conf that is a git repo here (name, path, GitHub repo), then this project's own
# repo when no entry is it.
TIMEOUT_CMD=""
for t in timeout gtimeout; do
  command -v "$t" >/dev/null && "$t" 1 true </dev/null >/dev/null 2>&1 && { TIMEOUT_CMD=$t; break; }
done
with_timeout() { # <seconds> <command...>: as in ground-truth.sh
  local secs=$1 pid n=0
  shift
  if [ -n "$TIMEOUT_CMD" ]; then "$TIMEOUT_CMD" "$secs" "$@"; return; fi
  "$@" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$n" -ge $((secs * 10)) ]; then kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 124; fi
    sleep 0.1
    n=$((n + 1))
  done
  wait "$pid"
}
: >"$T/conf" && : >"$T/repos"
if [ -f .claude/ground-truth.conf ]; then
  (REPOS=(); . ./.claude/ground-truth.conf >/dev/null 2>&1
    for r in ${REPOS[@]+"${REPOS[@]}"}; do printf '%s\n' "$r"; done) >"$T/conf"
fi
self=$(git rev-parse --show-toplevel 2>/dev/null)
self_name=""
while IFS='|' read -r name path remote def gh_repo; do
  [ -n "$name" ] && [ -n "$path" ] && git -C "$path" rev-parse --git-dir >/dev/null 2>&1 || continue
  if [ -z "$gh_repo" ]; then
    gh_repo=$(git -C "$path" remote get-url "${remote:-origin}" 2>/dev/null |
      sed -nE 's#^(git@|ssh://git@|https://)github\.com[:/]([^/]+/[^/]+)$#\2#p')
    gh_repo=${gh_repo%.git}
  fi
  [ -n "$self" ] && [ "$(git -C "$path" rev-parse --show-toplevel 2>/dev/null)" = "$self" ] && self_name=$name
  printf '%s\t%s\t%s\n' "$name" "$path" "$gh_repo" >>"$T/repos"
done <"$T/conf"
if [ -n "$self" ] && [ -z "$self_name" ]; then
  self_name=$(basename "$self")
  gh_repo=$(git remote get-url origin 2>/dev/null | sed -nE 's#^(git@|ssh://git@|https://)github\.com[:/]([^/]+/[^/]+)$#\2#p')
  printf '%s\t%s\t%s\n' "$self_name" . "${gh_repo%.git}" >>"$T/repos"
fi

# The PRs of each GitHub repo, once per repo: @tsv escapes a tab, a newline and a backslash as items.sh does. Those
# read are kept for the next --offline build, with the time they were read.
: >"$T/prs" && : >"$T/prs-read" && : >"$T/read-now"
cut -f3 "$T/repos" | grep -v '^$' | awk '!seen[$0]++' >"$T/ghs"
while IFS= read -r gh_repo; do
  names=$(awk -F '\t' -v g="$gh_repo" '$3 == g { printf "%s%s", (n++ ? ", " : ""), $1 }' "$T/repos")
  if [ "$offline" = 1 ]; then
    st="not read: --offline"
    read_at=$(awk -F '\t' -v g="$gh_repo" '$1 == g { print $2; exit }' "$cache.read" 2>/dev/null)
    if [ -n "$read_at" ]; then
      st="ok: as read $read_at"
      awk -F '\t' -v r="$names" -v g="$gh_repo" 'BEGIN { OFS = "\t" } $2 == g { $1 = r; print }' "$cache" >>"$T/prs"
    fi
  elif ! command -v gh >/dev/null 2>&1; then st="not read: gh is not installed"
  elif with_timeout 30 gh pr list -R "$gh_repo" --state all --limit 500 \
    --json number,title,state,headRefName,baseRefName,createdAt,mergedAt,closedAt,url,author,mergeCommit,body \
    --jq '.[] | [.number, .title, .state, .headRefName, .baseRefName, .createdAt, (.mergedAt // ""),
      (.closedAt // ""), .url, (.author.login // ""), (.mergeCommit.oid // ""), (.body // "")] | @tsv' \
    >"$T/pr" 2>"$T/pr.err" </dev/null; then
    st="ok"
    [ "$(wc -l <"$T/pr" | tr -d ' ')" -ge 500 ] && st="ok: the 500 latest only"
    awk -v r="$names" -v g="$gh_repo" '{ print r "\t" g "\t" $0 }' "$T/pr" >>"$T/prs"
    printf '%s\t%s\n' "$gh_repo" "$(date '+%Y-%m-%d %H:%M')" >>"$T/read-now"
  else
    st="UNKNOWN: gh pr list failed: $(head -1 "$T/pr.err" | tr '\t' ' ')"
    [ -s "$T/pr.err" ] || st="UNKNOWN: gh pr list failed or timed out"
  fi
  printf '%s\t%s\t%s\n' "$names" "$gh_repo" "$st" >>"$T/prs-read"
done <"$T/ghs"
if [ -s "$T/read-now" ]; then # keep what was read now, and what an earlier build read of the other repos
  { awk -F '\t' 'NR == FNR { now[$1] = 1; next } !($2 in now)' "$T/read-now" "$cache" 2>/dev/null
    awk -F '\t' 'NR == FNR { now[$1] = 1; next } $2 in now' "$T/read-now" "$T/prs"; } >"$T/cache"
  { cat "$T/read-now"; awk -F '\t' 'NR == FNR { now[$1] = 1; next } !($1 in now)' "$T/read-now" "$cache.read" 2>/dev/null; } \
    >"$T/cache.read"
  mv -f "$T/cache" "$cache" && mv -f "$T/cache.read" "$cache.read"
fi

# The commits: the history's, every commit of each repo that names an id, then every hash quoted in the text, each
# described once, in the first repo that has it.
: >"$T/commits"
describe() { # <repo name> <path> <file of hashes>
  [ -s "$3" ] || return 0
  git -C "$2" log --no-walk=unsorted --stdin --date=short --name-status \
    --format='%x1e%H%x1f%h%x1f%cd%x1f%an%x1f%s%x1f%b%x1f' <"$3" 2>/dev/null |
    awk -v repo="$1" 'BEGIN { RS = "\036"; FS = "\037" } NF >= 7 { printf "%s\037%s\036", repo, $0 }' >>"$T/commits"
}
new_only() { # the hashes in want that no repo has described yet, in want2
  awk 'BEGIN { RS = "\036"; FS = "\037" } NF >= 7 { print $2 }' "$T/commits" >"$T/have"
  awk 'FILENAME == ARGV[1] { have[$0] = 1; next } !($0 in have)' "$T/have" "$T/want" >"$T/want2"
}
idre='(^|[^A-Za-z0-9-])[BQLH]-[1-9][0-9]*([^0-9]|$)'
while IFS="$tab" read -r name path gh_repo; do
  {
    [ "$name" = "$self_name" ] && awk -F '\t' '$3 != "" { print $3 }' "$T/versions"
    git -C "$path" log --all -E --grep="$idre" --format=%H 2>/dev/null
  } | awk '!seen[$0]++' >"$T/want"
  new_only
  describe "$name" "$path" "$T/want2"
done <"$T/repos"
cat "$T/now" "$T/hist" "$T/prs" "$T/commits" 2>/dev/null | awk '
  { gsub(/\\[nt]/, " "); gsub(/[^0-9A-Za-z]/, " "); n = split($0, w, " ")
    for (i = 1; i <= n; i++) if (length(w[i]) >= 7 && length(w[i]) <= 40 && w[i] ~ /^[0-9a-f]+$/ && !seen[w[i]]++) print w[i] }
' >"$T/tokens"
if [ -s "$T/tokens" ]; then
  while IFS="$tab" read -r name path gh_repo; do
    awk '{ print $0 "^{commit}" }' "$T/tokens" | git -C "$path" cat-file --batch-check='%(objectname) %(objecttype)' 2>/dev/null |
      awk '$2 == "commit" { print $1 }' | awk '!seen[$0]++' >"$T/want"
    new_only
    describe "$name" "$path" "$T/want2"
  done <"$T/repos"
fi

# The data: one JSON object, one item per line. An item's events come from comparing each version with the one
# before: added, changed (and how), closed when a version no longer has it, reopened when a later one has it again.
# Text from items.sh is already escaped for JSON but for its quotes; "</" is cut so the page's script cannot end early.
awk -v vfile="$T/versions" -v hfile="$T/hist" -v project="$project" -v head="$head" -v repos="$repos" \
  -v generated="$(date '+%Y-%m-%d %H:%M')" '
function swap(s, a, b,   out, i) {
  out = ""
  while ((i = index(s, a)) > 0) { out = out substr(s, 1, i - 1) b; s = substr(s, i + length(a)) }
  return out s
}
function je(s) { return "\"" swap(swap(swap(s, "\"", "\\\""), "</", "<\\/"), "*/", "*\\/") "\"" }
function js(s) { return je(swap(swap(swap(swap(s, "\\", "\\\\"), "\t", "\\t"), "\n", "\\n"), "\r", "\\r")) }
function ev(id, n, what) {
  hist[id] = hist[id] (hist[id] == "" ? "" : ",") "[" js(vday[n]) "," js(vsha[n]) "," js(vsubj[n]) "," js(what) "]"
  if (!(id in added)) added[id] = vday[n]
  changed[id] = vday[n]
  closed[id] = (what == "closed") ? n : 0
}
function claimed(fields) { return index(fields, "claimed: ") == 1 || index(fields, "\\nclaimed: ") > 0 }
function how(a, b,   A, B, out) { # A and B: state, cross, section, title, fields, body
  split(a, A, "\t"); split(b, B, "\t"); out = ""
  if (A[1] != B[1]) out = out ", " A[1] " → " B[1]
  if (claimed(A[5]) != claimed(B[5])) out = out (claimed(B[5]) ? ", claimed" : ", claim released")
  if (A[4] != B[4]) out = out ", renamed"
  if (A[3] != B[3]) out = out ", moved to " B[3]
  if (out == "" || A[2] != B[2] || A[6] != B[6]) out = out ", edited"
  return substr(out, 3)
}
function item(id, state, cross, section, title, fields, body, file, line, closedn) {
  printf "%s{\"kind\":%s,\"id\":%s,\"state\":%s,\"cross\":%d,\"section\":%s,\"title\":%s,\"fields\":%s,\"body\":%s,", \
    sep, js(substr(id, 1, 1)), js(id), js(state), cross, je(section), je(title), je(fields), je(body)
  printf "\"file\":%s,\"line\":%d,\"added\":%s,\"changed\":%s,\"closed\":%s,\"history\":[%s]}\n", js(file), line, \
    js(added[id]), js(changed[id]), js(closedn ? vday[closedn] : ""), hist[id]
  sep = ","
}
BEGIN { FS = "\t" }
FILENAME == vfile { N = $1 + 0; vtr[N] = $2; vsha[N] = $3; vday[N] = $4; vsubj[N] = $5; next }
FILENAME == hfile {
  if ($1 != "I") next
  n = substr($2, 1, index($2, "/") - 1) + 0
  if ((n, $4) in has) next
  has[n, $4] = $5 "\t" $6 "\t" $7 "\t" $8 "\t" $9 "\t" $10; ids[n] = ids[n] " " $4; lastn[$4] = n
  next
}
{ now[++nn] = $0; if ($1 == "I") current[$4] = 1 }
END {
  for (n = 1; n <= N; n++) {
    p = prev[vtr[n]] + 0
    k = split(ids[n], L, " ")
    for (i = 1; i <= k; i++) {
      if (!p || !((p, L[i]) in has)) ev(L[i], n, (L[i] in added) ? "reopened" : "added")
      else if (has[p, L[i]] != has[n, L[i]]) ev(L[i], n, how(has[p, L[i]], has[n, L[i]]))
    }
    if (p) { k = split(ids[p], L, " "); for (i = 1; i <= k; i++) if (!((n, L[i]) in has)) ev(L[i], n, "closed") }
    prev[vtr[n]] = n
  }
  printf "{\"project\":%s,\"generated\":%s,\"head\":%s,\"git\":%s,\"repos\":[", js(project), js(generated), js(head), \
    N ? "true" : "false"
  k = split(repos, L, " "); for (i = 1; i <= k; i++) printf "%s%s", (i > 1 ? "," : ""), js(L[i])
  printf "],\n\"items\":[\n"
  for (i = 1; i <= nn; i++) {
    split(now[i], F, "\t")
    if (F[1] == "I") item(F[4], F[5], F[6], F[7], F[8], F[9], F[10], F[2], F[3], 0)
  }
  for (id in lastn) if (!(id in current) && closed[id]) {
    split(has[lastn[id], id], F, "\t")
    item(id, F[1], F[2], F[3], F[4], F[5], F[6], vtr[lastn[id]], 0, closed[id])
  }
  printf "],\n\"problems\":["; sep = ""
  for (i = 1; i <= nn; i++) {
    split(now[i], F, "\t")
    if (F[1] != "P" && F[1] != "U") continue
    printf "%s\n{\"type\":%s,\"file\":%s,\"line\":%d,\"text\":%s}", sep, js(F[1]), js(F[2]), F[3], \
      (F[2] == "" ? js(F[4]) : je(F[4]))
    sep = ","
  }
  printf "],\n"
}
' "$T/versions" "$T/hist" "$T/now" >"$T/data.json" || { echo "UNKNOWN: building the data failed"; exit 2; }

# The commits, the PRs and whether each repo's PRs could be read. A PR's text comes escaped by @tsv: quotes only.
awk -v cfile="$T/commits" -v pfile="$T/prs" -v rfile="$T/prs-read" '
function swap(s, a, b,   out, i) {
  out = ""
  while ((i = index(s, a)) > 0) { out = out substr(s, 1, i - 1) b; s = substr(s, i + length(a)) }
  return out s
}
function je(s) { return "\"" swap(swap(swap(s, "\"", "\\\""), "</", "<\\/"), "*/", "*\\/") "\"" }
function js(s) { return je(swap(swap(swap(swap(s, "\\", "\\\\"), "\t", "\\t"), "\n", "\\n"), "\r", "\\r")) }
function trim(s) { sub(/^\n+/, "", s); sub(/\n+$/, "", s); return s }
BEGIN {
  printf "\"commits\":["; sep = ""; RS = "\036"
  while ((getline rec < cfile) > 0) {
    if (split(rec, F, "\037") < 8) continue
    printf "%s\n{\"sha\":%s,\"repo\":%s,\"date\":%s,\"author\":%s,\"subject\":%s,\"body\":%s,\"files\":%s}", sep, \
      js(F[2]), js(F[1]), js(F[4]), js(F[5]), js(F[6]), js(trim(F[7])), js(trim(F[8]))
    sep = ","
  }
  printf "],\n\"prs\":["; sep = ""; RS = "\n"
  while ((getline rec < pfile) > 0) {
    if (split(rec, F, "\t") < 14) continue
    printf "%s\n{\"repo\":%s,\"gh\":%s,\"number\":%d,\"title\":%s,\"state\":%s,\"branch\":%s,\"base\":%s,", sep, \
      je(F[1]), je(F[2]), F[3], je(F[4]), je(F[5]), je(F[6]), je(F[7])
    printf "\"created\":%s,\"merged\":%s,\"closed\":%s,\"url\":%s,\"author\":%s,\"merge\":%s,\"body\":%s}", \
      je(substr(F[8], 1, 10)), je(substr(F[9], 1, 10)), je(substr(F[10], 1, 10)), je(F[11]), je(F[12]), je(F[13]), je(F[14])
    sep = ","
  }
  printf "],\n\"prsRead\":["; sep = ""
  while ((getline rec < rfile) > 0) {
    split(rec, F, "\t")
    printf "%s{\"repo\":%s,\"gh\":%s,\"status\":%s}", sep, js(F[1]), js(F[2]), js(F[3]); sep = ","
  }
  printf "]}\n"
}' >>"$T/data.json" || { echo "UNKNOWN: building the data failed"; exit 2; }

# The build's stamp: the data without the time it was built, so a rebuild that changes nothing leaves an open page
# alone. In the data, "*/" is written "*\/" (as "</" is "<\/"): read as a script, the page is a comment up to its last
# line, the only "*/" in it.
stamp=$(sed 's/"generated":"[^"]*"//' "$T/data.json" | cksum | awk '{ print $1 }')

{
  printf '%s\n' '<!-- An open board loads this file as a script to see whether it was rebuilt: then this line is a comment,' \
    "window.boardStamp = \"$stamp\"; /*" '-->'
  cat <<'PAGE'
<!doctype html>
PAGE
  printf '<html lang="en" data-stamp="%s">\n' "$stamp"
  cat <<'PAGE'
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Board</title>
<style>
:root {
  --bg: #ffffff; --fg: #1f2328; --muted: #656d76; --line: #d8dee4; --soft: #f6f8fa; --accent: #0969da;
  --on: #ddf4ff; --warn: #9a6700; --warnbg: #fff8c5;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0d1117; --fg: #e6edf3; --muted: #8d96a0; --line: #30363d; --soft: #161b22; --accent: #4493f8;
    --on: #0c2d6b; --warn: #d29922; --warnbg: #2e2a1a;
  }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--fg); font: 14px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif; }
header { padding: 14px 16px 6px; display: flex; flex-wrap: wrap; align-items: baseline; gap: 4px 14px; }
h1 { font-size: 18px; margin: 0; }
.muted { color: var(--muted); }
.bar { padding: 6px 16px; display: flex; flex-wrap: wrap; align-items: center; gap: 6px 8px; }
.bar > b { font-weight: 600; margin-right: 2px; }
.sep { width: 1px; align-self: stretch; background: var(--line); margin: 0 6px; }
.chip { border: 1px solid var(--line); background: var(--bg); color: var(--fg); border-radius: 999px; padding: 2px 10px;
  font: inherit; cursor: pointer; }
.chip.on { background: var(--on); border-color: var(--accent); }
.chip .n { color: var(--muted); margin-left: 4px; }
.tabs { display: flex; gap: 2px; padding: 8px 16px 0; border-bottom: 1px solid var(--line); }
.tab { border: 1px solid transparent; border-bottom: none; background: none; color: var(--muted); font: inherit;
  font-weight: 600; padding: 6px 14px; cursor: pointer; border-radius: 6px 6px 0 0; }
.tab.on { color: var(--fg); border-color: var(--line); background: var(--bg); margin-bottom: -1px; }
input, select { font: inherit; color: var(--fg); background: var(--bg); border: 1px solid var(--line); border-radius: 6px;
  padding: 2px 6px; }
input[type=search] { width: 16em; }
a { color: var(--accent); }
.main { display: grid; grid-template-columns: minmax(0, 1fr); }
.main.open { grid-template-columns: minmax(0, 1fr) minmax(320px, 42%); }
table { width: 100%; border-collapse: collapse; }
th, td { text-align: left; padding: 6px 8px; border-bottom: 1px solid var(--line); vertical-align: top; }
th { font-weight: 600; color: var(--muted); position: sticky; top: 0; background: var(--bg); }
tr.row { cursor: pointer; }
tr.row:hover { background: var(--soft); }
tr.row.sel { background: var(--on); }
tr.closed td { color: var(--muted); }
td.id, td.date, td.st { white-space: nowrap; font-variant-numeric: tabular-nums; }
.tag { display: inline-block; border: 1px solid var(--line); border-radius: 4px; padding: 0 5px; margin: 0 3px 2px 0;
  font-size: 12px; white-space: nowrap; }
.tablewrap { padding: 0 8px 16px; overflow-x: auto; }
aside { border-left: 1px solid var(--line); padding: 12px 16px 24px; position: sticky; top: 0; height: 100vh; overflow: auto;
  background: var(--soft); }
aside h2 { font-size: 16px; margin: 4px 0 8px; }
aside .close { float: right; }
.body { white-space: pre-wrap; overflow-wrap: anywhere; margin: 10px 0; }
code { font: 12.5px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; background: var(--bg);
  border: 1px solid var(--line); border-radius: 4px; padding: 0 3px; }
dl { display: grid; grid-template-columns: max-content 1fr; gap: 2px 10px; margin: 8px 0; }
dt { color: var(--muted); }
dd { margin: 0; }
ol.hist { padding-left: 18px; margin: 4px 0; }
ol.hist li { margin-bottom: 4px; }
details.msg { margin: 2px 0 6px; }
details.msg summary { cursor: pointer; color: var(--muted); font-size: 12px; }
details.msg .body { margin: 4px 0; }
pre.files { white-space: pre-wrap; font: 12px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; margin: 4px 0 10px; }
.note { margin: 4px 16px; color: var(--warn); }
.problems { margin: 8px 16px; padding: 8px 12px; border: 1px solid var(--warn); background: var(--warnbg); border-radius: 6px; }
.problems summary { cursor: pointer; color: var(--warn); font-weight: 600; }
.problems pre { white-space: pre-wrap; margin: 6px 0; }
.empty { padding: 24px 16px; color: var(--muted); }
footer { padding: 8px 16px 20px; color: var(--muted); font-size: 12px; }
@media (max-width: 760px) {
  .main.open { grid-template-columns: minmax(0, 1fr); }
  aside { position: fixed; inset: 0; height: auto; z-index: 2; border-left: none; }
  td.hide-s, th.hide-s { display: none; }
}
</style>
</head>
<body>
<header>
  <h1 id="title">Board</h1>
  <span class="muted" id="meta"></span>
  <span class="muted" id="live"></span>
</header>
<div class="bar" id="repos"></div>
<nav class="tabs" id="tabs"></nav>
<div class="bar" id="states"></div>
<div class="bar">
  <b>Date</b>
  <select id="dk"></select>
  <label>from <input type="date" id="from"></label>
  <label>to <input type="date" id="to"></label>
  <span class="sep"></span>
  <input type="search" id="q" placeholder="Search id, title, text">
  <select id="sort">
    <option value="old">Oldest first</option>
    <option value="new">Newest first</option>
    <option value="changed">Last changed first</option>
  </select>
  <button class="chip" id="reset">Reset filters</button>
</div>
<div id="problems"></div>
<div id="prnote"></div>
<div class="main" id="main">
  <div class="tablewrap" id="list"></div>
  <aside id="panel" hidden></aside>
</div>
<footer id="foot"></footer>
<script id="data" type="application/json">
PAGE
  cat "$T/data.json"
  cat <<'PAGE'
</script>
<script>
"use strict";
var D;
try { D = JSON.parse(document.getElementById("data").textContent); }
catch (e) { document.body.textContent = "The board data could not be read: " + e; throw e; }

var KINDS = { B: "Backlog", Q: "Questions", L: "Lessons", H: "Handoffs" };
var FILES = { B: "BACKLOG.md", Q: "questions.md", L: "notes/lessons.md", H: "notes/handoff" };
var STATES = {
  B: [["open", "🔲", "open"], ["claimed", "🔲", "claimed"], ["waiting", "⏸️", "waiting"], ["closed", "✓", "closed"]],
  Q: [["question", "💬", "open question"], ["waiting", "⏸️", "deferred"], ["ruling", "🟢", "ruling"], ["closed", "✓", "closed"]],
  L: [["lesson", "📘", "holds"], ["closed", "✗", "dropped"]],
  H: [["handoff", "📍", "live"], ["closed", "↩", "replaced"]]
};
var DATES = { B: [["added", "added"], ["changed", "last changed"], ["closed", "closed"]],
  Q: [["added", "added"], ["changed", "last changed"], ["ruled", "ruled"], ["closed", "closed"]],
  L: [["added", "added"], ["changed", "last changed"], ["closed", "dropped"]],
  H: [["added", "written"], ["closed", "replaced"]] };
var IDS = /\b([BQLH]-[1-9][0-9]*)\b/g;
var NOREPO = "(no repo)", MULTI = "(several)";

var byId = {};
var known = D.repos.slice();
D.items.forEach(function (it) {
  it.f = {};
  (it.fields || "").split("\n").forEach(function (l) {
    var i = l.indexOf(":");
    if (i > 0) it.f[l.slice(0, i)] = l.slice(i + 1).trim();
  });
  it.status = it.closed ? "closed" : (it.kind === "B" && it.f.claimed ? "claimed" : it.state);
  it.old = it.id.indexOf("H~") === 0; // a handoff written before handoffs had ids
  it.num = it.old ? 0 : parseInt(it.id.slice(2), 10);
  it.ruled = it.f.ruled || "";
  if (it.f.repos) it.repos = it.f.repos.split(/\s*(?:→|->|,)\s*|\s+/).filter(Boolean);
  else if (D.repos.length === 1) it.repos = [D.repos[0]];
  else {
    var w = (it.section || "").split(/[\s(:/]/)[0];
    it.repos = D.repos.indexOf(w) >= 0 ? [w] : [];
  }
  it.repos.forEach(function (r) { if (known.indexOf(r) < 0) known.push(r); });
  it.text = (it.id + " " + it.title + " " + it.fields + " " + it.body + " " + it.section).toLowerCase();
  if (!byId[it.id] || !it.closed) byId[it.id] = it;
});
// Commits by hash, PRs by repo and number; which commits and PRs name each item, which PRs each item names.
var commits = {}, shas = [];
D.commits.forEach(function (c) { if (!commits[c.sha]) { commits[c.sha] = c; shas.push(c.sha); } });
var prefix = {};
function commitOf(h) { // a full or short hash, or ""
  if (!h) return "";
  if (commits[h]) return h;
  if (!(h in prefix)) {
    var m = shas.filter(function (s) { return s.indexOf(h) === 0; });
    prefix[h] = m.length === 1 ? m[0] : "";
  }
  return prefix[h];
}
function idsIn(s) { var o = {}; (String(s).match(IDS) || []).forEach(function (m) { o[m] = 1; }); return Object.keys(o); }
var namedBy = {}; // id -> commits whose message names it
D.commits.forEach(function (c) {
  idsIn(c.subject + "\n" + c.body).forEach(function (id) { (namedBy[id] = namedBy[id] || []).push(c); });
});
var prs = {}, prByNum = {};
D.prs.forEach(function (pr) {
  pr.key = pr.gh + "#" + pr.number;
  pr.names = pr.repo.split(", ");
  pr.ids = idsIn(pr.title + "\n" + pr.body + "\n" + pr.branch);
  prs[pr.key] = pr;
  (prByNum[pr.number] = prByNum[pr.number] || []).push(pr);
});
function prsOf(it) { // PRs that name the item, and PRs the item names by #number, in its repos
  var out = D.prs.filter(function (pr) { return pr.ids.indexOf(it.id) >= 0; });
  (it.body.match(/(^|[^&\w])#([1-9][0-9]*)\b/g) || []).forEach(function (m) {
    (prByNum[m.replace(/^[^#]*#/, "")] || []).forEach(function (pr) {
      var mine = !it.repos.length || pr.names.some(function (r) { return it.repos.indexOf(r) >= 0; });
      if (mine && out.indexOf(pr) < 0) out.push(pr);
    });
  });
  return out;
}

// Which handoffs name each item: the "continuous" link from a handoff back to the work it ordered.
var citedBy = {};
D.items.forEach(function (it) {
  if (it.kind !== "H") return;
  var seen = {};
  (it.body.match(IDS) || []).forEach(function (m) {
    if (seen[m]) return;
    seen[m] = 1;
    (citedBy[m] = citedBy[m] || []).push(it);
  });
});

// The view: kept in the address (#...), so a reload after a new run keeps the filters.
var S;
function defaults() {
  return { tab: "B", repos: [],
    st: { B: ["open", "claimed", "waiting"], Q: ["question", "waiting", "ruling"], L: ["lesson"], H: ["handoff", "closed"] },
    dk: "changed", from: "", to: "", q: "", sort: "old", sel: "", back: "" };
}
function load() {
  S = defaults();
  try {
    var h = new URLSearchParams(location.hash.slice(1));
    if (h.get("tab") in KINDS) S.tab = h.get("tab");
    if (h.has("repos")) S.repos = h.get("repos").split(",").filter(Boolean);
    Object.keys(KINDS).forEach(function (k) { if (h.has("st" + k)) S.st[k] = h.get("st" + k).split(",").filter(Boolean); });
    ["dk", "from", "to", "q", "sort", "sel", "back"].forEach(function (k) { if (h.has(k)) S[k] = h.get(k); });
  } catch (e) { S = defaults(); }
}
function save() {
  var h = new URLSearchParams();
  h.set("tab", S.tab);
  if (S.repos.length) h.set("repos", S.repos.join(","));
  Object.keys(KINDS).forEach(function (k) { h.set("st" + k, S.st[k].join(",")); });
  ["dk", "from", "to", "q", "sort", "sel", "back"].forEach(function (k) { if (S[k]) h.set(k, S[k]); });
  try { history.replaceState(null, "", "#" + h.toString()); } catch (e) {} // a browser that refuses it on file:
}

function inRepos(it) {
  if (!S.repos.length) return true;
  return S.repos.some(function (r) {
    if (r === NOREPO) return it.repos.length === 0;
    if (r === MULTI) return it.repos.length > 1;
    return it.repos.indexOf(r) >= 0;
  });
}
function inStates(it) { return S.st[it.kind].indexOf(it.status) >= 0; }
function inDates(it) {
  if (!S.from && !S.to) return true;
  var d = it[S.dk] || "";
  if (!d) return false;
  return (!S.from || d >= S.from) && (!S.to || d <= S.to);
}
function inText(it) {
  var q = S.q.trim().toLowerCase();
  return !q || q.split(/\s+/).every(function (w) { return it.text.indexOf(w) >= 0; });
}
function shown(it, skip) {
  return (skip === "repos" || inRepos(it)) && (skip === "states" || inStates(it)) && inDates(it) && inText(it);
}

function esc(s) {
  return String(s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;" }[c]; });
}
function fmt(s) { // the little markdown the trackers use: `code`, **bold**; ids, commit hashes and #PRs as links
  return esc(s).replace(/`([^`\n]+)`/g, "<code>$1</code>").replace(/[*][*]([^*\n]+)[*][*]/g, "<b>$1</b>")
    .replace(/\b[0-9a-f]{7,40}\b/g, function (m) {
      var c = commitOf(m);
      return c ? "<a href=\"#\" data-commit=\"" + c + "\">" + m + "</a>" : m;
    })
    .replace(/(^|[\s(\[])#([1-9][0-9]*)\b/g, function (m, pre, n) {
      var l = prByNum[n] || [];
      return l.length === 1 ? pre + "<a href=\"#\" data-pr=\"" + esc(l[0].key) + "\">#" + n + "</a>" : m;
    })
    .replace(IDS, function (m) { return byId[m] ? "<a href=\"#\" data-id=\"" + m + "\">" + m + "</a>" : m; });
}
function fmtBody(s) { // a line wrapped in the markdown joins the one before, as markdown renders it
  var out = "", fence = false, joinable = false;
  s.split("\n").forEach(function (l) {
    var isFence = /^\s*(```|~~~)/.test(l);
    if (isFence) fence = !fence;
    var cont = joinable && !isFence && !fence && l.trim() !== "" && !/^\s*([-*+] |\d+[.)] |\||>|#|Done when:)/.test(l);
    out += out === "" ? l : cont ? " " + l.trim() : "\n" + l;
    joinable = !isFence && !fence && l.trim() !== "" && !/^\s*(\||#)/.test(l);
  });
  return fmt(out).replace(/^#{1,6} (.*)$/gm, "<b>$1</b>"); // a heading in a body (a handoff's sections)
}
function idOf(it) { return it.old ? "1.x" : it.id; }
function when(it) { return it.old ? it.id.slice(2) : it.added || ""; } // a 1.x handoff: the date and time in its id
function newest(a, b) { return b.num - a.num || when(b).localeCompare(when(a)); }
function stateOf(it) {
  var s = STATES[it.kind].filter(function (x) { return x[0] === it.status; })[0] || ["", "", it.status];
  return s[1] + " " + s[2] + (it.cross ? " ⚠" : "");
}
function chip(label, n, on, attrs) {
  return "<button class=\"chip" + (on ? " on" : "") + "\" " + attrs + ">" + esc(label) +
    (n === null ? "" : "<span class=\"n\">" + n + "</span>") + "</button>";
}

function render() {
  save();
  var tabItems = D.items.filter(function (it) { return it.kind === S.tab; });
  document.title = D.project + " board";
  document.getElementById("title").textContent = D.project + " board";
  document.getElementById("meta").textContent = "built " + D.generated + (D.head ? " at " + D.head : "") +
    (D.git ? "" : " · no git history: no dates, no closed items") + " · read-only: the trackers are the source";

  // Repos: how many the project has, and how many items each holds with the other filters applied.
  var cnt = function (pred) { return tabItems.filter(function (it) { return shown(it, "repos") && pred(it); }).length; };
  var h = "<b>Repos (" + D.repos.length + ")</b>";
  known.forEach(function (r) {
    h += chip(r, cnt(function (it) { return it.repos.indexOf(r) >= 0; }), S.repos.indexOf(r) >= 0,
      "data-repo=\"" + esc(r) + "\"" + (D.repos.indexOf(r) < 0 ? " title=\"not in .claude/ground-truth.conf\"" : ""));
  });
  h += "<span class=\"sep\"></span>";
  h += chip("several repos", cnt(function (it) { return it.repos.length > 1; }), S.repos.indexOf(MULTI) >= 0,
    "data-repo=\"" + MULTI + "\" title=\"items that name more than one repo\"");
  if (D.items.some(function (it) { return it.repos.length === 0; }))
    h += chip("no repo", cnt(function (it) { return it.repos.length === 0; }), S.repos.indexOf(NOREPO) >= 0,
      "data-repo=\"" + NOREPO + "\" title=\"no repos: line, and the section names no repo\"");
  document.getElementById("repos").innerHTML = h;

  h = "";
  Object.keys(KINDS).forEach(function (k) {
    var n = D.items.filter(function (it) { return it.kind === k && shown(it); }).length;
    h += "<button class=\"tab" + (S.tab === k ? " on" : "") + "\" data-tab=\"" + k + "\">" + KINDS[k] +
      " <span class=\"muted\">" + n + "</span></button>";
  });
  document.getElementById("tabs").innerHTML = h;

  h = "<b>State</b>";
  STATES[S.tab].forEach(function (s) {
    var n = tabItems.filter(function (it) { return shown(it, "states") && it.status === s[0]; }).length;
    h += chip(s[1] + " " + s[2], n, S.st[S.tab].indexOf(s[0]) >= 0, "data-state=\"" + s[0] + "\"");
  });
  document.getElementById("states").innerHTML = h;

  var dk = document.getElementById("dk");
  if (!DATES[S.tab].some(function (d) { return d[0] === S.dk; })) S.dk = "changed";
  dk.innerHTML = DATES[S.tab].map(function (d) {
    return "<option value=\"" + d[0] + "\"" + (S.dk === d[0] ? " selected" : "") + ">" + d[1] + "</option>";
  }).join("");
  document.getElementById("from").value = S.from;
  document.getElementById("to").value = S.to;
  if (document.activeElement !== document.getElementById("q")) document.getElementById("q").value = S.q;
  document.getElementById("sort").value = S.sort;

  var probs = D.problems.filter(function (p) { return !p.file || p.file.indexOf(FILES[S.tab]) === 0; });
  document.getElementById("problems").innerHTML = !probs.length ? "" :
    "<details class=\"problems\"><summary>" + probs.length + " problem(s) in " + FILES[S.tab] +
    ": not in its format (" + (S.tab === "H" ? "notes/handoff-format.md" : "notes/item-format.md") + ")</summary>" + probs.map(function (p) {
      return p.type === "U" ? "<div>" + esc(p.file + ":" + p.line) + ": not read as an item, shown as written:</div><pre>" +
        esc(p.text) + "</pre>" : "<div>" + esc((p.file ? p.file + ":" + p.line + ": " : "") + p.text) + "</div>";
    }).join("") + "</details>";

  var unread = D.prsRead.filter(function (r) { return r.status.indexOf("ok") !== 0; });
  var asRead = D.prsRead.filter(function (r) { return r.status.indexOf("ok: as read ") === 0; });
  document.getElementById("prnote").innerHTML = (!unread.length ? (D.prsRead.length ? "" :
    "<div class=\"note muted\">No GitHub repo in .claude/ground-truth.conf: no PRs.</div>") : unread.map(function (r) {
      return "<div class=\"note\">PRs of " + esc(r.repo) + " (" + esc(r.gh) + ") " + esc(r.status) + ": an item may have PRs not shown.</div>";
    }).join("")) + asRead.map(function (r) {
      return "<div class=\"note muted\">PRs of " + esc(r.repo) + " " + esc(r.status.slice(4)) + ".</div>";
    }).join("");
  var rows = tabItems.filter(function (it) { return shown(it); });
  rows.sort(function (a, b) {
    var byAdded = when(a).localeCompare(when(b)); // orders the handoffs that have no id
    if (S.sort === "changed") return (b.changed || "").localeCompare(a.changed || "") || b.num - a.num || -byAdded;
    return S.sort === "new" ? b.num - a.num || -byAdded : a.num - b.num || byAdded;
  });
  h = !rows.length ? "<div class=\"empty\">No item matches these filters.</div>" :
    "<table><thead><tr><th>Id</th><th>State</th><th>Title</th><th>Repos</th><th class=\"hide-s\">Added</th>" +
    "<th class=\"hide-s\">" + (S.dk === "ruled" ? "Ruled" : "Changed") + "</th></tr></thead><tbody>" +
    rows.map(function (it) {
      return "<tr class=\"row" + (it.closed ? " closed" : "") + (S.sel === it.id ? " sel" : "") + "\" data-id=\"" + it.id + "\">" +
        "<td class=\"id\"" + (it.old ? " title=\"written before handoffs had ids\"" : "") + ">" + idOf(it) + "</td><td class=\"st\">" + esc(stateOf(it)) + "</td><td>" + fmt(it.title) + "</td><td>" +
        it.repos.map(function (r) { return "<span class=\"tag\">" + esc(r) + "</span>"; }).join("") + "</td>" +
        "<td class=\"date hide-s\">" + esc(it.added || "") + "</td><td class=\"date hide-s\">" +
        esc((S.dk === "ruled" ? it.ruled : it.closed || it.changed) || "") + "</td></tr>";
    }).join("") + "</tbody></table>";
  document.getElementById("list").innerHTML = h;
  document.getElementById("foot").textContent = rows.length + " of " + tabItems.length + " " + KINDS[S.tab].toLowerCase() +
    " shown. Built from " + FILES[S.tab] + " and its git history by board.sh: run it again to refresh.";
  panel();
}

function backLink() {
  var b = byId[S.back] ? S.back : "";
  return "<button class=\"chip close\" id=\"close\">Close</button>" +
    (b ? "<a href=\"#\" data-id=\"" + esc(b) + "\">← " + esc(idOf(byId[b])) + "</a>" : "");
}
function prLine(pr) {
  var st = pr.merged ? "merged " + pr.merged : pr.state === "OPEN" ? "open" : "closed " + pr.closed;
  return "<a href=\"#\" data-pr=\"" + esc(pr.key) + "\">" + esc(pr.repo) + " #" + pr.number + "</a> " + esc(pr.title) +
    " <span class=\"muted\">· " + esc(st) + "</span>";
}
function commitLine(c) {
  return "<a href=\"#\" data-commit=\"" + c.sha + "\"><code>" + c.sha.slice(0, 7) + "</code></a> " + esc(c.subject) +
    " <span class=\"muted\">· " + esc(c.repo) + " · " + esc(c.date) + "</span>";
}
function prose(body) { // a message body without its trailers (Co-Authored-By:, Signed-off-by:)
  return String(body || "").split("\n").filter(function (l) { return !/^[A-Z][A-Za-z-]*-by: /.test(l); }).join("\n").trim();
}
function msg(c) { return c && prose(c.body) ? "<details class=\"msg\"><summary>message</summary><div class=\"body\">" + fmtBody(c.body) + "</div></details>" : ""; }
function commitView(c) {
  var h = backLink() + "<h2>" + fmt(c.subject) + "</h2><div class=\"muted\">commit <code>" + c.sha.slice(0, 12) + "</code> · " +
    esc(c.repo) + " · " + esc(c.date) + " · " + esc(c.author) + "</div><div class=\"body\">" + (fmtBody(c.body) || "<span class=\"muted\">No message beyond its subject.</span>") + "</div>";
  if (c.files) h += "<b>Files</b><pre class=\"files\">" + esc(c.files) + "</pre>";
  var its = idsIn(c.subject + "\n" + c.body).filter(function (id) { return byId[id]; });
  if (its.length) h += "<b>Items it names</b><div class=\"body\">" + its.map(function (id) {
    return "<a href=\"#\" data-id=\"" + id + "\">" + esc(idOf(byId[id])) + "</a> " + esc(byId[id].title);
  }).join("\n") + "</div>";
  var merged = D.prs.filter(function (pr) { return pr.merge === c.sha; });
  if (merged.length) h += "<b>Merge of</b><div class=\"body\">" + merged.map(prLine).join("\n") + "</div>";
  return h;
}
function prView(pr) {
  var h = backLink() + "<h2>" + esc(pr.repo) + " #" + pr.number + " " + fmt(pr.title) + "</h2><div class=\"muted\">" +
    esc(pr.state.toLowerCase()) + " · " + esc(pr.branch) + " → " + esc(pr.base) + " · opened " + esc(pr.created) +
    (pr.merged ? " · merged " + esc(pr.merged) : pr.closed ? " · closed " + esc(pr.closed) : "") + " · " + esc(pr.author) +
    " · <a href=\"" + esc(pr.url) + "\" target=\"_blank\" rel=\"noopener\">on GitHub</a></div>" +
    "<div class=\"body\">" + (fmtBody(pr.body) || "<span class=\"muted\">No description.</span>") + "</div>";
  var mc = commitOf(pr.merge);
  if (mc) h += "<b>Merge commit</b><div class=\"body\">" + commitLine(commits[mc]) + "</div>";
  var its = pr.ids.filter(function (id) { return byId[id]; });
  if (its.length) h += "<b>Items it names</b><div class=\"body\">" + its.map(function (id) {
    return "<a href=\"#\" data-id=\"" + id + "\">" + esc(idOf(byId[id])) + "</a> " + esc(byId[id].title);
  }).join("\n") + "</div>";
  return h;
}
function panel() {
  var p = document.getElementById("panel"), sel = S.sel || "";
  var c = sel.indexOf("c:") === 0 ? commits[sel.slice(2)] : null, pr = sel.indexOf("p:") === 0 ? prs[sel.slice(2)] : null;
  var it = c || pr ? null : byId[sel];
  document.getElementById("main").classList.toggle("open", !!(it || c || pr));
  p.hidden = !(it || c || pr);
  if (c || pr) { p.innerHTML = c ? commitView(c) : prView(pr); return; }
  if (!it) return;
  var where = it.closed ? "closed on " + it.closed + "; last in " + it.file : it.file + ":" + it.line;
  var h = "<button class=\"chip close\" id=\"close\">Close</button><h2>" + idOf(it) + " " + fmt(it.title) + "</h2>" +
    "<div class=\"muted\">" + esc(stateOf(it)) + " · " + esc(where) + "</div><dl>" +
    "<dt>section</dt><dd>" + (fmt(it.section) || "—") + "</dd>" +
    (it.f.repos ? "" : "<dt>repos</dt><dd>" + (esc(it.repos.join(", ")) || "—") + "</dd>");
  Object.keys(it.f).forEach(function (k) { h += "<dt>" + esc(k) + "</dt><dd>" + fmt(it.f[k]) + "</dd>"; });
  h += "</dl><div class=\"body\">" + fmtBody(it.body) + "</div>";
  var ps = prsOf(it);
  if (ps.length) h += "<b>Pull requests</b><div class=\"body\">" + ps.map(prLine).join("\n") + "</div>";
  var by = (citedBy[it.id] || []).filter(function (x) { return x !== it; }).sort(newest);
  if (by.length) h += "<b>Named in handoffs</b><div class=\"body\">" + by.map(function (x) {
    return "<a href=\"#\" data-id=\"" + esc(x.id) + "\">" + esc(idOf(x)) + "</a> " + esc(x.title) + (x.closed ? " (replaced)" : "");
  }).join("\n") + "</div>";
  h += "<b>History</b>";
  h += !it.history.length ? "<div class=\"muted\">No commit has it yet.</div>" : "<ol class=\"hist\">" +
    it.history.slice().reverse().map(function (e) {
      var c = commits[e[1]];
      return "<li><b>" + esc(e[3]) + "</b> " + esc(e[0]) + " · " + (c ? "<a href=\"#\" data-commit=\"" + c.sha + "\"><code>" +
        e[1].slice(0, 7) + "</code></a> " : e[1] ? "<code>" + esc(e[1].slice(0, 7)) + "</code> " : "") + fmt(e[2]) + msg(c) + "</li>";
    }).join("") + "</ol>";
  var inHist = {};
  it.history.forEach(function (e) { inHist[e[1]] = 1; });
  var other = (namedBy[it.id] || []).filter(function (c) { return !inHist[c.sha]; });
  if (other.length) h += "<b>Other commits that name it</b><div class=\"body\">" + other.map(commitLine).join("\n") + "</div>";
  p.innerHTML = h;
}

document.addEventListener("click", function (e) {
  var t = e.target.closest("[data-repo],[data-tab],[data-state],[data-id],[data-commit],[data-pr],#close,#reset");
  if (!t) return;
  if (t.tagName === "A") e.preventDefault();
  var list, v;
  if (t.id === "close") { S.sel = ""; S.back = ""; }
  else if (t.dataset.commit || t.dataset.pr) {
    if (byId[S.sel]) S.back = S.sel;
    S.sel = t.dataset.commit ? "c:" + t.dataset.commit : "p:" + t.dataset.pr;
  }
  else if (t.id === "reset") { v = S.tab; S = defaults(); S.tab = v; }
  else if (t.dataset.repo) { list = S.repos; v = t.dataset.repo; }
  else if (t.dataset.state) { list = S.st[S.tab]; v = t.dataset.state; }
  else if (t.dataset.tab) { S.tab = t.dataset.tab; }
  else if (t.dataset.id) { S.sel = (S.sel === t.dataset.id && t.tagName === "TR") ? "" : t.dataset.id; S.back = ""; }
  if (list) { var i = list.indexOf(v); if (i >= 0) list.splice(i, 1); else list.push(v); }
  render();
});
document.addEventListener("keydown", function (e) { if (e.key === "Escape" && S.sel) { S.sel = ""; S.back = ""; render(); } });
["dk", "from", "to", "sort"].forEach(function (k) {
  document.getElementById(k).addEventListener("change", function (e) { S[k] = e.target.value; render(); });
});
document.getElementById("q").addEventListener("input", function (e) { S.q = e.target.value; render(); });
load();
render();

// Live: each change rebuilds this file (the hook). Every 2 s, while the tab is shown, the page loads its own file as
// a script: its first lines set window.boardStamp. A new stamp reloads the page, never while a key was pressed in
// the last 4 s. The filters are in the address; the scroll, the focus and the caret are kept across the reload.
var STAMP = document.documentElement.getAttribute("data-stamp"), typed = 0, probes = 0;
document.addEventListener("keydown", function () { typed = Date.now(); }, true);
function live(on) {
  var m = document.getElementById("live");
  m.textContent = on ? "· updates itself" : "· reload to see changes";
  m.title = on ? "This tab reloads itself when the board is rebuilt." : "This browser does not let the page read its own file.";
}
function probe() {
  if (document.hidden) return;
  window.boardStamp = undefined;
  var s = document.createElement("script");
  s.src = location.href.split(/[?#]/)[0] + "?stamp=" + (++probes);
  s.onerror = function () { s.remove(); live(false); };
  s.onload = function () {
    s.remove();
    if (typeof window.boardStamp !== "string") { live(false); return; }
    live(true);
    if (window.boardStamp === STAMP || Date.now() - typed < 4000) return;
    try {
      var a = document.activeElement, keep = { x: window.scrollX, y: window.scrollY,
        panel: document.getElementById("panel").scrollTop, list: document.getElementById("list").scrollLeft,
        focus: a && a.id ? a.id : "", caret: null };
      try { keep.caret = a.selectionStart; } catch (e) {}
      sessionStorage.setItem("board-keep", JSON.stringify(keep));
    } catch (e) {}
    location.reload();
  };
  document.head.appendChild(s);
}
try {
  var keep = JSON.parse(sessionStorage.getItem("board-keep") || "null");
  sessionStorage.removeItem("board-keep");
  if (keep) {
    window.scrollTo(keep.x, keep.y);
    document.getElementById("panel").scrollTop = keep.panel;
    document.getElementById("list").scrollLeft = keep.list;
    var f = keep.focus && document.getElementById(keep.focus);
    if (f) { f.focus(); if (keep.caret != null && f.setSelectionRange) f.setSelectionRange(keep.caret, keep.caret); }
  }
} catch (e) {}
setInterval(probe, 2000);
document.addEventListener("visibilitychange", probe);
probe();
</script>
</body>
</html>
<!-- */ -->
PAGE
} >"$T/page.html" && mv -f "$T/page.html" "$out" || { echo "UNKNOWN: cannot write $out"; exit 2; }

echo "Board: $out"

# Where no browser can show the page, nothing opens: the open items are printed instead. Under Remote Control the
# page opens on this machine and the text is printed too, for the owner who follows from another device.
away=""
if [ "${CLAUDE_CODE_REMOTE:-}" = true ]; then away="a cloud session"
elif [ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]; then away="a session over SSH"
else
  case $(uname -s) in
    Darwin | MINGW* | MSYS* | CYGWIN*) ;;
    *) if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then away="a machine with no display"
       elif ! command -v xdg-open >/dev/null 2>&1; then away="a machine with no xdg-open"; fi ;;
  esac
fi
[ "$open" = 1 ] && { [ -n "$away" ] || [ -n "${CLAUDE_CODE_BRIDGE_SESSION_ID:-}" ]; } && text=1

if [ "$text" = 1 ]; then
  echo
  awk -F '\t' -v project="$project" -v built="$(date '+%Y-%m-%d %H:%M')" '
function unesc(s) { gsub(/\\n/, " · ", s); gsub(/\\t/, " ", s); gsub(/\\\\/, "\\", s); return s }
function mark(st) {
  if (st == "open") return "🔲"; if (st == "waiting") return "⏸️"; if (st == "question") return "💬"; return st
}
$1 == "P" || $1 == "U" { problems++; next }
$1 != "I" { next }
{ k = substr($4, 1, 1) }
k == "B" {
  nb++; sec = $7
  if (!(sec in seen)) { seen[sec] = 1; order[++ns] = sec }
  line = "    " mark($5) " " ($6 == 1 ? "⚠ " : "") $4 "  " $8
  if ($9 != "") line = line "  (" unesc($9) ")"
  items[sec] = items[sec] line "\n"; next
}
k == "Q" { if ($5 == "ruling") rulings++; else { nq++; qs = qs "  " mark($5) " " $4 "  " $8 "\n" }; next }
k == "L" { nl++; next }
k == "H" { nh++; hs = hs (nh > 1 ? ", " : "") $4 " " $8 }
END {
  printf "%s: the open items, %s\n\nBACKLOG: %d open\n", project, built, nb
  for (i = 1; i <= ns; i++) printf "  %s\n%s", order[i], items[order[i]]
  printf "\nquestions.md: %d open, %d rulings\n%s", nq, rulings, qs
  printf "\nLessons: %d. Live handoffs: %s\n", nl, (nh ? hs : "none")
  if (problems) printf "\n%d problem(s) in the trackers: bash .claude/skills/session-start/items.sh check\n", problems
}' "$T/now"
  if [ -n "$away" ] && [ "$open" = 1 ]; then
    echo
    echo "The page (filters, closed items, the history of each item) cannot open in $away. On a machine with a"
    echo "browser: git pull, then /board (or bash .claude/skills/session-start/board.sh)."
  fi
fi
if [ "$open" = 1 ] && [ -z "$away" ]; then
  case $(uname -s) in
    Darwin) open "$out" ;;
    MINGW* | MSYS* | CYGWIN*) start "" "$out" ;;
    *) xdg-open "$out" >/dev/null 2>&1 & ;;
  esac
fi
exit 0
