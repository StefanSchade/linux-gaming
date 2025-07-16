#!/bin/bash

SLOTDIR="__SAVESLOT_PATH__/__GAME_ID__"

if [[ ! -d "$SLOTDIR" ]]; then
  echo "Keine Slots gefunden für __GAME_ID__."
  exit 0
fi

echo "Verfügbare Slots für __GAME_ID__:"
ls -1 "$SLOTDIR"

