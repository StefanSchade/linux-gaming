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

if [[ "$EXE_PATH" == "null" || "$EXE_FILE" == "null" ]]; then
  echo -e "${RED}Fehler: exe_path oder exe_file fehlt in $GAME_CONFIG${NC}"
  exit 1
fi

if [[ -d "$INSTALL_DIR" && -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]]; then
  echo -e "${RED}Fehler: $INSTALL_DIR ist nicht leer${NC}"
  exit 1
fi

mkdir -p "$INSTALL_DIR/prefix"
echo -e "${GREEN}Installation wird gestartet...${NC}"
cd "$INSTALL_DIR"
export WINEPREFIX="$INSTALL_DIR/prefix"

# Initialisiere Prefix
wineboot -u

# Wine-Version setzen (optional)
WINE_VERSION=$(jq -r '.wine_version // empty' "$GAME_CONFIG")
if [[ -n "$WINE_VERSION" && "$WINE_VERSION" != "null" ]]; then
  echo "Setze Wine-Version auf $WINE_VERSION"
  wine reg add "HKCU\\Software\\Wine" /v Version /d "$WINE_VERSION" /f
else
  echo "Keine Wine-Version angegeben – Standard bleibt erhalten"
fi

# Installer bestimmen
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

# Installer ausführen
for INSTALLER in "${INSTALLERS[@]}"; do
  echo "→ Installiere: $INSTALLER"
  wine "$INSTALLER" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-
done


# Symlink-Bereinigung und Registry-Tweak für 'My Documents'
# DOCS_DIR="$WINEPREFIX/drive_c/users/$(whoami)/Documents"
# SAVE_DIR_WIN="C:\\games\\_savegame\\$GAME_ID"
# SAVE_DIR_NATIVE="$SAVEGAME_PATH/$GAME_ID"
# DOCS_TARGET="$WINEPREFIX/drive_c/games/_savegame/$GAME_ID"

# start.sh erzeugen
cat > "$INSTALL_DIR/start.sh" <<EOF
#!/bin/bash
export WINEPREFIX="$INSTALL_DIR/prefix"
export WINEDEBUG=-all
export SAVEDIR="$SAVE_DIR"
cd "\$WINEPREFIX/drive_c/$EXE_PATH"
wine "$EXE_FILE"
EOF
chmod +x "$INSTALL_DIR/start.sh"

# uninstall.sh erzeugen
cat > "$INSTALL_DIR/uninstall.sh" <<EOF
#!/bin/bash
echo "Entferne Spiel: $GAME_ID"
rm -rf $INSTALL_DIR/prefix
rm $INSTALL_DIR/*.sh
EOF
chmod +x "$INSTALL_DIR/uninstall.sh"

echo -e "${GREEN}Installation abgeschlossen. Starte das Spiel mit:${NC}"
echo "$INSTALL_DIR/start.sh"

