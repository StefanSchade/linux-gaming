#!/bin/bash
# File: scripts/engines/_wineboot.sh
set -euo pipefail

umask 022

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

# NOTE: honor your path layout change
INSTALL_DIR="${INSTALL_PATH%/}/$GAME_ID/install/"
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
WINE_VERSION="$(jq_get '.wine_version')"   # e.g., win7, win10
EXE_PATH_WIN="$(jq_get '.exe_path')"
EXE_FILE_WIN="$(jq_get '.exe_file')"
INSTALLER_TYPE="$(jq_get '.installer_type')"
POST_INSTALL_COUNT="$(jq -r '.post_install | length // 0' "$GAME_CONFIG")"
INSTALLER_FILES_COUNT="$(jq -r '.installer_files | length // 0' "$GAME_CONFIG")"

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
require_tool() {
  local bin="$1" hint="$2"
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo -e "${RED}Fehlt: '$bin'.${NC} ${YELLOW}$hint${NC}"
    exit 1
  fi
}
have_tool() { command -v "$1" >/dev/null 2>&1; }

create_dir_from_pattern() {
  local pat="$1"
  if [[ "$pat" != prefix/* ]]; then
    return
  fi
  local sub="${pat#prefix/}"
  local hostpath="${WINEPREFIX%/}/$sub"
  if [[ "$hostpath" == */ && "$hostpath" != *'*'* && "$hostpath" != *'?'* && "$hostpath" != *'['* ]]; then
    mkdir -p -- "${hostpath%/}"
    return
  fi
  local static="${hostpath%%[\*\?\[]*}"
  static="${static%/}"
  [[ -z "$static" ]] && return
  [[ "$static" == *".."* ]] && return
  mkdir -p -- "$static"
}

to_host_path_from_win_c() {
  local win_rel="$1"
  echo "${WINEPREFIX%/}/drive_c/${win_rel}"
}

mount_copy_with_fuseiso() {
  local image="$1" dest="$2"
  require_tool "fuseiso" "sudo apt install fuseiso"
  local mnt; mnt="$(mktemp -d -t fuseiso.XXXXXXXX)"
  # Run fuseiso in background (default). Wait until mounted.
  fuseiso -- "$image" "$mnt"
  local tries=0
  while ! mountpoint -q "$mnt"; do
    sleep 0.1
    tries=$((tries+1))
    if (( tries > 100 )); then
      echo -e "${RED}fuseiso Mountpunkt nicht bereit: $mnt${NC}"
      # Best-effort unmount/cleanup
      fusermount -u "$mnt" 2>/dev/null || true
      rmdir "$mnt" 2>/dev/null || true
      exit 1
    fi
  done
  rsync -a "$mnt"/ "$dest"/
  fusermount -u "$mnt" 2>/dev/null || true
  rmdir "$mnt" 2>/dev/null || true   # do not fail if already removed
}

bchunk_to_iso_then_extract() {
  local bin="$1" cue="$2" outdir="$3"
  require_tool "bchunk" "sudo apt install bchunk"
  require_tool "7z" "sudo apt install p7zip-full"
  local tmpdir; tmpdir="$(mktemp -d -t bchunk.XXXXXXXX)"
  (cd "$tmpdir" && bchunk "$bin" "$cue" disc >/dev/null)
  local first_iso; first_iso="$(find "$tmpdir" -maxdepth 1 -type f -iname '*.iso' | sort | head -n1 || true)"
  if [[ -z "$first_iso" ]]; then
    echo -e "${RED}bchunk hat keine ISO erzeugt (unerwartetes Disc-Layout).${NC}"
    rm -rf "$tmpdir" || true
    exit 1
  fi
  7z x -y -o"$outdir" -- "$first_iso" >/dev/null
  rm -rf "$tmpdir" || true
}

