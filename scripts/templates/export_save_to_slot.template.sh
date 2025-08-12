#!/bin/bash
set -euo pipefail

# Export save data into a named slot.
# Primary mode: whitelist patterns injected by install.sh.
# Fallback mode: baseline diff (files created after install), recursive & NUL-safe.
#
# Templated by install.sh:
#   __INSTALL_DIR__      -> absolute game root
#   __SAVESLOT_PATH__    -> absolute base path for all game slots
#   __GAME_ID__          -> game identifier
#   __BASELINE_FILE__    -> path to .install_baseline.lst (newline list, recursive)
#   __SAVE_PATTERNS_ARRAY__ -> bash array literal of patterns relative to game root
#
# Usage: ./export_save_to_slot.sh <slotname>

SLOT="${1:-}"
if [[ -z "$SLOT" ]]; then
  echo "Usage: $0 <slotname>" >&2
  exit 1
fi

GAME_ROOT="__INSTALL_DIR__"
DEST="__SAVESLOT_PATH__/__GAME_ID__/$SLOT"
BASELINE="__BASELINE_FILE__"

# If non-empty, we copy only these patterns (relative to $GAME_ROOT).
# Examples: "DUNECD/*.SAV" or "SAVE/" (trailing slash => copy whole dir)
declare -a SAVE_PATTERNS=__SAVE_PATTERNS_ARRAY__

mkdir -p "$DEST"

# Make globs predictable and safe.
shopt -s globstar nullglob dotglob

if [[ ${#SAVE_PATTERNS[@]} -gt 0 ]]; then
  # ------------------------------
  # WHITELIST MODE (primary)
  # ------------------------------
  (
    cd "$GAME_ROOT"
    # rsync -aR preserves the relative path (with leading "./")
    for pat in "${SAVE_PATTERNS[@]}"; do
      if [[ "$pat" == */ ]]; then
        # Directory marker: copy entire directory tree if it exists
        dir="${pat%/}"
        [[ -d "$dir" ]] || continue
        rsync -aR "./$dir/" "$DEST/"
      else
        # File / wildcard pattern: expand and copy, preserving paths
        matches=( ./$pat )
        (( ${#matches[@]} )) || continue
        rsync -aR "${matches[@]}" "$DEST/"
      fi
    done
  )
  echo "Exported whitelist patterns to slot '$SLOT' at: $DEST"
  exit 0
fi

# ------------------------------
# FALLBACK: BASELINE DIFF MODE
# ------------------------------
# Robust against unsorted/locale issues and nested directories.
CUR_LIST="$(mktemp)"
BASE_LIST_Z="$(mktemp)"
DELTA_LIST="$(mktemp)"

cleanup() {
  rm -f "$CUR_LIST" "$BASE_LIST_Z" "$DELTA_LIST"
}
trap cleanup EXIT

if [[ ! -f "$BASELINE" ]]; then
  echo "Baseline fehlt: $BASELINE" >&2
  exit 1
fi

# 1) Current files (recursive, relative to GAME_ROOT), NUL-delimited & sorted.
LC_ALL=C find "$GAME_ROOT" -type f -printf '%P\0' | LC_ALL=C sort -z -o "$CUR_LIST"

# 2) Normalize baseline (newline -> NUL) and sort to match CUR_LIST collation.
awk 'BEGIN{RS="\n"; ORS="\0"} {print}' "$BASELINE" | LC_ALL=C sort -z -o "$BASE_LIST_Z"

# 3) Delta: only entries present in current but not in baseline.
comm -z -13 "$BASE_LIST_Z" "$CUR_LIST" > "$DELTA_LIST"

# 4) Copy just the delta, preserving directory structure.
if [[ -s "$DELTA_LIST" ]]; then
  rsync -a --from0 --files-from="$DELTA_LIST" "$GAME_ROOT/" "$DEST/"
  echo "Exported $(tr -cd '\0' < "$DELTA_LIST" | wc -c) new/changed files to slot '$SLOT' at: $DEST"
else
  echo "Keine neuen Dateien seit Installation – nichts zu exportieren."
fi

