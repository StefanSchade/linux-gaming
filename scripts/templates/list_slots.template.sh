#!/bin/bash
set -euo pipefail

# Templated by install.sh:
#   __SAVESLOT_PATH__  -> absolute base path for all game slots
#   __GAME_ID__        -> game identifier used as subdir under save root

SAVE_ROOT="__SAVESLOT_PATH__/__GAME_ID__"

if [[ ! -d "$SAVE_ROOT" ]]; then
  echo "No slots yet for __GAME_ID__"
  exit 0
fi

shopt -s nullglob dotglob

# Build list "mtime<TAB>slotname" and sort by mtime desc
mapfile -t entries < <(
  for d in "$SAVE_ROOT"/*; do
    [[ -d "$d" ]] || continue
    mtime=$(stat -c '%Y' -- "$d")
    name=$(basename -- "$d")
    printf '%s\t%s\n' "$mtime" "$name"
  done | sort -rn -k1,1
)

if ((${#entries[@]} == 0)); then
  echo "No slots yet for __GAME_ID__"
  exit 0
fi

# Print: slot name, file count (recursive), last updated timestamp
for line in "${entries[@]}"; do
  mtime="${line%%$'\t'*}"
  name="${line#*$'\t'}"
  count=$(find "$SAVE_ROOT/$name" -type f -print0 | tr -cd '\0' | wc -c)
  ts=$(date -d "@$mtime" '+%Y-%m-%d %H:%M:%S')
  printf '%-24s files=%-6s updated=%s\n' "$name" "$count" "$ts"
done

