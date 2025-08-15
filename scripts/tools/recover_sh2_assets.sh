#!/bin/bash
set -euo pipefail

GAME_ID="silent_hill_2_2002"
BASE="$HOME/games/$GAME_ID"
DOWNLOAD_DIR="$HOME/games/_downloads/$GAME_ID"
WINEPREFIX="$BASE/install/prefix"
GAME_DIR="$WINEPREFIX/drive_c/Program Files/Konami/SILENT HILL 2"

echo "[i] Game dir: $GAME_DIR"
mkdir -p "$GAME_DIR"

have() { command -v "$1" >/dev/null 2>&1; }

need() {
  local bin="$1" hint="$2"
  if ! have "$bin"; then
    echo "[!] '$bin' fehlt. $hint"
    exit 1
  fi
}

need unzip "sudo apt install unzip"
need rsync "sudo apt install rsync"

tmp="$(mktemp -d -t sh2assets.XXXXXXXX)"
cleanup(){ chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf "$tmp" || true; }
trap cleanup EXIT

copy_from_tree() {
  local src="$1"
  local copied=0
  # binkw32.dll
  local dll
  dll="$(find "$src" -type f -iname 'binkw32.dll' | head -n1 || true)"
  if [[ -n "$dll" ]]; then
    echo "[+] binkw32.dll -> $GAME_DIR"
    cp -f -- "$dll" "$GAME_DIR/"
    copied=1
  fi
  # Movies (optional, falls fehlen)
  if [[ ! -d "$GAME_DIR/movie" ]]; then
    local movdir
    movdir="$(find "$src" -type d -iname 'movie' | head -n1 || true)"
    if [[ -n "$movdir" ]]; then
      echo "[+] movie/* -> $GAME_DIR/movie/"
      mkdir -p "$GAME_DIR/movie"
      rsync -a "$movdir"/ "$GAME_DIR/movie"/
      copied=1
    fi
  fi
  return $copied
}

extract_image_payload_into() {
  local src_root="$1" dest="$2"
  mkdir -p "$dest"
  local cue bin iso img mdf
  cue="$(find "$src_root" -type f -iname '*.cue' | head -n1 || true)"
  iso="$(find "$src_root" -type f -iname '*.iso' | head -n1 || true)"
  bin="$(find "$src_root" -type f -iname '*.bin' | head -n1 || true)"
  img="$(find "$src_root" -type f -iname '*.img' | head -n1 || true)"
  mdf="$(find "$src_root" -type f -iname '*.mdf' | head -n1 || true)"

  if [[ -n "$iso" ]]; then
    need 7z "sudo apt install p7zip-full"
    7z x -y -o"$dest" -- "$iso" >/dev/null
    return
  fi

  if [[ -n "$cue" && -n "$bin" ]]; then
    if have fuseiso; then
      local mnt; mnt="$(mktemp -d -p "$tmp" mnt.XXXXXX)"
      fuseiso -- "$bin" "$mnt"
      rsync -a "$mnt"/ "$dest"/
      fusermount -u "$mnt" 2>/dev/null || true
      rmdir "$mnt" 2>/dev/null || true
    else
      need bchunk "sudo apt install bchunk"
      need 7z "sudo apt install p7zip-full"
      local bdir; bdir="$(mktemp -d -p "$tmp" bchunk.XXXXXX)"
      (cd "$bdir" && bchunk "$bin" "$cue" disc >/dev/null)
      local first_iso; first_iso="$(find "$bdir" -maxdepth 1 -type f -iname '*.iso' | sort | head -n1 || true)"
      [[ -z "$first_iso" ]] && { echo "[!] Kein ISO nach bchunk."; exit 1; }
      7z x -y -o"$dest" -- "$first_iso" >/dev/null
    fi
    return
  fi

  if [[ -n "$img" || -n "$mdf" ]]; then
    need fuseiso "sudo apt install fuseiso"
    local src_img="${img:-$mdf}"
    local mnt; mnt="$(mktemp -d -p "$tmp" mnt.XXXXXX)"
    fuseiso -- "$src_img" "$mnt"
    rsync -a "$mnt"/ "$dest"/
    fusermount -u "$mnt" 2>/dev/null || true
    rmdir "$mnt" 2>/dev/null || true
    return
  fi

  # Fallback: evtl. liegen Dateien schon plain
  rsync -a "$src_root"/ "$dest"/
}

# Wenn DLL schon da ist, nur nochmal sicherheitshalber Movies prüfen
if [[ -f "$GAME_DIR/binkw32.dll" && -d "$GAME_DIR/movie" ]]; then
  echo "[i] binkw32.dll und movie/ bereits vorhanden."
  exit 0
fi

# Alle 3 ZIPs durchgehen
shopt -s nullglob
zips=( "$DOWNLOAD_DIR"/*CD*.zip )
if (( ${#zips[@]} == 0 )); then
  echo "[!] Keine *CD*.zip im Download-Ordner gefunden: $DOWNLOAD_DIR"
  exit 1
fi

merged="$tmp/merged"
mkdir -p "$merged"
for z in "${zips[@]}"; do
  echo "[i] Entpacke $(basename "$z") ..."
  zout="$tmp/$(basename "$z" .zip)"
  mkdir -p "$zout"
  unzip -q "$z" -d "$zout"
  extract_image_payload_into "$zout" "$merged"
  if copy_from_tree "$merged"; then
    echo "[i] Benötigte Assets gefunden und kopiert."
    break
  fi
done

if [[ ! -f "$GAME_DIR/binkw32.dll" ]]; then
  echo "[!] binkw32.dll nicht gefunden. Prüfe manuell die Disc-Inhalte."
  exit 1
fi

echo "[OK] Fertig. Starte erneut:"
echo "$BASE/install/run.sh"

