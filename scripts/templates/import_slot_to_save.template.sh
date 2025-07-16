#!/bin/bash
set -e

SLOT="$1"
if [[ -z "$SLOT" ]]; then
  echo "Usage: $0 <slotname>"
  exit 1
fi

SRC="__SAVESLOT_PATH__/__GAME_ID__/$SLOT"
DEST="__SAVEGAME_PATH__"

if [[ ! -d "$SRC" ]]; then
  echo "Slot nicht gefunden: \$SRC"
  exit 1
fi

rm -r "$DEST/"
mkdir "$DEST/"
cp -r "$SRC/"* "$DEST/"
echo "Slot '$SLOT' wurde ins Spielverzeichnis wiederhergestellt."

