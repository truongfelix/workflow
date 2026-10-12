#!/usr/bin/env bash
#
# adopt.sh — install the workflow skeleton into a project, never overwriting a file that is already there.
#
# Usage: bin/adopt.sh <project-root> [--workspace]
#   --workspace  the root is a multi-repo workspace: also install workspace/gitignore as its .gitignore (if absent),
#                so the root becomes a docs-only repo next to the code repos it contains.
#
# Prints what was copied, what was skipped (and how to diff it against the template), the FILL markers left to
# resolve, and records the workflow commit in .claude/workflow-version. Exit 1 on a usage error only.
#
# Two names differ in template/: CLAUDE.template.md and dot-claude/ are installed as CLAUDE.md and .claude/. Under
# their real names, Claude Code would load them as instructions and skills in a session working on the workflow.

set -euo pipefail

SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
dst=${1:-}
[ -z "$dst" ] && { echo "usage: $0 <project-root> [--workspace]" >&2; exit 1; }
workspace=0
[ "${2:-}" = "--workspace" ] && workspace=1
mkdir -p "$dst"
dst=$(cd "$dst" && pwd)

copied=() skipped=() skipped_src=()
install_file() { # <source> <relative destination>
  if [ -e "$dst/$2" ]; then
    skipped+=("$2")
    skipped_src+=("$1")
  else
    mkdir -p "$dst/$(dirname "$2")"
    cp -p "$1" "$dst/$2"
    copied+=("$2")
  fi
}

installed_name() { # <path in template/>: its path in the project
  case $1 in
    CLAUDE.template.md) echo CLAUDE.md ;;
    dot-claude/*) echo ".claude/${1#dot-claude/}" ;;
    *) echo "$1" ;;
  esac
}

while IFS= read -r -d '' f; do
  f=${f#./}
  install_file "$SRC/template/$f" "$(installed_name "$f")"
done < <(cd "$SRC/template" && find . -type f -print0 | sort -z)
[ "$workspace" = 1 ] && install_file "$SRC/workspace/gitignore" ".gitignore"
chmod +x "$dst/.claude/skills/session-start/"{ground-truth,items,board}.sh 2>/dev/null || true

version=$(git -C "$SRC" log -1 --format='%h %cd' --date=short 2>/dev/null || echo "unversioned")
echo "workflow $version, adopted $(date +%Y-%m-%d)" >"$dst/.claude/workflow-version"

echo "Adopted the workflow ($version) into $dst"
if [ ${#copied[@]} -gt 0 ]; then
  echo
  echo "Copied:"
  printf '  %s\n' "${copied[@]}"
fi
if [ ${#skipped[@]} -gt 0 ]; then
  echo
  echo "Skipped (already there; merge by hand if the template is newer):"
  for i in "${!skipped[@]}"; do
    f=${skipped[$i]} src=${skipped_src[$i]}
    if cmp -s "$src" "$dst/$f"; then echo "  $f (identical)"; else echo "  $f   diff -u $dst/$f $src"; fi
  done
fi
echo
# The markers of every template file in the project, copied now or already there: the setup runs this script again
# after the user did, and that run must still say what is left.
installed=(${copied[@]+"${copied[@]}"} ${skipped[@]+"${skipped[@]}"})
fills=""
[ ${#installed[@]} -gt 0 ] && fills=$(cd "$dst" && grep -Hn 'FILL' "${installed[@]}" 2>/dev/null || true)
if [ -n "$fills" ]; then
  echo "Left to fill (README.md, 'Adopt in a new project'):"
  printf '%s\n' "$fills" | sed 's|^|  |'
else
  echo "No FILL markers left."
fi
