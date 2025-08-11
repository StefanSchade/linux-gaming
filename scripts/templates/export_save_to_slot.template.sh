#!/bin/bash
set -euo pipefail

SLOT="${1:-}"
if [[ -z "$SLOT" ]]; then
  echo "Usage: $0 <slotname>"
  exit 1
fi

GAME_ROOT="__INSTALL_DIR__"
DEST="__SAVESLOT_PATH__/__GAME_ID__/$SLOT"
BASELINE="__BASELINE_FILE__"

# Whitelist patterns (relative to $GAME_ROOT). If empty -> baseline-diff mode.
# Patterns may contain wildcards; trailing "/" denotes "treat as directory".
declare -a SAVE_PATTERNS=__SAVE_PATTERNS_ARRAY__

mkdir -p "$DEST"

shopt -s globstar nullglob dotglob

if [[ ${#SAVE_PATTERNS[@]} -gt 0 ]]; then
  # Export only whitelisted items, preserving structure
  (
    cd "$GAME_ROOT"
    # rsync with --relative (-R) preserves path components in the destination
    for pat in "${SAVE_PATTERNS[@]}"; do
      # Allow directory markers to mean "full directory content"
      if [[ "$pat" == */ ]]; then
        dir="${pat%/}"
        [[ -d "$dir" ]] || continue
        rsync -aRL "./$dir/" "$DEST/"
      else
        # File/wildcard pattern
        # Expand safely; if nothing matches, skip
        matches=( ./$pat )
        # If the literal string stayed unexpanded, check existence
        if [[ "${matches[*]}" != "./$pat" || -e "./$pat" || -L "./$pat" ]]; then
          rsync -aRL "${matches[@]}" "$DEST/" 2>/dev/null || true
        fi
      fi
    done
  )
else
  # No whitelist → export "new files" (diff vs baseline)
  if [[ ! -f "$BASELINE" ]]; then
    echo "Baseline fehlt: $BASELINE"
    exit 1
  fi
  TMP_LIST="$(mktemp)"
  trap 'rm -f "$TMP_LIST"' EXIT
  (
    cd "$GAME_ROOT"
    # list current files (relative)
    find . -type f -printf '%P\n' | LC_ALL=C sort > "$TMP_LIST.cur"
    # export only files NOT in baseline
    comm -13 "$BASELINE" "$TMP_LIST.cur" > "$TMP_LIST"
    rm -f "$TMP_LIST.cur"
    if [[ -s "$TMP_LIST" ]]; then
      rsync -a --files-from="$TMP_LIST" "$GAME_ROOT/" "$DEST/"
    else
      echo "Keine neuen Dateien seit Installation – nichts zu exportieren."
    fi
  )
fi

echo "Savegame wurde nach Slot '$SLOT' exportiert."

