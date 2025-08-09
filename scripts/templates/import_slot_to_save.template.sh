#!/bin/bash
set -euo pipefail

SLOT="${1:-}"
if [[ -z "$SLOT" ]]; then
  echo "Usage: $0 <slotname>"
  exit 1
fi

SRC="__SAVESLOT_PATH__/__GAME_ID__/$SLOT"
GAME_ROOT="__INSTALL_DIR__"
BASELINE="__BASELINE_FILE__"

if [[ ! -d "$SRC" ]]; then
  echo "Slot nicht gefunden: $SRC"
  exit 1
fi

declare -a SAVE_PATTERNS=__SAVE_PATTERNS_ARRAY__

shopt -s globstar nullglob dotglob

# 1) Cleanup phase (produce 'clean slate' per spec)
if [[ ${#SAVE_PATTERNS[@]} -gt 0 ]]; then
  (
    cd "$GAME_ROOT"
    for pat in "${SAVE_PATTERNS[@]}"; do
      if [[ "$pat" == */ ]]; then
        dir="${pat%/}"
        [[ -d "$dir" ]] || continue
        # Remove directory contents but keep the directory itself
        rm -rf -- "$dir/"* "$dir/".* 2>/dev/null || true
      else
        matches=( ./$pat )
        if [[ "${matches[*]}" != "./$pat" || -e "./$pat" || -L "./$pat" ]]; then
          rm -rf -- "${matches[@]}" 2>/dev/null || true
        fi
      fi
    done
  )
else
  # No whitelist → remove everything not in baseline
  if [[ ! -f "$BASELINE" ]]; then
    echo "Baseline fehlt: $BASELINE"
    exit 1
  fi
  (
    cd "$GAME_ROOT"
    TMP_CUR="$(mktemp)"
    trap 'rm -f "$TMP_CUR"' EXIT
    find . -type f -printf '%P\n' | LC_ALL=C sort > "$TMP_CUR"
    # files present now but not in baseline
    while IFS= read -r rel; do
      rm -f -- "$rel" 2>/dev/null || true
    done < <(comm -13 "$BASELINE" "$TMP_CUR")
    # Optional: prune empty dirs that were created post-install (best-effort)
    find . -type d -empty -mindepth 1 -delete 2>/dev/null || true
  )
fi

# 2) Restore phase (preserve structure)
rsync -a "$SRC/" "$GAME_ROOT/"

echo "Slot '$SLOT' wurde ins Spielverzeichnis wiederhergestellt."