extract_image_payload_into() {
  # Detect image type within $1 and merge its content into $2
  local src_root="$1" dest="$2"
  mkdir -p "$dest"

  local cue bin iso img mdf
  cue="$(find "$src_root" -type f -iname '*.cue' | head -n1 || true)"
  iso="$(find "$src_root" -type f -iname '*.iso' | head -n1 || true)"
  bin="$(find "$src_root" -type f -iname '*.bin' | head -n1 || true)"
  img="$(find "$src_root" -type f -iname '*.img' | head -n1 || true)"
  mdf="$(find "$src_root" -type f -iname '*.mdf' | head -n1 || true)"

  if [[ -n "$iso" ]]; then
    require_tool "7z" "sudo apt install p7zip-full"
    7z x -y -o"$dest" -- "$iso" >/dev/null
    return
  fi

  if [[ -n "$cue" && -n "$bin" ]]; then
    if have_tool fuseiso; then
      mount_copy_with_fuseiso "$bin" "$dest"
    else
      bchunk_to_iso_then_extract "$bin" "$cue" "$dest"
    fi
    return
  fi

  if [[ -n "$img" ]]; then
    if have_tool fuseiso; then
      mount_copy_with_fuseiso "$img" "$dest"
      return
    fi
    echo -e "${RED}IMG gefunden, aber 'fuseiso' fehlt.${NC}"
    exit 1
  fi

  if [[ -n "$mdf" ]]; then
    if have_tool fuseiso; then
      mount_copy_with_fuseiso "$mdf" "$dest"
      return
    fi
    echo -e "${RED}MDF gefunden, aber 'fuseiso' fehlt.${NC}"
    exit 1
  fi

  # Fallback: maybe the ZIP payload is already plain files (setup.exe etc.)
  if find "$src_root" -type f \( -iname 'setup.exe' -o -iname 'install.exe' -o -iname 'autorun.exe' \) | grep -q . ; then
    rsync -a "$src_root"/ "$dest"/
    return
  fi

  echo -e "${RED}Kein unterstütztes Disc-Image (ISO/BIN+CUE/IMG/MDF) im Archiv gefunden.${NC}"
  exit 1
}

