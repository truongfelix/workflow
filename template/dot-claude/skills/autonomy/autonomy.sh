#!/usr/bin/env bash
#
# autonomy.sh — read and set the table "What Claude does alone" in CLAUDE.md: for each step where a session could
# stop and ask, "ask first" or "do, then tell". The /autonomy skill asks the owner, then calls it; the setup does the
# same for its first answer. It rewrites the table's rows and nothing else, and once the owner has chosen it deletes
# the setup's FILL comment above the table.
#
# The presets, as the last bullet under the table defines them: Careful asks first on every row; Balanced asks first
# to start the day's task, to open or merge a pull request (or push code to a default branch), to release, and to
# comment or message, and does the rest, then tells; Hands-off asks first only to release, and to comment or message.
# A row of the project's own, which no preset names, asks first in Careful and keeps its answer in the others: a
# preset never makes a step nobody chose a step done alone.
#
# Generic (from the workflow repo): upgrade this file from there; never put project data in it.
#
# Usage: bash .claude/skills/autonomy/autonomy.sh show [-f <CLAUDE.md>]
#        bash .claude/skills/autonomy/autonomy.sh preset <careful|balanced|hands-off> [-f <CLAUDE.md>]
#        bash .claude/skills/autonomy/autonomy.sh ask|tell <step>... [-f <CLAUDE.md>]
#   show    each row as "<n>\t<step>\t<answer>", then the preset the rows make: "preset: Balanced", or "preset: none,
#           closest Careful, 2 step(s) switched: Commit the docs; Push the docs"; then the project's own rows, if any
#   preset  every row to that preset's answer, then what show prints
#   ask     those steps to "ask first"; tell: to "do, then tell"; then what show prints. A step is its number in
#           show, its text, or the start of its text when only one row starts so ("Claim an item")
#   -f      the CLAUDE.md to read; default: the project's, three folders above this script
# Exit 0 = done. 1 = usage error, or a step that is not in the table: nothing is written. 2 = no table, or a row
# answered neither "ask first" nor "do, then tell" (UNKNOWN): nothing is written.

set -uo pipefail

usage() {
  echo "usage: $0 show | preset <careful|balanced|hands-off> | ask <step>... | tell <step>...  [-f <CLAUDE.md>]" >&2
  exit 1
}
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
file="$DIR/../../../CLAUDE.md" cmd="" args=()
while [ $# -gt 0 ]; do
  case $1 in
    -f) [ $# -ge 2 ] || usage; file=$2; shift 2 ;;
    -*) usage ;;
    *) if [ -z "$cmd" ]; then cmd=$1; else args+=("$1"); fi; shift ;;
  esac
done
[ -n "$cmd" ] || usage

ASK="ask first" TELL="do, then tell"
ALL=("Start the day's task after the brief" "Commit the docs" "Push the docs" "Add an item to the backlog"
  "Claim an item (commit and push its claim line)" "Commit code" "Push a work branch" "Open a pull request"
  "Merge a pull request, or push code to a default branch" "Delete a branch or worktree whose work has landed"
  "Stop a background job this session started" "Release: tag, publish" "Comment, or message anyone")
BALANCED=("Start the day's task after the brief" "Open a pull request"
  "Merge a pull request, or push code to a default branch" "Release: tag, publish" "Comment, or message anyone")
HANDSOFF=("Release: tag, publish" "Comment, or message anyone")

in_list() { # <text> <item>...: 0 when the text is one of the items
  local t=$1 x
  shift
  for x in "$@"; do [ "$x" = "$t" ] && return 0; done
  return 1
}
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
name() { # <preset>: its name as the owner reads it
  case $1 in careful) echo Careful ;; balanced) echo Balanced ;; *) echo Hands-off ;; esac
}
preset_answer() { # <preset> <step>: the preset's answer, or nothing (the row keeps its answer)
  if ! in_list "$2" "${ALL[@]}"; then
    [ "$1" = careful ] && echo "$ASK"
    return 0
  fi
  case $1 in
    careful) echo "$ASK" ;;
    balanced) if in_list "$2" "${BALANCED[@]}"; then echo "$ASK"; else echo "$TELL"; fi ;;
    hands-off) if in_list "$2" "${HANDSOFF[@]}"; then echo "$ASK"; else echo "$TELL"; fi ;;
  esac
}

