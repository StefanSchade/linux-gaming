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

# Spielverzeichnis vorbereiten
GAME_DIR="$INSTALL_PATH/$GAME_ID"
mkdir -p "$GAME_DIR"

echo "${RED}$GAME_DIR${NC}"

if [[ -n "$(ls -A "$GAME_DIR")" ]]; then
  echo -e "${RED}Fehler: Zielverzeichnis '$GAME_DIR' ist nicht leer.${NC}"
  echo -e "${RED}Breche Installation ab. Bitte 'uninstall.sh' ausführen und erneut versuchen.${NC}"
  echo -e "$GAME_DIR/uninstall.sh"
  exit 1
fi


# Wenn die Engine abhaengige Installation erfolgreich ist...
if "$ENGINE_SCRIPT" "$GAME_ID"; then

# Aus Config holen
SAVEGAME_PATH=$(jq -r '.savegame_path' "$GAME_CONFIG")

# Slash am Ende bereinigen
SAVEGAME_PATH="${SAVEGAME_PATH%/}"

# whoami Referenz aufloesen
USERNAME=$(whoami)
SAVEGAME_PATH=$(echo "$SAVEGAME_PATH" | sed "s|\$(whoami)|$USERNAME|g")

# kompletten Pfad zusammenbauen
SAVEGAME_PATH="$INSTALL_PATH/$GAME_ID/$SAVEGAME_PATH"

# ... Slot-Tools generieren
for TEMPLATE in export_save_to_slot import_slot_to_save list_slots delete_slot; do
    TEMPLATE_PATH="$(dirname "$0")/templates/${TEMPLATE}.template.sh"
    TARGET_PATH="$GAME_DIR/${TEMPLATE}.sh"

    if [[ ! -f "$TEMPLATE_PATH" ]]; then
      echo -e "${RED}Template fehlt: $TEMPLATE_PATH${NC}"
      exit 1
    fi

    sed \
      -e "s|__SAVEGAME_PATH__|$SAVEGAME_PATH|g" \
      -e "s|__SAVESLOT_PATH__|$SAVESLOT_PATH|g" \
      -e "s|__GAME_ID__|$GAME_ID|g" \
      "$TEMPLATE_PATH" > "$TARGET_PATH"

    chmod +x "$TARGET_PATH"
  done

else
  echo -e "${RED}Engine-Installation fehlgeschlagen, Slot-Tools nicht erzeugt.${NC}"
  exit 1
fi
