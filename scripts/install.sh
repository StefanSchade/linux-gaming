#!/bin/bash
set -e

source "$(dirname "$0")/_config.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

GAME_ID="$1"
if [[ -z "$GAME_ID" ]]; then
  echo -e "${RED}Usage: $0 <game_id>${NC}"
  exit 1
fi

GAME_CONFIG="$CONFIG_PATH/$GAME_ID/game.json"
if [[ ! -f "$GAME_CONFIG" ]]; then
  echo -e "${RED}Konfigurationsdatei nicht gefunden: $GAME_CONFIG${NC}"
  exit 1
fi

ENGINE=$(jq -r '.engine' "$GAME_CONFIG")

ENGINE_SCRIPT="$(dirname "$0")/engines/_${ENGINE,,}.sh"

if [[ ! -f "$ENGINE_SCRIPT" ]]; then
  echo -e "${RED}Engine '$ENGINE' nicht unterstützt oder Script fehlt: $ENGINE_SCRIPT${NC}"
  echo -e "${RED}Tipp: Unterstützte Engines sind:${NC}"
  ls "$(dirname "$0")/engines/" | grep '^_' | sed 's/^_//;s/\.sh$//' | sort
  exit 1
fi




if [[ ! -f "$ENGINE_SCRIPT" ]]; then
  echo -e "${RED}Engine '$ENGINE' nicht unterstützt oder Script fehlt: $ENGINE_SCRIPT${NC}"
  exit 1
fi

"$ENGINE_SCRIPT" "$GAME_ID"