run_installer_from_merged_source() {
  local merged_root="$1"
  local exe=""
  for name in setup.exe Setup.exe SETUP.EXE install.exe Install.exe INSTALL.EXE autorun.exe Autorun.exe AUTORUN.EXE; do
    local cand
    cand="$(find "$merged_root" -maxdepth 5 -type f -name "$name" | head -n1 || true)"
    if [[ -n "$cand" ]]; then exe="$cand"; break; fi
  done
  if [[ -z "$exe" ]]; then
    echo -e "${RED}Kein setup.exe/install.exe/autorun.exe im Installationsmedium gefunden.${NC}"
    exit 1
  fi
  echo -e "${GREEN}Starte Installer:${NC} $exe"
  wine start /unix "$exe"
  wineserver -w
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
  export WINEARCH=win32
else
  export WINEARCH="$WINE_ARCH"
fi

echo -e "${GREEN}Initialisiere Wine-Prefix ($WINEARCH) ...${NC}"
wineboot -u || true

# Optional Windows version via winetricks verbs (e.g., win7)
if [[ -n "${WINE_VERSION:-}" ]] && have_tool winetricks; then
  echo -e "${GREEN}Setze Windows-Version via winetricks:${NC} $WINE_VERSION"
  winetricks -q "$WINE_VERSION" || echo -e "${YELLOW}winetricks konnte '$WINE_VERSION' nicht setzen (ignoriere).${NC}"
fi

# ------------------------------------------------------------
# Installer handling
# ------------------------------------------------------------
TMP_ROOT="$(mktemp -d -t "${GAME_ID}_build.XXXXXXXX")"
cleanup() {
  # Make temp tree writable & best-effort unmount any stray fuse mounts
  if mount | grep -q "$TMP_ROOT"; then
    # Try to unmount any sub-mounts safely
    while read -r m; do
      fusermount -u "$m" 2>/dev/null || true
    done < <(mount | awk -v root="$TMP_ROOT" '$3 ~ "^"root {print $3}')
  fi
  chmod -R u+w "$TMP_ROOT" 2>/dev/null || true
  rm -rf "$TMP_ROOT" 2>/dev/null || true
}
trap cleanup EXIT

if [[ "$INSTALLER_TYPE" == "MULTI_DISC_ZIP" ]]; then
  echo -e "${GREEN}Modus:${NC} MULTI_DISC_ZIP – entpacke und merge Discs"
  require_tool "unzip" "sudo apt install unzip"
  require_tool "rsync" "sudo apt install rsync"

  if (( INSTALLER_FILES_COUNT == 0 )); then
    echo -e "${RED}installer_files[] ist leer in game.json.${NC}"
    exit 1
  fi

  MERGED_DIR="$TMP_ROOT/merged"
  mkdir -p "$MERGED_DIR"

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

    extract_image_payload_into "$ZIP_OUT" "$MERGED_DIR"
  done

  run_installer_from_merged_source "$MERGED_DIR"
else
  echo -e "${YELLOW}INSTALLER_TYPE != MULTI_DISC_ZIP – Engine erwartet externe Installer-Logik (z.B. GOG/Inno).${NC}"
fi

# ------------------------------------------------------------
# Post-install (e.g., SH2 Enhanced Edition)
# ------------------------------------------------------------
HOST_GAME_DIR=""
if [[ -n "$EXE_PATH_WIN" ]]; then
  HOST_GAME_DIR="$(to_host_path_from_win_c "$EXE_PATH_WIN")"
  mkdir -p "$HOST_GAME_DIR"
fi

if (( POST_INSTALL_COUNT > 0 )); then
  for idx in $(seq 0 $((POST_INSTALL_COUNT-1))); do
    PI_NAME="$(jq -r ".post_install[$idx]" "$GAME_CONFIG")"
    PI_SRC="${DOWNLOAD_DIR%/}/$PI_NAME"
    if [[ ! -f "$PI_SRC" ]]; then
      echo -e "${YELLOW}Post-Install Datei nicht gefunden:${NC} $PI_SRC (überspringe)"
      continue
    fi
    local_target="${HOST_GAME_DIR:-${WINEPREFIX%/}/drive_c/}"
    echo -e "${GREEN}Kopiere Post-Install:${NC} $PI_NAME -> $local_target"
    cp -f -- "$PI_SRC" "$local_target/"
    if [[ "${PI_NAME,,}" == *.exe ]]; then
      echo -e "${GREEN}Starte Post-Install:${NC} $PI_NAME"
      wine start /unix "$local_target/$PI_NAME"
      wineserver -w
    fi
  done
fi

# ------------------------------------------------------------
# Pre-create savegame directories
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
# Convenience run script (case-insensitive resolve)
# ------------------------------------------------------------
if [[ -n "${EXE_PATH_WIN:-}" && -n "${EXE_FILE_WIN:-}" ]]; then
  # Compute host path (may have wrong case)
  HOST_GAME_DIR="$(to_host_path_from_win_c "$EXE_PATH_WIN")"

  # If the directory doesn't exist due to case, try to find it case-insensitively
  if [[ ! -d "$HOST_GAME_DIR" ]]; then
    parent_dir="$(dirname "$HOST_GAME_DIR")"
    leaf_dir="$(basename "$HOST_GAME_DIR")"
    ci_dir="$(find "$parent_dir" -maxdepth 1 -type d -iname "$leaf_dir" -print -quit || true)"
    [[ -n "$ci_dir" ]] && HOST_GAME_DIR="$ci_dir"
  fi

  # Resolve EXE name case-insensitively as well
  EXE_HOST_PATH="$HOST_GAME_DIR/$EXE_FILE_WIN"
  if [[ ! -f "$EXE_HOST_PATH" ]]; then
    ci_exe="$(find "$HOST_GAME_DIR" -maxdepth 1 -type f -iname "$EXE_FILE_WIN" -print -quit || true)"
    [[ -n "$ci_exe" ]] && EXE_HOST_PATH="$ci_exe"
  fi

  if [[ -d "$HOST_GAME_DIR" && -f "$EXE_HOST_PATH" ]]; then
    RUN_SH="${INSTALL_DIR%/}/run.sh"
    cat >"$RUN_SH" <<EOF
#!/bin/bash
set -euo pipefail
export WINEPREFIX="${WINEPREFIX}"
GAME_DIR="${HOST_GAME_DIR}"
cd "\$GAME_DIR"
exec wine "./$(basename "$EXE_HOST_PATH")"
EOF
    chmod +x "$RUN_SH"
    echo -e "${GREEN}Run-Script:${NC} $RUN_SH"
  else
    echo -e "${YELLOW}Konnte Installationspfad/EXE nicht sicher auflösen. Überspringe run.sh-Erzeugung.${NC}"
  fi
fi

