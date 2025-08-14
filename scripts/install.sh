#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/_config.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# pre create savegame directories after install to increase stability 
create_dir_from_pattern() {
  local pat="$1"
  [[ -z "$pat" ]] && return 0

  # Flags
  local is_dir_marker=0 has_glob=0
  [[ "$pat" == */ && "$pat" != *'*'* && "$pat" != *'?'* && "$pat" != *'['* ]] && is_dir_marker=1
  [[ "$pat" == *'*'* || "$pat" == *'?'* || "$pat" == *'['* ]] && has_glob=1

  # Zielverzeichnis, das ggf. angelegt werden soll (relativ zu INSTALL_DIR)
  local dir=""

  if (( is_dir_marker )); then
    # "SAVE/" -> SAVE
    dir="${pat%/}"

  elif (( has_glob )); then
    # "SAVE/*.SAV", "SAVE/**", "SAVE/slot_*" -> Elternordner "SAVE" anlegen
    dir="${pat%/*}"
    [[ "$dir" == "$pat" ]] && dir=""

  else
    # Plain path ohne Globs -> als DATEI interpretieren
    # Nur falls ein Unterordner enthalten ist, dessen Elternordner anlegen.
    if [[ "$pat" == */* ]]; then
      dir="${pat%/*}"
    else
      dir=""   # "ROSTER.DTA" -> nichts anlegen
    fi
  fi

  # Nichts zu tun?
  [[ -z "$dir" ]] && return 0

  # Sicherheitsgurt
  [[ "$dir" == /* ]] && return 0
  [[ "$dir" == *".."* ]] && return 0

  local target="${INSTALL_DIR%/}/$dir"

  # Wenn an der Stelle bereits eine Datei existiert (kein Ordner), nichts tun.
  if [[ -e "$target" && ! -d "$target" ]]; then
    return 0
  fi

  mkdir -p -- "$target"
}

GAME_ID="$1"
if [[ -z "$GAME_ID" ]]; then
  echo -e "${RED}Usage: $0 <game_id>${NC}"
  exit 1
fi

GAME_CONFIG="${CONFIG_PATH%/}/$GAME_ID/game.json"
if [[ ! -f "$GAME_CONFIG" ]]; then
  echo -e "${RED}Game configuration not found: $GAME_CONFIG${NC}"
  exit 1
fi

command -v jq >/dev/null || { echo -e "${RED}jq nicht gefunden.${NC}"; exit 1; }

ENGINE=$(jq -r '.engine' "$GAME_CONFIG")
ENGINE_SCRIPT="$(dirname "$0")/engines/_${ENGINE,,}.sh"

if [[ ! -f "$ENGINE_SCRIPT" ]]; then
  echo -e "${RED}Engine '$ENGINE' not supported or missing script: $ENGINE_SCRIPT${NC}"
  echo -e "${RED}List of supported engines:${NC}"
  ls "$(dirname "$0")/engines/" | grep '^_' | sed 's/^_//;s/\.sh$//' | sort
  exit 1
fi

# prepare installation path
INSTALL_DIR="${INSTALL_PATH%/}/$GAME_ID/install/"
GAME_DIR="${INSTALL_PATH%/}/$GAME_ID/"
# mkdir -p "$INSTALL_DIR"
echo "${RED}$INSTALL_DIR${NC}"

if [[ -n "$(ls -A "$INSTALL_DIR")" ]]; then
  echo -e "${RED}Fehler: Zielverzeichnis '$INSTALL_DIR' ist nicht leer.${NC}"
  echo -e "${RED}Breche Installation ab. Bitte 'uninstall.sh' ausführen und erneut versuchen.${NC}"
  echo -e "$INSTALL_DIR/uninstall.sh"
  exit 1
fi

# Wenn die Engine abhängige Installation erfolgreich ist...
if "$ENGINE_SCRIPT" "$GAME_ID"; then
  BASELINE_FILE="${GAME_DIR%/}/.install_baseline.lst"

  # --- Whitelist-Patterns bestimmen (Array-Unterstützung + Backwards-Compat)
  # Prefer `.savegame_paths` (array). If missing, derive array from single `savegame_path` (dir).

  # --- Read savegame paths (array) and legacy single path from game.json
  USERNAME="$(id -un)"
  
  # SAVEGAME_PATHS: [] if missing/null; newline-separated -> bash array
  mapfile -t SAVEGAME_PATHS < <(jq -r '
    ( .savegame_paths // [] )
    | (if type=="array" then . else [] end)
    | map(select(type=="string" and . != "" and . != "null"))
    | .[]
  ' "$GAME_CONFIG")
  
  # Legacy single path
  SINGLE_SAVE_PATH="$(jq -r '
    ( .savegame_path // empty )
    | select(. != null and . != "null" and . != "")
  ' "$GAME_CONFIG")"
  
  # --- Build both: a literal for templating AND a sanitized array for install-time use
  SAVE_PATTERNS_ARRAY_LIT="()"
  SAVE_PATTERNS_SAN=()
  
  if [[ ${#SAVEGAME_PATHS[@]} -gt 0 ]]; then
    tmp=()
    for p in "${SAVEGAME_PATHS[@]}"; do
      # Expand $(whoami) once, centrally
      p="${p//\$(whoami)/$USERNAME}"
      tmp+=("'$p'")
      SAVE_PATTERNS_SAN+=("$p")
    done
    SAVE_PATTERNS_ARRAY_LIT="(${tmp[*]})"
  
  elif [[ -n "$SINGLE_SAVE_PATH" ]]; then
    # Back-compat: treat as directory + recursive export
    CLEAN="${SINGLE_SAVE_PATH%/}/"
    RECUR="${SINGLE_SAVE_PATH%/}/**"
    SAVE_PATTERNS_ARRAY_LIT="('$CLEAN' '$RECUR')"
    SAVE_PATTERNS_SAN+=("$CLEAN" "$RECUR")
  
  else
    SAVE_PATTERNS_ARRAY_LIT="()"
    SAVE_PATTERNS_SAN=()
  fi
  
  
   # ... Slot-Tools generieren
  for TEMPLATE_BASENAME in export_save_to_slot import_slot_to_save list_slots delete_slot; do
    TEMPLATE_PATH="$(dirname "$0")/templates/${TEMPLATE_BASENAME}.template.sh"
    TARGET_PATH="${GAME_DIR%/}/${TEMPLATE_BASENAME}.sh"

    if [[ ! -f "$TEMPLATE_PATH" ]]; then
      echo -e "${RED}Template fehlt: $TEMPLATE_PATH${NC}"
      exit 1
    fi

    sed \
      -e "s|__SAVEGAME_PATH__|$INSTALL_DIR/${SINGLE_SAVE_PATH%/}|g" \
      -e "s|__SAVESLOT_PATH__|$SAVESLOT_PATH|g" \
      -e "s|__GAME_ID__|$GAME_ID|g" \
      -e "s|__GAME_DIR__|$INSTALL_DIR|g" \
      -e "s|__INSTALL_DIR__|$INSTALL_DIR|g" \
      -e "s|__BASELINE_FILE__|$BASELINE_FILE|g" \
      -e "s|__SAVE_PATTERNS_ARRAY__|$SAVE_PATTERNS_ARRAY_LIT|g" \
      "$TEMPLATE_PATH" > "$TARGET_PATH"

    chmod +x "$TARGET_PATH"
  done

  # Pre-create all parent dirs implied by patterns
  if [[ "${ENGINE,,}" == "dosbox" ]]; then
    for p in "${SAVE_PATTERNS_SAN[@]}"; do
      create_dir_from_pattern "$p"
    done
  elif [[ "${ENGINE,,}" == "wineboot" ]]; then
    for p in "${SAVE_PATTERNS_SAN[@]}"; do
      # nur relative/spielordner-nahe Patterns vorab anlegen
      # (keine Windows-Absolutpfade, keine %VARS%, keine Backslashes mit Laufwerksbuchstaben)
      if [[ "$p" != *:\\* && "$p" != %*% && "$p" != /* ]]; then
        create_dir_from_pattern "$p"
      fi
    done
  fi
  
  # --- Baseline schreiben: alle Dateien direkt nach Installation (relativ zum INSTALL_DIR)
  LC_ALL=C find "$INSTALL_DIR" -type f -printf '%P\n' | LC_ALL=C sort > "$BASELINE_FILE"

else
  echo -e "${RED}Engine-Installation fehlgeschlagen, Slot-Tools nicht erzeugt.${NC}"
  exit 1
fi

