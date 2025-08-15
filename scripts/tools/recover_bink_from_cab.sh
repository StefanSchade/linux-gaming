#!/bin/bash
set -euo pipefail

GAME_ID="silent_hill_2_2002"
DOWNLOAD_DIR="$HOME/games/_downloads/$GAME_ID"
WINEPREFIX="$HOME/games/$GAME_ID/install/prefix"
GAME_DIR="$WINEPREFIX/drive_c/Program Files/Konami/SILENT HILL 2"

have(){ command -v "$1" >/dev/null 2>&1; }

need(){
  local b="$1" hint="$2"
  have "$b" || { echo "Fehlt: $b ($hint)"; exit 1; }
}

need unshield "sudo apt install unshield"
need unzip    "sudo apt install unzip"
need rsync    "sudo apt install rsync"

mkdir -p "$GAME_DIR"
tmp="$(mktemp -d -t sh2bink.XXXXXXXX)"
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT

extract_from_zip(){
  local zip="$1"
  local zout="$tmp/$(basename "$zip" .zip)"
  mkdir -p "$zout"
  unzip -q "$zip" -d "$zout"

  # Falls im ZIP ein Image steckt, extrahiere zuerst sichtbare Dateien,
  # weil manche Discs data1.cab direkt im Root haben:
  rsync -a "$zout"/ "$tmp/merged"/ 2>/dev/null || true

  # Suche CAB/HDR-Paar (InstallShield)
  local cab hdr
  cab="$(find "$zout" -type f -iname 'data1.cab' | head -n1 || true)"
  hdr="$(find "$zout" -type f -iname 'data1.hdr' | head -n1 || true)"

  if [[ -n "$cab" ]]; then
    # Unshield braucht nur den CAB-Pfad; HDR liegt i.d.R. daneben.
    local out="$tmp/unshield_out"
    mkdir -p "$out"
    # Liste auflösen, um korrekten Groß/Kleinschreibungs-Pfad zu treffen:
    if unshield l "$cab" >/dev/null 2>&1; then
      local name
      name="$(unshield l "$cab" | awk 'BEGIN{IGNORECASE=1} /binkw32\.dll/{print; found=1} END{if(!found) exit 1}' | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//' | awk -F']' '{print $NF}' | sed 's/^[[:space:]]*//')"
      if [[ -n "${name:-}" ]]; then
        echo "[i] Extrahiere aus CAB: $name"
        unshield x -d "$out" "$cab" "$name" >/dev/null
      else
        # Fallback: versuche alles und filtere danach
        unshield x -d "$out" "$cab" >/dev/null || true
      fi
    else
      # Manche sehr alten IS-Versionen – bruteforce extract
      unshield x -d "$out" "$cab" >/dev/null || true
    fi

    # DLL einsammeln (case-insensitive)
    local dll
    dll="$(find "$out" -type f -iname 'binkw32.dll' | head -n1 || true)"
    if [[ -n "$dll" ]]; then
      echo "[+] binkw32.dll -> $GAME_DIR"
      cp -f -- "$dll" "$GAME_DIR/"
      return 0
    fi
  fi

  return 1
}

mkdir -p "$tmp/merged"
shopt -s nullglob
zips=( "$DOWNLOAD_DIR"/*CD*.zip )
if (( ${#zips[@]} == 0 )); then
  echo "Keine *CD*.zip in $DOWNLOAD_DIR"
  exit 1
fi

found=0
for z in "${zips[@]}"; do
  echo "[i] Prüfe $(basename "$z") ..."
  if extract_from_zip "$z"; then
    found=1
    break
  fi
done

if (( ! found )); then
  echo "[!] binkw32.dll nicht in CAB gefunden. Prüfe, ob der Installer sie bereits ins Game-Verzeichnis gelegt hat."
fi

if [[ -f "$GAME_DIR/binkw32.dll" ]]; then
  echo "[OK] binkw32.dll vorhanden. Starte Spiel erneut:"
  echo "$HOME/games/$GAME_ID/install/run.sh"
  exit 0
else
  echo "[X] binkw32.dll weiterhin fehlt. Workarounds:"
  echo "    • Installer erneut ausführen (ggf. nicht-silent) und Full+Movies on HDD wählen."
  echo "    • Oder GOG/andere legale Quelle verwenden und DLL aus dortiger Installation kopieren."
  exit 1
fi

