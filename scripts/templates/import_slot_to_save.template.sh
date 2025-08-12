#!/bin/bash
set -euo pipefail

# Restore save data from a named slot into the game directory.
# Behavior:
#   - If SAVE_PATTERNS present: delete matches in GAME_ROOT, then copy slot.
#   - Else (fallback): delete everything NOT in baseline, then copy slot.
#
# Templated by install.sh:
#   __INSTALL_DIR__          -> absolute game root
#   __SAVESLOT_PATH__        -> absolute base path for all game slots
#   __GAME_ID__              -> game identifier
#   __BASELINE_FILE__        -> path to .install_baseline.lst (newline list, recursive)
#   __SAVE_PATTERNS_ARRAY__  -> bash array literal of patterns relative to game root
#
# Usage: ./import_slot_to_save.sh <slotname>

SLOT="${1:-}"
if [[ -z "$SLOT" ]]; then
  echo "Usage: $0 <slotname>" >&2
  exit 1
fi

GAME_ROOT="__INSTALL_DIR__"
SRC="__SAVESLOT_PATH__/__GAME_ID__/$SLOT"
BASELINE="__BASELINE_FILE__"

declare -a SAVE_PATTERNS=__SAVE_PATTERNS_ARRAY__

if [[ ! -d "$SRC" ]]; then
  echo "Slot not found: $SRC" >&2
  exit 1
fi

# Make globs predictable for whitelist handling.
shopt -s globstar nullglob dotglob

# -------------------------------------------------------------------
# Mode A: WHITELIST — purge matches then restore from slot
# -------------------------------------------------------------------
if [[ ${#SAVE_PATTERNS[@]} -gt 0 ]]; then
  (
    cd "$GAME_ROOT"

    for pat in "${SAVE_PATTERNS[@]}"; do
      if [[ "$pat" == */ ]]; then
        # Directory marker: remove the entire directory (if present)
        dir="${pat%/}"
        [[ -e "$dir" ]] || continue
        rm -rf -- "$dir"
      else
        # File / wildcard pattern: expand and delete matches
        matches=( $pat )
        (( ${#matches[@]} )) || continue
        rm -f -- "${matches[@]}"
      fi
    done
  )

  # Restore slot into cleaned areas
  rsync -a "$SRC/" "$GAME_ROOT/"
  echo "Imported slot '$SLOT' (whitelist mode) into: $GAME_ROOT"
  exit 0
fi

# -------------------------------------------------------------------
# Mode B: FALLBACK — baseline diff clean, then restore from slot
# -------------------------------------------------------------------
if [[ ! -f "$BASELINE" ]]; then
  echo "Baseline fehlt: $BASELINE" >&2
  exit 1
fi

CUR_LIST="$(mktemp)"
BASE_LIST_Z="$(mktemp)"
DEL_LIST="$(mktemp)"

cleanup() {
  rm -f "$CUR_LIST" "$BASE_LIST_Z" "$DEL_LIST"
}
trap cleanup EXIT

# Build current file list: recursive, relative, NUL-delimited, sorted
LC_ALL=C find "$GAME_ROOT" -type f -printf '%P\0' | LC_ALL=C sort -z -o "$CUR_LIST"

# Normalize baseline (newline -> NUL) and sort to match current collation
awk 'BEGIN{RS="\n"; ORS="\0"} {print}' "$BASELINE" | LC_ALL=C sort -z -o "$BASE_LIST_Z"

# Files only in current (i.e., not in baseline) → must be removed
comm -z -13 "$BASE_LIST_Z" "$CUR_LIST" > "$DEL_LIST"

# Delete those files relative to GAME_ROOT, NUL-safe
(
  cd "$GAME_ROOT"
  if [[ -s "$DEL_LIST" ]]; then
    xargs -0 -r rm -f -- < "$DEL_LIST"
  fi
  # Optionally prune now-empty directories (but never remove the root)
  find . -mindepth 1 -type d -empty -delete
)

# Restore slot content
rsync -a "$SRC/" "$GAME_ROOT/"

# Done
count=$(tr -cd '\0' < "$DEL_LIST" | wc -c)
echo "Imported slot '$SLOT' (baseline mode) into: $GAME_ROOT (removed $count non-baseline files before restore)"

