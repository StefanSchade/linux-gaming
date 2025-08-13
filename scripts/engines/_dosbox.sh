#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR%/}/../_config.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

GAME_ID="$1"
if [[ -z "$GAME_ID" ]]; then
  echo -e "${RED}Usage: $0 <game_id>${NC}"
  exit 1
fi

INSTALL_DIR="${INSTALL_PATH%/}/$GAME_ID/install"
GAME_DIR="${INSTALL_PATH%/}/$GAME_ID/"
DOWNLOAD_DIR="${DOWNLOAD_PATH%/}/$GAME_ID/"
CONFIG_DIR="${CONFIG_PATH%/}/$GAME_ID/"
GLOBAL_CONFIG="${CONFIG_PATH%/}/global.json"
GAME_CONFIG="${CONFIG_DIR%/}/game.json"

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
# Werte laden (mit Fallback) exe nur wenn kein autoexec.template
# ---------------------------------------------

if [[ ! -f "${CONFIG_DIR%/}/autoexec.template" ]]; then
  EXE_FILE=$(jq -r '.exe_file' "$GAME_CONFIG")
  if [[ -z "$EXE_FILE" || "$EXE_FILE" == "null" ]]; then
    echo -e "${RED}Fehler: exe_file fehlt in $GAME_CONFIG und kein autoexec.template vorhanden${NC}"
    exit 1
  fi
fi

FULLSCREEN=$(load_conf_value "fullscreen" "false")
FULLRES=$(load_conf_value "fullresolution" "desktop")
WINDOWRES=$(load_conf_value "windowresolution" "1400x980")
OUTPUT=$(load_conf_value "output" "opengl")
SCALER=$(load_conf_value "scaler" "normal2x")
MEMSIZE=$(load_conf_value "memsize" "16")
CYCLES=$(load_conf_value "cycles" "auto")
ASPECT=$(load_conf_value "aspect" "true")
RATE=$(load_conf_value "rate" "44100")
SPEAKER=$(load_conf_value "pcspeaker" "false")

# ---------------------------------------------
# Installer erkennen und verarbeiten
# ---------------------------------------------

INSTALLER=$(jq -r '.installer // empty' "$GAME_CONFIG")
INSTALLER_TYPE=$(jq -r '.installer_type // "auto"' "$GAME_CONFIG")

echo "→ Prüfe Installer-Konfiguration:"

if [[ -n "$INSTALLER" ]]; then
  echo "  → Konfigurierter Installer: $INSTALLER"
  INSTALLER="${DOWNLOAD_DIR%/}/$INSTALLER"
else
  echo "  → Kein Installer konfiguriert, starte heuristische Suche..."
  INSTALLER=$(find "$DOWNLOAD_DIR" -type f \( -iname "*.zip" -o -iname "*.exe" \) | head -n1)
  if [[ -n "$INSTALLER" ]]; then
    echo "  → Gefundener Installer: $INSTALLER"
  else
    echo -e "${RED}Fehler: Kein Installer gefunden im Download-Verzeichnis${NC}"
    exit 1
  fi
fi

# ---------------------------------------------
# Installer-Typ bestimmen (sofern nicht gesetzt)
# ---------------------------------------------

if [[ "$INSTALLER_TYPE" == "auto" || -z "$INSTALLER_TYPE" ]]; then
  echo "→ Kein installer_type gesetzt – heuristische Bestimmung..."

  if [[ "$INSTALLER" == *.zip ]]; then
    if unzip -l "$INSTALLER" | grep -i '\.iso' >/dev/null; then
      INSTALLER_TYPE="iso_install"
      echo "  → Enthält ISO: Typ = iso_install"
    else
      INSTALLER_TYPE="zip_plain"
      echo "  → Normales ZIP: Typ = zip_plain"
    fi
  elif [[ "$INSTALLER" == *.exe ]]; then
    if innoextract --silent --list "$INSTALLER" >/dev/null 2>&1; then
      INSTALLER_TYPE="gog"
      echo "  → GOG-Installer erkannt"
    else
      INSTALLER_TYPE="exe"
      echo "  → Normale EXE-Datei"
    fi
  else
    echo -e "${RED}Fehler: Unbekannter Installer-Typ für Datei: $INSTALLER${NC}"
    exit 1
  fi
else
  echo "→ Installer-Typ aus game.json: $INSTALLER_TYPE"
fi

# ---------------------------------------------
# Verarbeitung des Installers je nach Typ
# ---------------------------------------------

