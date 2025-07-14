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
GLOBAL_CONFIG="$CONFIG_PATH/global.json"

if [[ ! -f "$GAME_CONFIG" ]]; then
  echo -e "${RED}Fehler: $GAME_CONFIG fehlt${NC}"
  exit 1
fi

if [[ ! -f "$GLOBAL_CONFIG" ]]; then
  echo -e "${RED}Fehler: $GLOBAL_CONFIG fehlt${NC}"
  exit 1
fi

EXE_PATH=$(jq -r '.exe_path' "$GAME_CONFIG")
EXE_FILE=$(jq -r '.exe_file' "$GAME_CONFIG")
WINE_SAVE_PATH=$(jq -r '.wine_save_path' "$GLOBAL_CONFIG")

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

INSTALLER=$(find "$DOWNLOAD_DIR" -type f -iname "*.exe" | head -n 1)
if [[ ! -f "$INSTALLER" ]]; then
  echo -e "${RED}Kein Installer in $DOWNLOAD_DIR gefunden${NC}"
  exit 1
fi

wine "$INSTALLER" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-

# start.sh erzeugen
cat > "$INSTALL_DIR/start.sh" <<EOF
#!/bin/bash
export WINEPREFIX="$INSTALL_DIR/prefix"
export WINEDEBUG=-all
export WINE_SAVEDIR="${WINE_SAVE_PATH}/${GAME_ID}"
cd "\$WINEPREFIX/drive_c/$EXE_PATH"
wine "$EXE_FILE"
EOF
chmod +x "$INSTALL_DIR/start.sh"

# uninstall.sh erzeugen
cat > "$INSTALL_DIR/uninstall.sh" <<EOF
#!/bin/bash
echo "Entferne Spiel: $GAME_ID"
rm -rf "\$(dirname "\$0")/prefix"
EOF
chmod +x "$INSTALL_DIR/uninstall.sh"

echo -e "${GREEN}Installation abgeschlossen. Starte das Spiel mit:$NC"
echo "$INSTALL_DIR/start.sh"

