#!/bin/bash
set -e

SLOT="$1"
if [[ -z "$SLOT" ]]; then
  echo "Usage: $0 <slotname>"
  exit 1
fi

SRC="__SAVEGAME_PATH__"
DEST="__SAVESLOT_PATH__/__GAME_ID__/$SLOT"

mkdir -p "$DEST"
cp -r "$SRC/"* "$DEST/"
echo "Savegame wurde nach Slot '$SLOT' exportiert."

