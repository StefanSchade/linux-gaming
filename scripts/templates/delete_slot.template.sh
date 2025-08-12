#!/bin/bash
set -euo pipefail

# Templated by install.sh:
#   __SAVESLOT_PATH__  -> absolute base path for all game slots
#   __GAME_ID__        -> game identifier used as subdir under save root
#
# Usage: ./delete_slot.sh <slotname>

SLOT="${1:-}"
if [[ -z "$SLOT" ]]; then
  echo "Usage: $0 <slotname>" >&2
  exit 1
fi

SAVE_ROOT="__SAVESLOT_PATH__/__GAME_ID__"
TARGET="$SAVE_ROOT/$SLOT"

# Safety: ensure TARGET is inside SAVE_ROOT
case "$TARGET" in
  "$SAVE_ROOT"/*) ;;
  *)
    echo "Refusing to delete outside save root: $TARGET" >&2
    exit 1
    ;;
esac

if [[ ! -d "$TARGET" ]]; then
  echo "Slot not found: $TARGET" >&2
  exit 1
fi

rm -rf -- "$TARGET"
echo "Deleted slot '$SLOT'"