case "$INSTALLER_TYPE" in

  iso_install)
    echo -e "${GREEN}ZIP mit ISO (Install-Quelle) – entpacke...${NC}"
    unzip -q -o "$INSTALLER" -d "$INSTALL_DIR"
    ISO_FILE=$(find "$INSTALL_DIR" -iname "*.iso" | head -n1)
    if [[ -z "$ISO_FILE" ]]; then
      echo -e "${RED}Fehler: Keine ISO-Datei im ZIP gefunden.${NC}"
      exit 1
    fi
    MOUNT_ISO="$ISO_FILE"
    INSTALL_MODE="iso_install"
    ;;

  iso_install_and_run)
    echo -e "${GREEN}ISO enthält Spiel und Setup – entpacke und mount vorbereiten...${NC}"
    unzip -q -o "$INSTALLER" -d "$INSTALL_DIR"
    ISO_FILE=$(find "$INSTALL_DIR" -iname "*.iso" | head -n1)
    if [[ -z "$ISO_FILE" ]]; then
      echo -e "${RED}Fehler: Keine ISO-Datei im ZIP gefunden.${NC}"
      exit 1
    fi
    MOUNT_ISO="$ISO_FILE"
    INSTALL_MODE="iso_install_and_run"
    ;;

  iso_runtime)
    echo -e "${GREEN}ISO wird zur Laufzeit benötigt – entpacke und mount vorbereiten...${NC}"
    unzip -q -o "$INSTALLER" -d "$INSTALL_DIR"
    ISO_FILE=$(find "$INSTALL_DIR" -iname "*.iso" | head -n1)
    if [[ -z "$ISO_FILE" ]]; then
      echo -e "${RED}Fehler: Keine ISO-Datei im ZIP gefunden.${NC}"
      exit 1
    fi
    MOUNT_ISO="$ISO_FILE"
    INSTALL_MODE="iso_runtime"
    ;;

  gog)
    echo -e "${GREEN}GOG-Installer erkannt – entpacke mit innoextract...${NC}"
    innoextract -s -d "$INSTALL_DIR" "$INSTALLER"
    ;;

  zip_plain)
    echo -e "${GREEN}Normales ZIP – entpacke mit unzip...${NC}"
    unzip -q -o "$INSTALLER" -d "$INSTALL_DIR"
    ;;

  exe)
    echo -e "${GREEN}EXE-Datei erkannt – kopiere in Install-Verzeichnis...${NC}"
    cp "$INSTALLER" "$INSTALL_DIR/"
    ;;

  *)
    echo -e "${RED}Fehler: Unbekannter installer_type: $INSTALLER_TYPE${NC}"
    exit 1
    ;;
esac


# ---------------------------------------------
# Postinstall Copy
# ---------------------------------------------

COPIES=$(jq -c '.copy_files[]?' "$GAME_CONFIG")
if [[ -n "$COPIES" ]]; then
  echo "→ Führe Copy-Anweisungen aus:"
  while IFS= read -r entry; do
    FROM=$(echo "$entry" | jq -r '.from')
    TO=$(echo "$entry" | jq -r '.to')
    echo "   - Kopiere $FROM → $TO"
    cp "${INSTALL_DIR%/}/$FROM" "${INSTALL_DIR%/}/$TO"
  done <<< "$COPIES"
fi

# ---------------------------------------------
# Autoexec bestimmen
# ---------------------------------------------
if [[ -f "${CONFIG_DIR%/}/autoexec.template" ]]; then
  echo "Verwende benutzerdefinierten autoexec.template"
  AUTOEXEC_BLOCK=$(< "${CONFIG_DIR%/}/autoexec.template")

  # Ersetze Platzhalter
  AUTOEXEC_BLOCK="${AUTOEXEC_BLOCK//\$(DOWNLOAD_DIR)/${DOWNLOAD_DIR%/}}"
  AUTOEXEC_BLOCK="${AUTOEXEC_BLOCK//\$(INSTALL_DIR)/${INSTALL_DIR%/}}"
  AUTOEXEC_BLOCK="${AUTOEXEC_BLOCK//\$(CONFIG_DIR)/${CONFIG_DIR%/}}"
  AUTOEXEC_BLOCK="${AUTOEXEC_BLOCK//\$(GAME_ID)/$GAME_ID}"

else
  echo "Kein benutzerdefiniertes Template – verwende Standard für $INSTALL_MODE"

  case "$INSTALL_MODE" in

    iso_runtime)
      AUTOEXEC_BLOCK=$(cat <<EOF
@echo off
imgmount d "$MOUNT_ISO" -t iso -fs iso
mount c ${INSTALL_DIR%/}
d:
$EXE_FILE
exit
EOF
)
      ;;

    iso_install)
      AUTOEXEC_BLOCK=$(cat <<EOF
@echo off
imgmount d "$MOUNT_ISO" -t iso -fs iso
mount c ${INSTALL_DIR%/}
d:
INSTALL.EXE
exit
EOF
)
      ;;

    iso_install_and_run)
      AUTOEXEC_BLOCK=$(cat <<EOF
@echo off
imgmount d "$MOUNT_ISO" -t iso -fs iso
mount c ${INSTALL_DIR%/}
c:
$EXE_FILE
exit
EOF
)
      ;;

    zip_plain | exe | gog | *)
      AUTOEXEC_BLOCK=$(cat <<EOF
@echo off
mount c ${INSTALL_DIR%/}
c:
$EXE_FILE
exit
EOF
)
      ;;

  esac
fi

# ---------------------------------------------
# dosbox.conf schreiben
# ---------------------------------------------
CONF_TARGET="${INSTALL_DIR%/}/${GAME_ID}.conf"
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
pcspeaker=$SPEAKER
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
cat > "${GAME_DIR%/}/start.sh" <<EOF
#!/bin/bash
dosbox -conf "$CONF_TARGET"
EOF
chmod +x "${GAME_DIR%/}/start.sh"

cat > "${GAME_DIR%/}/uninstall.sh" <<EOF
#!/bin/bash
echo "Entferne Spiel: $GAME_ID"
rm -rf "$GAME_DIR"
EOF
chmod +x "${GAME_DIR%/}/uninstall.sh"

# ---------------------------------------------
# Abschlussmeldung
# ---------------------------------------------
echo -e "${GREEN}Installation abgeschlossen. Starte das Spiel mit:${NC}"
echo "${GAME_DIR%/}/start.sh"

