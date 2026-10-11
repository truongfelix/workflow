#!/usr/bin/env bash
#
# board.sh — BACKLOG.md and questions.md as one read-only page: every item, filtered by repo, state, date and text,
# the closed ones included (from git), each with its history.
#
# The page is rebuilt from the markdown at each run, by items.sh (the parser of the format check) and git. It never
# writes to the trackers, which stay the only source. One self-contained HTML file: plain JavaScript, no server, no
# library, no network. Run it again to refresh.
#
# Repos: the names in .claude/ground-truth.conf. An item's repos are its `repos:` line, else its section's first word
# when that names a repo; with one repo configured, every item is in it.
# Dates: from the commits that changed each tracker (first parent only, so a merge counts once): added, last changed,
# closed (the commit that deleted the item). Edits not committed yet count as today's.
#
# Generic (from the workflow repo): upgrade this file from there; never put project data in it.
#
# Usage: bash .claude/skills/session-start/board.sh [--out <file>] [--no-open] [<project dir>]
#   <project dir>  default: the project this script is installed in
#   --out          where to write the page. Default: <temp folder>/<project>-board.html, the same file at each run
#   --no-open      only print the page's path
# Exit 0 = the page is written (problems in the trackers are shown on it). 2 = no page (UNKNOWN). 1 = usage error.

set -uo pipefail

usage() { echo "usage: $0 [--out <file>] [--no-open] [<project dir>]" >&2; exit 1; }
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SH=${BASH:-bash}
out="" open=1 dir=""
while [ $# -gt 0 ]; do
  case $1 in
    --out) [ $# -ge 2 ] || usage; out=$2; shift 2 ;;
    --no-open) open=0; shift ;;
    -*) usage ;;
    *) [ -z "$dir" ] || usage; dir=$1; shift ;;
  esac
done
[ -n "$out" ] && case $out in /*) ;; *) out="$(pwd)/$out" ;; esac
cd "${dir:-$HERE/../../..}" 2>/dev/null || { echo "UNKNOWN: cannot reach the project folder ${dir:-}"; exit 2; }

trackers=()
for f in BACKLOG.md questions.md; do [ -f "$f" ] && trackers+=("$f"); done
[ ${#trackers[@]} -gt 0 ] || { echo "UNKNOWN: no BACKLOG.md or questions.md in $(pwd)"; exit 2; }
T=$(mktemp -d "${TMPDIR:-/tmp}/board.XXXXXX") || { echo "UNKNOWN: no temp folder"; exit 2; }
trap 'rm -rf "$T"' EXIT

# The project's name: the trackers' title up to its dash ("# Pantry — Backlog"), else the folder's name.
project=$(sed -n '1s/^# *\(.*\) — .*/\1/p' "${trackers[0]}" | tr -d '\r')
[ -n "$project" ] || project=$(basename "$(pwd)")
[ -n "$out" ] || out="${TMPDIR:-/tmp}/$(printf '%s' "$project" | tr -c 'A-Za-z0-9._-' '-')-board.html"

repos=""
if [ -f .claude/ground-truth.conf ]; then
  repos=$(REPOS=(); . ./.claude/ground-truth.conf >/dev/null 2>&1
    for r in ${REPOS[@]+"${REPOS[@]}"}; do printf '%s ' "${r%%|*}"; done)
fi

