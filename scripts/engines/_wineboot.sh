#!/bin/bash
# File: scripts/engines/_wineboot.sh
set -euo pipefail

# ------------------------------------------------------------
# Common env
# ------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR%/}/../_config.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

GAME_ID="${1:-}"
if [[ -z "$GAME_ID" ]]; then
  echo -e "${RED}Usage: $0 <game_id>${NC}"
  exit 1
fi

INSTALL_DIR="${INSTALL_PATH%/}/install/$GAME_ID/"
DOWNLOAD_DIR="${DOWNLOAD_PATH%/}/$GAME_ID/"
CONFIG_DIR="${CONFIG_PATH%/}/$GAME_ID/"
GAME_CONFIG="$CONFIG_PATH/$GAME_ID/game.json"

if [[ ! -f "$GAME_CONFIG" ]]; then
  echo -e "${RED}Konfigurationsdatei nicht gefunden: $GAME_CONFIG${NC}"
  exit 1
fi

# ------------------------------------------------------------
# Read config
# ------------------------------------------------------------
jq_get() { jq -r "$1 // empty" "$GAME_CONFIG"; }

WINE_ARCH="$(jq_get '.wine_arch')"
WINE_VERSION="$(jq_get '.wine_version')"
EXE_PATH_WIN="$(jq_get '.exe_path')"
EXE_FILE_WIN="$(jq_get '.exe_file')"
INSTALLER_TYPE="$(jq_get '.installer_type')"
POST_INSTALL_COUNT="$(jq -r '.post_install | length // 0' "$GAME_CONFIG")"
INSTALLER_FILES_COUNT="$(jq -r '.installer_files | length // 0' "$GAME_CONFIG")"

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
# Create parent dirs for savegame patterns (prefix/drive_c/... only)
create_dir_from_pattern() {
  local pat="$1"
  # Only handle prefix-relative targets, ignore others silently
  if [[ "$pat" != prefix/* ]]; then
    return
  fi

  # Strip "prefix/" and map to real path inside WINEPREFIX
  local sub="${pat#prefix/}"
  local hostpath="${WINEPREFIX%/}/$sub"

  # Case 1: explicit directory marker "foo/" (no globs)
  if [[ "$hostpath" == */ && "$hostpath" != *'*'* && "$hostpath" != *'?'* && "$hostpath" != *'['* ]]; then
    mkdir -p -- "${hostpath%/}"
    return
  fi

  # Case 2: pattern with globs -> create static prefix up to first glob
  local static="${hostpath%%[\*\?\[]*}"
  static="${static%/}"
  [[ -z "$static" ]] && return
  [[ "$static" == /* ]] || static="$(realpath -m "$static")"
  [[ "$static" == *".."* ]] && return

  mkdir -p -- "$static"
}

require_tool() {
  local bin="$1" hint="$2"
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo -e "${RED}Fehlt: '$bin'.${NC} ${YELLOW}$hint${NC}"
    exit 1
  fi
}

# Convert Windows path segment (like "Program Files/Konami/...") to host path
to_host_path_from_win_c() {
  local win_rel="$1"
  echo "${WINEPREFIX%/}/drive_c/${win_rel}"
}

# ------------------------------------------------------------
# Prepare install dirs / WINE prefix
# ------------------------------------------------------------
if [[ -d "$INSTALL_DIR" && -n "$(ls -A "$INSTALL_DIR" 2>/dev/null || true)" ]]; then
  echo -e "${RED}Fehler: Zielverzeichnis '$INSTALL_DIR' ist nicht leer.${NC}"
  echo -e "${RED}Breche Installation ab. Bitte 'uninstall.sh' ausführen und erneut versuchen.${NC}"
  exit 1
fi

mkdir -p "$INSTALL_DIR" "$DOWNLOAD_DIR" "$CONFIG_DIR"

export WINEPREFIX="${INSTALL_DIR%/}/prefix"
if [[ -z "${WINE_ARCH:-}" ]]; then
  # default to 32-bit for old games
  export WINEARCH=win32
else
  export WINEARCH="$WINE_ARCH"
fi

echo -e "${GREEN}Initialisiere Wine-Prefix ($WINEARCH) ...${NC}"
wineboot -u

# Optional: set Windows version if provided (best-effort, no hard dep on winetricks)
if [[ -n "${WINE_VERSION:-}" ]]; then
  if command -v winetricks >/dev/null 2>&1; then
    case "$WINE_VERSION" in
      win10|win81|win7|winxp|win11) winetricks -q "windows=$WINE_VERSION" || true ;;
      *) winetricks -q "windows=$WINE_VERSION" || true ;;
    esac
  else
    echo -e "${YELLOW}Hinweis: 'winetricks' nicht gefunden – Überspringe Windows-Version-Set (${WINE_VERSION}).${NC}"
  fi
fi

# ------------------------------------------------------------
# Installer handling
# ------------------------------------------------------------
TMP_ROOT="$(mktemp -d -t "${GAME_ID}_build.XXXXXXXX")"
cleanup() {
  rm -rf "$TMP_ROOT" || true
}
trap cleanup EXIT

run_installer_from_merged_source() {
  local merged_root="$1"
  # Prefer setup.exe, fallback to autorun.exe
  local setup exe
  setup="$(find "$merged_root" -maxdepth 2 -type f -iname 'setup.exe' | head -n1 || true)"
  if [[ -z "$setup" ]]; then
    exe="$(find "$merged_root" -maxdepth 2 -type f -iname 'autorun.exe' | head -n1 || true)"
  else
    exe="$setup"
  fi
  if [[ -z "$exe" ]]; then
    echo -e "${RED}Kein setup.exe/autorun.exe im zusammengeführten Installationsmedium gefunden.${NC}"
    exit 1
  fi
  echo -e "${GREEN}Starte Installer:${NC} $exe"
  wine start /unix "$exe"
  # Wait for installer to complete (simple heuristic: wait for wineserver idle)
  wineserver -w
}

if [[ "$INSTALLER_TYPE" == "MULTI_DISC_ZIP" ]]; then
  echo -e "${GREEN}Modus:${NC} MULTI_DISC_ZIP – entpacke und merge Discs"
  require_tool "7z" "Installiere z.B. 'p7zip-full'."
  require_tool "unzip" "Bitte 'unzip' installieren."

  if (( INSTALLER_FILES_COUNT == 0 )); then
    echo -e "${RED}installer_files[] ist leer in game.json.${NC}"
    exit 1
  fi

  MERGED_DIR="$TMP_ROOT/merged"
  mkdir -p "$MERGED_DIR"

  # 1) For each zip: unzip to temp, then extract ISO (if present) with 7z; else merge extracted files.
  for idx in $(seq 0 $((INSTALLER_FILES_COUNT-1))); do
    ZIP_NAME="$(jq -r ".installer_files[$idx]" "$GAME_CONFIG")"
    SRC_ZIP="${DOWNLOAD_DIR%/}/$ZIP_NAME"
    if [[ ! -f "$SRC_ZIP" ]]; then
      echo -e "${RED}Fehlende Datei:${NC} $SRC_ZIP"
      exit 1
    fi
    echo -e "${GREEN}Entpacke ZIP:${NC} $ZIP_NAME"
    ZIP_OUT="$TMP_ROOT/zip_$idx"
    mkdir -p "$ZIP_OUT"
    unzip -q "$SRC_ZIP" -d "$ZIP_OUT"

    # Try to find ISO within the zip payload
    ISO_FILE="$(find "$ZIP_OUT" -type f \( -iname '*.iso' -o -iname '*.bin' \) | head -n1 || true)"
    if [[ -n "$ISO_FILE" ]]; then
      echo -e "${GREEN}Extrahiere ISO mit 7z:${NC} $(basename "$ISO_FILE")"
      ISO_OUT="$TMP_ROOT/iso_$idx"
      mkdir -p "$ISO_OUT"
      7z x -y -o"$ISO_OUT" -- "$ISO_FILE" >/dev/null
      rsync -a --ignore-existing "$ISO_OUT"/ "$MERGED_DIR"/
    else
      # No ISO; merge files directly
      rsync -a --ignore-existing "$ZIP_OUT"/ "$MERGED_DIR"/
    fi
  done

  # 2) Run the installer from merged media
  run_installer_from_merged_source "$MERGED_DIR"

else
  # Fallback: if a single installer is configured or heuristics in install.sh handle it,
  # we don’t duplicate logic here. We only run the already installed game if present.
  echo -e "${YELLOW}INSTALLER_TYPE ist nicht 'MULTI_DISC_ZIP'. Diese Engine erwartet, dass die Installation bereits von install.sh durchgeführt wurde (GOG/Inno o.ä.).${NC}"
fi

# ------------------------------------------------------------
# Post-install steps (e.g., SH2 Enhanced Edition)
# ------------------------------------------------------------
# Ensure game install dir and EXE are where config says
if [[ -n "$EXE_PATH_WIN" && -n "$EXE_FILE_WIN" ]]; then
  HOST_GAME_DIR="$(to_host_path_from_win_c "$EXE_PATH_WIN")"
  mkdir -p "$HOST_GAME_DIR"
else
  echo -e "${YELLOW}Warnung: exe_path/exe_file nicht gesetzt – Überspringe Validierung des Installationsziels.${NC}"
fi

if (( POST_INSTALL_COUNT > 0 )); then
  for idx in $(seq 0 $((POST_INSTALL_COUNT-1))); do
    PI_NAME="$(jq -r ".post_install[$idx]" "$GAME_CONFIG")"
    PI_SRC="${DOWNLOAD_DIR%/}/$PI_NAME"
    if [[ ! -f "$PI_SRC" ]]; then
      echo -e "${YELLOW}Post-Install Datei nicht gefunden:${NC} $PI_SRC (überspringe)"
      continue
    fi
    if [[ -z "${HOST_GAME_DIR:-}" ]]; then
      # Fallback: drop into prefix drive_c root
      HOST_TARGET_DIR="${WINEPREFIX%/}/drive_c/"
    else
      HOST_TARGET_DIR="$HOST_GAME_DIR"
    fi
    echo -e "${GREEN}Kopiere Post-Install:${NC} $PI_NAME -> $HOST_TARGET_DIR"
    cp -f -- "$PI_SRC" "$HOST_TARGET_DIR/"
    # Execute if it looks like a Windows executable
    if [[ "${PI_NAME,,}" == *.exe ]]; then
      echo -e "${GREEN}Starte Post-Install:${NC} $PI_NAME"
      wine start /unix "$HOST_TARGET_DIR/$PI_NAME"
      wineserver -w
    fi
  done
fi

# ------------------------------------------------------------
# Pre-create savegame directories (best-effort)
# ------------------------------------------------------------
SAVE_COUNT="$(jq -r '.savegame_paths | length // 0' "$GAME_CONFIG")"
if (( SAVE_COUNT > 0 )); then
  for i in $(seq 0 $((SAVE_COUNT-1))); do
    SAVE_PAT="$(jq -r ".savegame_paths[$i]" "$GAME_CONFIG")"
    [[ -n "$SAVE_PAT" ]] && create_dir_from_pattern "$SAVE_PAT"
  done
fi

echo -e "${GREEN}Installation abgeschlossen.${NC}"

# ------------------------------------------------------------
# Optionally create run script in game dir for convenience
# ------------------------------------------------------------
if [[ -n "${HOST_GAME_DIR:-}" && -n "${EXE_FILE_WIN:-}" ]]; then
  RUN_SH="${INSTALL_DIR%/}/run.sh"
  cat >"$RUN_SH" <<EOF
#!/bin/bash
set -e
export WINEPREFIX="${WINEPREFIX}"
cd "${HOST_GAME_DIR}"
exec wine start /unix "${HOST_GAME_DIR%/}/${EXE_FILE_WIN}"
EOF
  chmod +x "$RUN_SH"
  echo -e "${GREEN}Run-Script:${NC} $RUN_SH"
fi

