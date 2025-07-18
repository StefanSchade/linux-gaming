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

# ---------------------------------------------
# Hilfsfunktion: Konfigurationswert mit Fallback
# ---------------------------------------------
load_conf_value() {
  local key="$1"
  local default="$2"
  local val
  val=$(jq -r --arg key "$key" '.[$key] // empty' "$GAME_CONFIG")
  [[ -n "$val" && "$val" != "null" ]] && echo "$val" && return
  val=$(jq -r --arg key "$key" '.[$key] // empty' "$GLOBAL_CONFIG")
  [[ -n "$val" && "$val" != "null" ]] && echo "$val" && return
  echo "$default"
}

# ---------------------------------------------
# Werte laden (mit Fallback)
# ---------------------------------------------
EXE_FILE=$(jq -r '.exe_file' "$GAME_CONFIG")
[[ "$EXE_FILE" == "null" || -z "$EXE_FILE" ]] && {
  echo -e "${RED}Fehler: exe_file fehlt in $GAME_CONFIG${NC}"
  exit 1
}

FULLSCREEN=$(load_conf_value "fullscreen" "true")
FULLRES=$(load_conf_value "fullresolution" "desktop")
WINDOWRES=$(load_conf_value "windowresolution" "1400x980")
OUTPUT=$(load_conf_value "output" "opengl")
SCALER=$(load_conf_value "scaler" "normal2x")
MEMSIZE=$(load_conf_value "memsize" "16")
CYCLES=$(load_conf_value "cycles" "auto")
ASPECT=$(load_conf_value "aspect" "true")
RATE=$(load_conf_value "rate" "44100")

# ---------------------------------------------
# Spieldateien kopieren
# ---------------------------------------------
echo -e "${GREEN}Kopiere Spieldateien nach $INSTALL_DIR ...${NC}"
cp -r "$DOWNLOAD_DIR/"* "$INSTALL_DIR/"

# ---------------------------------------------
# Autoexec bestimmen
# ---------------------------------------------
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

# ---------------------------------------------
# dosbox.conf schreiben
# ---------------------------------------------
CONF_TARGET="$INSTALL_DIR/${GAME_ID}.conf"
cat > "$CONF_TARGET" <<EOF
[sdl]
fullscreen=$FULLSCREEN
fullresolution=$FULLRES
windowresolution=$WINDOWRES
output=$OUTPUT
autolock=false

[render]
aspect=$ASPECT
scaler=$SCALER

[dosbox]
machine=svga_s3
memsize=$MEMSIZE
captures=captures

[cpu]
core=auto
cputype=auto
cycles=$CYCLES
cycleup=10
cycledown=20

[mixer]
nosound=false
rate=$RATE
blocksize=2048
prebuffer=25

[midi]
mpu401=intelligent
mididevice=default
midiconfig=

[sblaster]
sbtype=sb16
sbbase=220
irq=7
dma=1
hdma=5
mixer=true
oplmode=auto
oplemu=default
oplrate=$RATE

[gus]
gus=false

[speaker]
pcspeaker=false
pcrate=$RATE
tandy=off
tandyrate=$RATE
disney=false

[joystick]
joysticktype=auto

[serial]
serial1=dummy
serial2=dummy
serial3=disabled
serial4=disabled

[dos]
xms=true
ems=true
umb=true

[ipx]
ipx=false

[autoexec]
$AUTOEXEC_BLOCK
EOF

# ---------------------------------------------
# Start- und Uninstall-Skripte erzeugen
# ---------------------------------------------
cat > "$INSTALL_DIR/start.sh" <<EOF
#!/bin/bash
dosbox "$CONF_TARGET" -exit -fullscreen
EOF
chmod +x "$INSTALL_DIR/start.sh"

cat > "$INSTALL_DIR/uninstall.sh" <<EOF
#!/bin/bash
echo "Entferne Spiel: $GAME_ID"
rm -rf "$INSTALL_DIR"
EOF
chmod +x "$INSTALL_DIR/uninstall.sh"

# ---------------------------------------------
# Abschlussmeldung
# ---------------------------------------------
echo -e "${GREEN}Installation abgeschlossen. Starte das Spiel mit:${NC}"
echo "$INSTALL_DIR/start.sh"

