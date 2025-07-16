#!/bin/bash
set -e

SLOT="$1"
if [[ -z "$SLOT" ]]; then
  echo "Usage: $0 <slotname>"
  exit 1
fi

SLOT_DIR="__SAVESLOT_PATH__/__GAME_ID__/$SLOT"
if [[ ! -d "$SLOT_DIR" ]]; then
  echo "Slot '$SLOT' existiert nicht."
  exit 1
fi

rm -rf "$SLOT_DIR"
echo "Slot '$SLOT' wurde gelöscht."

