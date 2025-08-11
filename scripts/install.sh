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

# Wenn die Engine abhängige Installation erfolgreich ist...
if "$ENGINE_SCRIPT" "$GAME_ID"; then
  INSTALL_DIR="$INSTALL_PATH/$GAME_ID"
  BASELINE_FILE="$INSTALL_DIR/.install_baseline.lst"

  # --- Baseline schreiben: alle Dateien direkt nach Installation (relativ zum INSTALL_DIR)
  ( cd "$INSTALL_DIR" && find . -type f -printf '%P\n' | LC_ALL=C sort ) > "$BASELINE_FILE"

  # --- Whitelist-Patterns bestimmen (Array-Unterstützung + Backwards-Compat)
  # Prefer `.savegame_paths` (array). If missing, derive array from single `savegame_path` (dir).
  mapfile -t SAVEGAME_PATHS < <(jq -r '.savegame_paths[]? // empty' "$GAME_CONFIG")
  USERNAME=$(whoami)

  SINGLE_SAVE_PATH=$(jq -r '.savegame_path // empty' "$GAME_CONFIG")

  SAVE_PATTERNS_ARRAY_LIT="()"
  if [[ ${#SAVEGAME_PATHS[@]} -gt 0 ]]; then
    # Use patterns as-is (user may include wildcards and/or trailing / for directories)
    tmp=()
    for p in "${SAVEGAME_PATHS[@]}"; do
      # expand $(whoami) in user-provided patterns so scripts see real paths
      p="${p//\$(whoami)/$USERNAME}"

      # trim trailing slash normalization happens in scripts; we keep literal here
      tmp+=("'$p'")
    done
    SAVE_PATTERNS_ARRAY_LIT="(${tmp[*]})"
  elif [[ -n "$SINGLE_SAVE_PATH" && "$SINGLE_SAVE_PATH" != "null" ]]; then
    # Backward compat: previous semantics were "copy that directory". Implement as:
    # - wipe contents of that dir on import
    # - export/import that dir recursively.
    # We inject two patterns:
    #   1) "<dir>/"       (signals 'directory semantics' for cleanup)
    #   2) "<dir>/**"     (ensures recursive match for export)
    CLEAN="${SINGLE_SAVE_PATH%/}/"
    RECUR="${SINGLE_SAVE_PATH%/}/**"
    SAVE_PATTERNS_ARRAY_LIT="('$CLEAN' '$RECUR')"
  else
    # No whitelist: scripts will fall back to baseline-diff logic.
    SAVE_PATTERNS_ARRAY_LIT="()"
  fi

  # ... Slot-Tools generieren
  for TEMPLATE_BASENAME in export_save_to_slot import_slot_to_save list_slots delete_slot; do
    TEMPLATE_PATH="$(dirname "$0")/templates/${TEMPLATE_BASENAME}.template.sh"
    TARGET_PATH="$INSTALL_DIR/${TEMPLATE_BASENAME}.sh"

    if [[ ! -f "$TEMPLATE_PATH" ]]; then
      echo -e "${RED}Template fehlt: $TEMPLATE_PATH${NC}"
      exit 1
    fi

    sed \
      -e "s|__SAVEGAME_PATH__|$INSTALL_DIR/${SINGLE_SAVE_PATH%/}|g" \
      -e "s|__SAVESLOT_PATH__|$SAVESLOT_PATH|g" \
      -e "s|__GAME_ID__|$GAME_ID|g" \
      -e "s|__INSTALL_DIR__|$INSTALL_DIR|g" \
      -e "s|__BASELINE_FILE__|$BASELINE_FILE|g" \
      -e "s|__SAVE_PATTERNS_ARRAY__|$SAVE_PATTERNS_ARRAY_LIT|g" \
      "$TEMPLATE_PATH" > "$TARGET_PATH"

    chmod +x "$TARGET_PATH"
  done

else
  echo -e "${RED}Engine-Installation fehlgeschlagen, Slot-Tools nicht erzeugt.${NC}"
  exit 1
fi