# The table: its rows between the heading "## What Claude does alone" and the next "## ", with their line numbers,
# and the setup's FILL comment above it (from its first line to the one that closes it).
[ -f "$file" ] || { echo "UNKNOWN: no $file"; exit 2; }
lns=() steps=() answers=()
ln=0 in=0 fill_from=0 fill_to=0
while IFS= read -r l || [ -n "$l" ]; do
  ln=$((ln + 1)) l=${l%$'\r'}
  case $l in
    "## What Claude does alone"*) in=1; continue ;;
    "## "*) [ "$in" = 1 ] && in=2 ;;
  esac
  [ "$in" = 1 ] || continue
  case $l in "<!-- FILL: ask the owner for a preset"*) fill_from=$ln ;; esac
  if [ "$fill_from" -gt 0 ] && [ "$fill_to" = 0 ]; then
    case $l in *"-->"*) fill_to=$ln ;; esac
  fi
  case $l in "| Step | Here |" | "|---"*) continue ;; "| "*" |") ;; *) continue ;; esac
  body=${l#| } body=${body% |}
  lns+=("$ln") steps+=("${body% | *}") answers+=("${body##* | }")
done <"$file"
[ ${#steps[@]} -gt 0 ] || { echo "UNKNOWN: no table \"What Claude does alone\" in $file"; exit 2; }
for i in "${!steps[@]}"; do
  a=${answers[$i]}
  [ "$a" = "$ASK" ] || [ "$a" = "$TELL" ] ||
    { echo "UNKNOWN: the row \"${steps[$i]}\" answers \"$a\": neither \"$ASK\" nor \"$TELL\""; exit 2; }
done

show() { # the rows, the preset they make (or the closest), the project's own rows
  local p i n diff best="" bestn=999 bestdiff="" own=""
  for i in "${!steps[@]}"; do printf '%d\t%s\t%s\n' $((i + 1)) "${steps[$i]}" "${answers[$i]}"; done
  for p in careful balanced hands-off; do
    n=0 diff=""
    for i in "${!steps[@]}"; do
      in_list "${steps[$i]}" "${ALL[@]}" || continue
      [ "$(preset_answer "$p" "${steps[$i]}")" = "${answers[$i]}" ] && continue
      n=$((n + 1)) diff="$diff${diff:+; }${steps[$i]}"
    done
    if [ "$n" -lt "$bestn" ]; then best=$p bestn=$n bestdiff=$diff; fi
  done
  if [ "$bestn" = 0 ]; then echo "preset: $(name "$best")"
  else echo "preset: none, closest $(name "$best"), $bestn step(s) switched: $bestdiff"; fi
  for i in "${!steps[@]}"; do in_list "${steps[$i]}" "${ALL[@]}" || own="$own${own:+; }${steps[$i]}"; done
  [ -z "$own" ] || echo "the project's own rows (no preset names them): $own"
}

find_step() { # <number, text or start of text>: the row's index; 1 when none, or several rows start so
  local s=$1 i hit="" lc
  case $s in
    "" | *[!0-9]*) ;;
    *) [ "$s" -ge 1 ] && [ "$s" -le ${#steps[@]} ] && { echo $((s - 1)); return 0; }; return 1 ;;
  esac
  for i in "${!steps[@]}"; do [ "${steps[$i]}" = "$s" ] && { echo "$i"; return 0; }; done
  lc=$(lower "$s")
  for i in "${!steps[@]}"; do
    case $(lower "${steps[$i]}") in "$lc"*) [ -n "$hit" ] && return 1; hit=$i ;; esac
  done
  [ -n "$hit" ] && echo "$hit"
}

write() { # the rows as answers[] says, the FILL comment and the blank line after it gone; CRLF kept
  local tmp i
  tmp=$(mktemp "${TMPDIR:-/tmp}/autonomy.XXXXXX") || { echo "UNKNOWN: mktemp failed: nothing written"; exit 2; }
  for i in "${!steps[@]}"; do printf '%s\t| %s | %s |\n' "${lns[$i]}" "${steps[$i]}" "${answers[$i]}"; done >"$tmp.map"
  if awk -v mf="$tmp.map" -v from="$fill_from" -v to="$fill_to" '
    BEGIN { while ((getline l < mf) > 0) { i = index(l, "\t"); m[substr(l, 1, i - 1)] = substr(l, i + 1) } }
    { cr = sub(/\r$/, "") ? "\r" : "" }
    from > 0 && FNR >= from && FNR <= to { gone = 1; next }
    gone == 1 && $0 == "" { gone = 2; next }
    (FNR "") in m { print m[FNR ""] cr; next }
    { print $0 cr }' "$file" >"$tmp"; then
    cat "$tmp" >"$file"
  else
    rm -f "$tmp" "$tmp.map"
    echo "UNKNOWN: the table could not be written: nothing written"
    exit 2
  fi
  rm -f "$tmp" "$tmp.map"
}

case $cmd in
  show)
    [ ${#args[@]} = 0 ] || usage
    show ;;
  preset)
    [ ${#args[@]} = 1 ] || usage
    p=$(lower "${args[0]}" | tr -cd 'a-z')
    [ "$p" = handsoff ] && p=hands-off
    in_list "$p" careful balanced hands-off || { echo "not a preset: ${args[0]} (careful, balanced, hands-off)" >&2; usage; }
    for i in "${!steps[@]}"; do
      a=$(preset_answer "$p" "${steps[$i]}")
      [ -z "$a" ] || answers[$i]=$a
    done
    write
    show ;;
  ask | tell)
    [ ${#args[@]} -ge 1 ] || usage
    to=$TELL
    [ "$cmd" = ask ] && to=$ASK
    for s in "${args[@]}"; do
      idx=$(find_step "$s") || { echo "no step \"$s\" in the table, or several start so: show lists them" >&2; exit 1; }
      answers[$idx]=$to
    done
    write
    show ;;
  *) usage ;;
esac
