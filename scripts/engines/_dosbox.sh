#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../_config.sh"

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
GLOBAL_CONFIG="$CONFIG_PATH/global.json"
GAME_CONFIG="$CONFIG_DIR/game.json"

if [[ ! -f "$GAME_CONFIG" ]]; then
  echo -e "${RED}Fehler: $GAME_CONFIG fehlt${NC}"
  exit 1
fi

mkdir -p "$INSTALL_DIR"

# Werte aus game.json lesen
EXE_FILE=$(jq -r '.exe_file' "$GAME_CONFIG")
if [[ "$EXE_FILE" == "null" ]]; then
  echo -e "${RED}Fehler: exe_file fehlt in $GAME_CONFIG${NC}"
  exit 1
fi

# Werte aus global.json lesen (z. B. Bildschirmauflösung)
FULLRES=$(jq -r '.fullresolution // "desktop"' "$GLOBAL_CONFIG")

# Spieldateien kopieren
echo -e "${GREEN}Kopiere Spieldateien nach $INSTALL_DIR ...${NC}"
cp -r "$DOWNLOAD_DIR/"* "$INSTALL_DIR/"

# AUTOEXEC-BLOCK: entweder aus autoexec.template oder generisch
if [[ -f "$CONFIG_DIR/autoexec.template" ]]; then
  echo "Verwende benutzerdefinierten autoexec.template"
  AUTOEXEC_BLOCK=$(< "$CONFIG_DIR/autoexec.template")
else
  echo "Erzeuge generischen autoexec-Block"
  AUTOEXEC_BLOCK=$(cat <<EOF
@echo off
mount c $INSTALL_DIR
c:
$EXE_FILE
exit
EOF
)
fi

# dosbox.conf erzeugen aus Template
TEMPLATE="$SCRIPT_DIR/../templates/dosbox.conf.template"
CONF_TARGET="$INSTALL_DIR/${GAME_ID}.conf"

if [[ ! -f "$TEMPLATE" ]]; then
  echo -e "${RED}Fehler: Template $TEMPLATE nicht gefunden${NC}"
  exit 1
fi

# Template mit Variablen ersetzen
sed \
  -e "s|__INSTALL_DIR__|$INSTALL_DIR|g" \
  -e "s|__FULLRESOLUTION__|$FULLRES|g" \
  -e "/__AUTOEXEC__/{
    s|__AUTOEXEC__||g
    r /dev/stdin
  }" "$TEMPLATE" <<< "$AUTOEXEC_BLOCK" > "$CONF_TARGET"

# start.sh erzeugen
cat > "$INSTALL_DIR/start.sh" <<EOF
#!/bin/bash
dosbox "$CONF_TARGET" -exit -fullscreen
EOF
chmod +x "$INSTALL_DIR/start.sh"

# uninstall.sh erzeugen
cat > "$INSTALL_DIR/uninstall.sh" <<EOF
#!/bin/bash
echo "Entferne Spiel: $GAME_ID"
rm -rf "$INSTALL_DIR"
EOF
chmod +x "$INSTALL_DIR/uninstall.sh"

echo -e "${GREEN}Installation abgeschlossen. Starte das Spiel mit:${NC}"
echo "$INSTALL_DIR/start.sh"

