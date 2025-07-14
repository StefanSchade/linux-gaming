#!/bin/bash
set -e

source "$(dirname "$0")/../_config.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

GAME_ID="$1"
if [[ -z "$GAME_ID" ]]; then
  echo -e "${RED}Usage: $0 <game_id>${NC}"
  exit 1
fi

INSTALL_DIR="$INSTALL_PATH/$GAME_ID"
DOWNLOAD_DIR="$DOWNLOAD_PATH/$GAME_ID"
CONFIG_DIR="$CONFIG_PATH/$GAME_ID"
GAME_CONFIG="$CONFIG_DIR/game.json"

if [[ ! -f "$GAME_CONFIG" ]]; then
  echo -e "${RED}Fehler: $GAME_CONFIG fehlt${NC}"
  exit 1
fi

EXE_PATH=$(jq -r '.exe_path' "$GAME_CONFIG")
EXE_FILE=$(jq -r '.exe_file' "$GAME_CONFIG")
SAVEDIR="$SAVEGAME_PATH/$GAME_ID"

if [[ "$EXE_PATH" == "null" || "$EXE_FILE" == "null" ]]; then
  echo -e "${RED}Fehler: exe_path oder exe_file fehlt in $GAME_CONFIG${NC}"
  exit 1
fi

if [[ -d "$INSTALL_DIR" && -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]]; then
  echo -e "${RED}Fehler: $INSTALL_DIR ist nicht leer${NC}"
  exit 1
fi

echo -e "${GREEN}Installation wird gestartet...${NC}"
mkdir -p "$INSTALL_DIR/prefix"
cd "$INSTALL_DIR"
export WINEPREFIX="$INSTALL_DIR/prefix"

wineboot -u

WINE_VERSION=$(jq -r '.wine_version // empty' "$GAME_CONFIG")
if [[ -n "$WINE_VERSION" && "$WINE_VERSION" != "null" ]]; then
  echo "Setze Wine-Version auf $WINE_VERSION"
  wine reg add "HKCU\\Software\\Wine" /v Version /d "$WINE_VERSION" /f
else
  echo "Keine Wine-Version angegeben – Standard bleibt erhalten"
fi

INSTALLERS=()
EXPLICIT_INSTALLERS=$(jq -r '.installers[]?' "$GAME_CONFIG" 2>/dev/null)

if [[ -n "$EXPLICIT_INSTALLERS" ]]; then
  echo "Verwende explizit konfigurierte Installer:"
  while IFS= read -r line; do
    INSTALLERS+=("$DOWNLOAD_DIR/$line")
  done <<< "$EXPLICIT_INSTALLERS"
else
  echo "Keine Installer-Liste gefunden – verwende alle .exe im Download-Verzeichnis"
  mapfile -t INSTALLERS < <(find "$DOWNLOAD_DIR" -type f -iname "*.exe" | sort)
fi

for INSTALLER in "${INSTALLERS[@]}"; do
  echo "→ Installiere: $INSTALLER"
  wine "$INSTALLER" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-
done

# Absolute Pfade für Start- und Hilfsskripte vorbereiten
START_SH="$INSTALL_DIR/start.sh"
UNINSTALL_SH="$INSTALL_DIR/uninstall.sh"
ROTATE_OUT="$INSTALL_DIR/rotate_save_to_slot.sh"
ROTATE_IN="$INSTALL_DIR/rotate_slot_to_save.sh"
LIST_SLOTS="$INSTALL_DIR/list_slots.sh"
DELETE_SLOT="$INSTALL_DIR/delete_slot.sh"

# start.sh
cat > "$START_SH" <<EOF
#!/bin/bash
export WINEPREFIX="$INSTALL_DIR/prefix"
export WINEDEBUG=-all
export SAVEDIR="$SAVEDIR"
cd "\$WINEPREFIX/drive_c/$EXE_PATH"
wine "$EXE_FILE"
EOF
chmod +x "$START_SH"

# uninstall.sh
cat > "$UNINSTALL_SH" <<EOF
#!/bin/bash
echo "Entferne Spiel: $GAME_ID"
rm -rf "$INSTALL_DIR"
EOF
chmod +x "$UNINSTALL_SH"

# rotate_save_to_slot.sh
cat > "$ROTATE_OUT" <<EOF
#!/bin/bash
set -e
SLOT="\$1"
if [[ -z "\$SLOT" ]]; then
  echo "Usage: \$0 <slotname>"
  exit 1
fi
SRC="$SAVEDIR"
DEST="$SAVESLOT_PATH/$GAME_ID/\$SLOT"
mkdir -p "\$DEST"
cp -r "\$SRC/"* "\$DEST/"
echo "Savegame wurde nach Slot '\$SLOT' exportiert."
EOF
chmod +x "$ROTATE_OUT"

# rotate_slot_to_save.sh
cat > "$ROTATE_IN" <<EOF
#!/bin/bash
set -e
SLOT="\$1"
if [[ -z "\$SLOT" ]]; then
  echo "Usage: \$0 <slotname>"
  exit 1
fi
SRC="$SAVESLOT_PATH/$GAME_ID/\$SLOT"
DEST="$SAVEDIR"
if [[ ! -d "\$SRC" ]]; then
  echo "Slot nicht gefunden: \$SRC"
  exit 1
fi
cp -r "\$SRC/"* "\$DEST/"
echo "Slot '\$SLOT' wurde ins Spielverzeichnis wiederhergestellt."
EOF
chmod +x "$ROTATE_IN"

# list_slots.sh
cat > "$LIST_SLOTS" <<EOF
#!/bin/bash
SLOTDIR="$SAVESLOT_PATH/$GAME_ID"
if [[ ! -d "\$SLOTDIR" ]]; then
  echo "Keine Slots gefunden für $GAME_ID."
  exit 0
fi
echo "Verfügbare Slots für $GAME_ID:"
ls -1 "\$SLOTDIR"
EOF
chmod +x "$LIST_SLOTS"

# delete_slot.sh
cat > "$DELETE_SLOT" <<EOF
#!/bin/bash
set -e
SLOT="\$1"
if [[ -z "\$SLOT" ]]; then
  echo "Usage: \$0 <slotname>"
  exit 1
fi
SLOT_DIR="$SAVESLOT_PATH/$GAME_ID/\$SLOT"
if [[ ! -d "\$SLOT_DIR" ]]; then
  echo "Slot '\$SLOT' existiert nicht."
  exit 1
fi
rm -rf "\$SLOT_DIR"
echo "Slot '\$SLOT' wurde gelöscht."
EOF
chmod +x "$DELETE_SLOT"

echo -e "${GREEN}Installation abgeschlossen. Starte das Spiel mit:${NC}"
echo "$START_SH"

