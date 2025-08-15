#!/bin/bash
set -euo pipefail

# Zielspiel
GAME_ID="silent_hill_2_2002"

# Pfade
BASE="$HOME/games/$GAME_ID"
DOWNLOAD_DIR="$HOME/games/_downloads/$GAME_ID"
WINEPREFIX="$BASE/install/prefix"
GAME_DIR="$WINEPREFIX/drive_c/Program Files/Konami/SILENT HILL 2"

# Helfer
have() { command -v "$1" >/dev/null 2>&1; }
need(){ have "$1" || { echo "[!] Fehlt: $1 — $2"; exit 1; }; }

# Anforderungen
need unzip "sudo apt install unzip"
need rsync "sudo apt install rsync"
need unshield "sudo apt install unshield"
# Für Image-Inhalte: eines von beiden reicht (fuseiso bevorzugt)
if ! have fuseiso && ! have bchunk; then
  echo "[!] Weder fuseiso noch bchunk vorhanden. Installiere eines davon:"
  echo "    sudo apt install fuseiso    # bevorzugt (kein root nötig)"
  echo "    oder: sudo apt install bchunk p7zip-full"
  exit 1
fi
# Für bchunk-Pfad auch 7z nötig
if have bchunk && ! have 7z; then
  echo "[!] 7z fehlt (für bchunk-Pfad). Installiere: sudo apt install p7zip-full"
  exit 1
fi

mkdir -p "$GAME_DIR"

tmp="$(mktemp -d -t sh2_bink.XXXXXXXX)"
cleanup(){
  # best-effort unmount & löschen
  if mount | grep -q "$tmp"; then
    while read -r m; do fusermount -u "$m" 2>/dev/null || true; done < <(mount | awk -v r="$tmp" '$3 ~ "^"r {print $3}')
  fi
  chmod -R u+w "$tmp" 2>/dev/null || true
  rm -rf "$tmp" 2>/dev/null || true
}
trap cleanup EXIT

mount_copy_with_fuseiso(){
  local image="$1" dest="$2"
  local mnt; mnt="$(mktemp -d -p "$tmp" mnt.XXXXXX)"
  fuseiso -- "$image" "$mnt"
  # Warten bis gemountet
  for _ in {1..100}; do mountpoint -q "$mnt" && break; sleep 0.05; done
  rsync -a "$mnt"/ "$dest"/
  fusermount -u "$mnt" 2>/dev/null || true
  rmdir "$mnt" 2>/dev/null || true
}

bchunk_to_iso_then_extract(){
  local bin="$1" cue="$2" out="$3"
  local bdir; bdir="$(mktemp -d -p "$tmp" bchunk.XXXXXX)"
  (cd "$bdir" && bchunk "$bin" "$cue" disc >/dev/null)
  local iso; iso="$(find "$bdir" -maxdepth 1 -type f -iname '*.iso' | sort | head -n1 || true)"
  [[ -n "$iso" ]] || { echo "[!] bchunk erzeugte kein ISO."; exit 1; }
  7z x -y -o"$out" -- "$iso" >/dev/null
}

extract_image_payload_into(){
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
    if have fuseiso; then mount_copy_with_fuseiso "$bin" "$dest"; else bchunk_to_iso_then_extract "$bin" "$cue" "$dest"; fi
    return
  fi
  if [[ -n "$img" || -n "$mdf" ]]; then
    have fuseiso || { echo "[!] IMG/MDF ohne fuseiso nicht unterstützt."; exit 1; }
    mount_copy_with_fuseiso "${img:-$mdf}" "$dest"
    return
  fi
  # Fallback: evtl. liegen Dateien schon plain im ZIP
  rsync -a "$src_root"/ "$dest"/
}

extract_bink_from_installshield(){
  # durchsucht $1 nach data1.cab und extrahiert binkw32.dll nach $GAME_DIR
  local root="$1"
  local cab
  cab="$(find "$root" -type f -iname 'data1.cab' | head -n1 || true)"
  [[ -n "$cab" ]] || return 1
  local out="$tmp/unshield_out"
  mkdir -p "$out"
  # a) gezielt nach binkw32.dll
  if unshield l "$cab" >/dev/null 2>&1; then
    # unshield list → Namen zeilenweise; wir versuchen case-insensitive Filter
    local name
    name="$(unshield l "$cab" | awk 'BEGIN{IGNORECASE=1}/binkw32\.dll/{print $0}' | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//' | awk -F']' '{print $NF}' | sed 's/^[[:space:]]*//')"
    if [[ -n "${name:-}" ]]; then
      unshield x -d "$out" "$cab" "$name" >/dev/null || true
    else
      unshield x -d "$out" "$cab" >/dev/null || true
    fi
  else
    # b) sehr alte IS-Variante → Vollentpackung
    unshield x -d "$out" "$cab" >/dev/null || true
  fi
  local dll
  dll="$(find "$out" -type f -iname 'binkw32.dll' | head -n1 || true)"
  if [[ -n "$dll" ]]; then
    echo "[+] binkw32.dll -> $GAME_DIR"
    cp -f -- "$dll" "$GAME_DIR/"
    return 0
  fi
  return 1
}

echo "[i] Game dir: $GAME_DIR"

# Wenn DLL schon da ist, nur Erfolg melden
if [[ -f "$GAME_DIR/binkw32.dll" ]]; then
  echo "[i] binkw32.dll bereits vorhanden."
  exit 0
fi

mkdir -p "$tmp/merged"
shopt -s nullglob
zips=( "$DOWNLOAD_DIR"/*CD*.zip )
(( ${#zips[@]} > 0 )) || { echo "[!] Keine *CD*.zip in $DOWNLOAD_DIR"; exit 1; }

# Alle Discs: erst Image-Inhalt extrahieren, dann CAB durchsuchen
found=0
for z in "${zips[@]}"; do
  echo "[i] Verarbeite $(basename "$z") ..."
  zout="$tmp/$(basename "$z" .zip)"
  mkdir -p "$zout"
  unzip -q "$z" -d "$zout"
  disc="$tmp/disc_$(basename "$z" .zip)"
  mkdir -p "$disc"
  extract_image_payload_into "$zout" "$disc"

  # Nebenbei: falls Filme noch fehlen, kopieren
  if [[ ! -d "$GAME_DIR/movie" ]]; then
    movdir="$(find "$disc" -type d -iname 'movie' | head -n1 || true)"
    if [[ -n "$movdir" ]]; then
      echo "[+] movie/* -> $GAME_DIR/movie/"
      mkdir -p "$GAME_DIR/movie"
      rsync -a "$movdir"/ "$GAME_DIR/movie"/
    fi
  fi

  if extract_bink_from_installshield "$disc"; then
    found=1
    break
  fi
done

if (( found )); then
  echo "[OK] binkw32.dll extrahiert. Starte erneut:"
  echo "$BASE/install/run.sh"
  exit 0
else
  echo "[X] binkw32.dll weiterhin nicht auffindbar."
  echo "    Möglichkeiten:"
  echo "    • Installer erneut laufen lassen (nicht-silent), Full + Movies on HDD."
  echo "    • Oder binkw32.dll aus einer legalen Quelle (z. B. GOG-Installation) ins Game-Verzeichnis kopieren."
  exit 1
fi