# Every version of each tracker in git, oldest first, then what is on disk when it differs from the last commit.
tab=$(printf '\t')
today=$(date +%Y-%m-%d)
head=""
mkdir "$T/v" && : >"$T/versions"
versions=()
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  head=$(git rev-parse --short HEAD 2>/dev/null)
  for f in "${trackers[@]}"; do
    git log --first-parent --reverse --date=short --format="%H$tab%cd$tab%s" -- "$f" >"$T/log" 2>/dev/null
    while IFS="$tab" read -r sha day subject; do
      n=$((${#versions[@]} + 1))
      mkdir "$T/v/$n" && git show "$sha:./$f" >"$T/v/$n/$f" 2>/dev/null
      printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$f" "$sha" "$day" "${subject//$tab/ }" >>"$T/versions"
      versions+=("$n/$f")
    done <"$T/log"
    if ! git ls-files --error-unmatch -- "$f" >/dev/null 2>&1 || ! git diff --quiet HEAD -- "$f" 2>/dev/null; then
      n=$((${#versions[@]} + 1))
      mkdir "$T/v/$n" && cp "$f" "$T/v/$n/$f"
      printf '%s\t%s\t\t%s\t%s\n' "$n" "$f" "$today" "not committed yet" >>"$T/versions"
      versions+=("$n/$f")
    fi
  done
fi
: >"$T/hist"
[ ${#versions[@]} -gt 0 ] && (cd "$T/v" && "$SH" "$HERE/items.sh" list "${versions[@]}" >"$T/hist" 2>/dev/null)
"$SH" "$HERE/items.sh" list "${trackers[@]}" >"$T/now" 2>"$T/now.err"
rc=$?
if [ "$rc" != 0 ] && [ "$rc" != 2 ]; then echo "UNKNOWN: items.sh failed (exit $rc)"; cat "$T/now.err"; exit 2; fi
if [ ! -s "$T/now" ] && [ -s "$T/now.err" ]; then echo "UNKNOWN: items.sh read nothing"; cat "$T/now.err"; exit 2; fi
awk '{ print "P\t\t0\t" $0 }' "$T/now.err" >>"$T/now" # its own complaints: no file, no line

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
function je(s) { return "\"" swap(swap(s, "\"", "\\\""), "</", "<\\/") "\"" }
function js(s) { return je(swap(swap(swap(s, "\\", "\\\\"), "\t", "\\t"), "\n", "\\n")) }
function ev(id, n, what) {
  hist[id] = hist[id] (hist[id] == "" ? "" : ",") "[" js(vday[n]) "," js(substr(vsha[n], 1, 7)) "," js(vsubj[n]) "," js(what) "]"
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
  printf "]}\n"
}
' "$T/versions" "$T/hist" "$T/now" >"$T/data.json" || { echo "UNKNOWN: building the data failed"; exit 2; }

{
  cat <<'PAGE'
<!doctype html>
<html lang="en">
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

var KINDS = { B: "Backlog", Q: "Questions" };
var FILES = { B: "BACKLOG.md", Q: "questions.md" };
var STATES = {
  B: [["open", "🔲", "open"], ["claimed", "🔲", "claimed"], ["waiting", "⏸️", "waiting"], ["closed", "✓", "closed"]],
  Q: [["question", "💬", "open question"], ["waiting", "⏸️", "deferred"], ["ruling", "🟢", "ruling"], ["closed", "✓", "closed"]]
};
var DATES = { B: [["added", "added"], ["changed", "last changed"], ["closed", "closed"]],
  Q: [["added", "added"], ["changed", "last changed"], ["ruled", "ruled"], ["closed", "closed"]] };
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
  it.num = parseInt(it.id.slice(2), 10);
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

// The view: kept in the address (#...), so a reload after a new run keeps the filters.
var S;
function defaults() {
  return { tab: "B", repos: [], st: { B: ["open", "claimed", "waiting"], Q: ["question", "waiting", "ruling"] },
    dk: "changed", from: "", to: "", q: "", sort: "old", sel: "" };
}
function load() {
  S = defaults();
  try {
    var h = new URLSearchParams(location.hash.slice(1));
    if (h.get("tab") in KINDS) S.tab = h.get("tab");
    if (h.has("repos")) S.repos = h.get("repos").split(",").filter(Boolean);
    ["B", "Q"].forEach(function (k) { if (h.has("st" + k)) S.st[k] = h.get("st" + k).split(",").filter(Boolean); });
    ["dk", "from", "to", "q", "sort", "sel"].forEach(function (k) { if (h.has(k)) S[k] = h.get(k); });
  } catch (e) { S = defaults(); }
}
function save() {
  var h = new URLSearchParams();
  h.set("tab", S.tab);
  if (S.repos.length) h.set("repos", S.repos.join(","));
  h.set("stB", S.st.B.join(",")); h.set("stQ", S.st.Q.join(","));
  ["dk", "from", "to", "q", "sort", "sel"].forEach(function (k) { if (S[k]) h.set(k, S[k]); });
  try { history.replaceState(null, "", "#" + h.toString()); } catch (e) { /* a browser that refuses it on file: */ }
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
function fmt(s) { // the little markdown the trackers use: `code`, **bold**, and ids as links
  return esc(s).replace(/`([^`\n]+)`/g, "<code>$1</code>").replace(/\*\*([^*\n]+)\*\*/g, "<b>$1</b>")
    .replace(/\b([BQ]-[1-9][0-9]*)\b/g, function (m) { return byId[m] ? "<a href=\"#\" data-id=\"" + m + "\">" + m + "</a>" : m; });
}
function fmtBody(s) { // a line wrapped in the markdown joins the one before, as markdown renders it
  var out = "", fence = false, joinable = false;
  s.split("\n").forEach(function (l) {
    var isFence = /^\s*(```|~~~)/.test(l);
    if (isFence) fence = !fence;
    var cont = joinable && !isFence && !fence && l.trim() !== "" && !/^\s*([-*+] |\d+[.)] |\||>|#|Done when:)/.test(l);
    out += out === "" ? l : cont ? " " + l.trim() : "\n" + l;
    joinable = !isFence && !fence && l.trim() !== "" && !/^\s*\|/.test(l);
  });
  return fmt(out);
}
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

  var probs = D.problems.filter(function (p) { return !p.file || p.file === FILES[S.tab]; });
  document.getElementById("problems").innerHTML = !probs.length ? "" :
    "<details class=\"problems\"><summary>" + probs.length + " problem(s) in " + FILES[S.tab] +
    ": not in the item format (notes/item-format.md)</summary>" + probs.map(function (p) {
      return p.type === "U" ? "<div>" + esc(p.file + ":" + p.line) + ": not read as an item, shown as written:</div><pre>" +
        esc(p.text) + "</pre>" : "<div>" + esc((p.file ? p.file + ":" + p.line + ": " : "") + p.text) + "</div>";
    }).join("") + "</details>";

  var rows = tabItems.filter(function (it) { return shown(it); });
  rows.sort(function (a, b) {
    if (S.sort === "changed") return (b.changed || "").localeCompare(a.changed || "") || b.num - a.num;
    return S.sort === "new" ? b.num - a.num : a.num - b.num;
  });
  h = !rows.length ? "<div class=\"empty\">No item matches these filters.</div>" :
    "<table><thead><tr><th>Id</th><th>State</th><th>Title</th><th>Repos</th><th class=\"hide-s\">Added</th>" +
    "<th class=\"hide-s\">" + (S.dk === "ruled" ? "Ruled" : "Changed") + "</th></tr></thead><tbody>" +
    rows.map(function (it) {
      return "<tr class=\"row" + (it.closed ? " closed" : "") + (S.sel === it.id ? " sel" : "") + "\" data-id=\"" + it.id + "\">" +
        "<td class=\"id\">" + it.id + "</td><td class=\"st\">" + esc(stateOf(it)) + "</td><td>" + fmt(it.title) + "</td><td>" +
        it.repos.map(function (r) { return "<span class=\"tag\">" + esc(r) + "</span>"; }).join("") + "</td>" +
        "<td class=\"date hide-s\">" + esc(it.added || "") + "</td><td class=\"date hide-s\">" +
        esc((S.dk === "ruled" ? it.ruled : it.closed || it.changed) || "") + "</td></tr>";
    }).join("") + "</tbody></table>";
  document.getElementById("list").innerHTML = h;
  document.getElementById("foot").textContent = rows.length + " of " + tabItems.length + " " + KINDS[S.tab].toLowerCase() +
    " items shown. Built from " + FILES[S.tab] + " and its git history by board.sh: run it again to refresh.";
  panel();
}

function panel() {
  var it = byId[S.sel], p = document.getElementById("panel");
  document.getElementById("main").classList.toggle("open", !!it);
  p.hidden = !it;
  if (!it) return;
  var where = it.closed ? "closed on " + it.closed + "; last in " + it.file : it.file + ":" + it.line;
  var h = "<button class=\"chip close\" id=\"close\">Close</button><h2>" + it.id + " " + fmt(it.title) + "</h2>" +
    "<div class=\"muted\">" + esc(stateOf(it)) + " · " + esc(where) + "</div><dl>" +
    "<dt>section</dt><dd>" + (fmt(it.section) || "—") + "</dd>" +
    (it.f.repos ? "" : "<dt>repos</dt><dd>" + (esc(it.repos.join(", ")) || "—") + "</dd>");
  Object.keys(it.f).forEach(function (k) { h += "<dt>" + esc(k) + "</dt><dd>" + fmt(it.f[k]) + "</dd>"; });
  h += "</dl><div class=\"body\">" + fmtBody(it.body) + "</div><b>History</b>";
  h += !it.history.length ? "<div class=\"muted\">No commit has it yet.</div>" : "<ol class=\"hist\">" +
    it.history.slice().reverse().map(function (e) {
      return "<li><b>" + esc(e[3]) + "</b> " + esc(e[0]) + (e[1] ? " · <code>" + esc(e[1]) + "</code> " : " · ") + esc(e[2]) + "</li>";
    }).join("") + "</ol>";
  p.innerHTML = h;
}

document.addEventListener("click", function (e) {
  var t = e.target.closest("[data-repo],[data-tab],[data-state],[data-id],#close,#reset");
  if (!t) return;
  if (t.tagName === "A") e.preventDefault();
  var list, v;
  if (t.id === "close") S.sel = "";
  else if (t.id === "reset") { v = S.tab; S = defaults(); S.tab = v; }
  else if (t.dataset.repo) { list = S.repos; v = t.dataset.repo; }
  else if (t.dataset.state) { list = S.st[S.tab]; v = t.dataset.state; }
  else if (t.dataset.tab) { S.tab = t.dataset.tab; }
  else if (t.dataset.id) S.sel = (S.sel === t.dataset.id && t.tagName === "TR") ? "" : t.dataset.id;
  if (list) { var i = list.indexOf(v); if (i >= 0) list.splice(i, 1); else list.push(v); }
  render();
});
document.addEventListener("keydown", function (e) { if (e.key === "Escape" && S.sel) { S.sel = ""; render(); } });
["dk", "from", "to", "sort"].forEach(function (k) {
  document.getElementById(k).addEventListener("change", function (e) { S[k] = e.target.value; render(); });
});
document.getElementById("q").addEventListener("input", function (e) { S.q = e.target.value; render(); });
load();
render();
</script>
</body>
</html>
PAGE
} >"$T/page.html" && mv -f "$T/page.html" "$out" || { echo "UNKNOWN: cannot write $out"; exit 2; }

echo "Board: $out"
if [ "$open" = 1 ]; then
  case $(uname -s) in
    Darwin) open "$out" ;;
    MINGW* | MSYS* | CYGWIN*) start "" "$out" ;;
    *) if command -v xdg-open >/dev/null 2>&1; then xdg-open "$out" >/dev/null 2>&1 & fi ;;
  esac
fi
exit 0
