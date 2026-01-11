# linux-gaming – reproducible retro & classic game installs

Dieses Repository stellt ein skriptbasiertes System zur reproduzierbaren Installation
klassischer DOS- und Windows-Spiele unter Linux bereit.

Ziel ist ausdrücklich NICHT ein universeller Launcher, sondern:
- deterministische, wiederholbare Installationen
- saubere Trennung von Input (Installer) und Output (Installationen)
- möglichst wenig implizite Magie

Unterstützt werden u.a.:
- DOS-Spiele via DOSBox
- Windows-Spiele via Wine (GOG, CD-ROM, Multi-Disc)

------------------------------------------------------------
Grundprinzip

Das Repo arbeitet strikt nach folgendem Modell:

1) _downloads/  = manueller Input
   - hier liegen originale Installer (ZIP, EXE, ISO)
   - diese Dateien werden nicht verändert

2) install/     = generierter Output
   - wird vollständig durch Skripte erzeugt
   - darf niemals manuell bearbeitet werden

3) config/<game_id>/game.json
   - beschreibt Engine, Installer, EXE-Pfade, Savegame-Orte

------------------------------------------------------------
Verzeichnislayout

$HOME/games/
├── _downloads/
│   └── <game_id>/
├── _savegames/
└── <game_id>/
    └── install/

------------------------------------------------------------
Abhängigkeiten

Wine, DOSBox und diverse Hilfstools werden zwingend benötigt.
wineboot ist TEIL von Wine und wird nicht separat installiert.

------------------------------------------------------------
Fedora (38+)

Wine (inkl. wineboot) – 64-bit UND 32-bit:

sudo dnf install -y \
  wine \
  wine.i686 \
  winetricks

Allgemeine Tools:

sudo dnf install -y \
  jq \
  unzip \
  rsync \
  p7zip p7zip-plugins \
  unshield \
  bchunk

Hinweis:
- fuseiso ist auf Fedora oft nicht verfügbar
- daher wird bchunk als Fallback verwendet
- bchunk benötigt zusätzlich p7zip

------------------------------------------------------------
Ubuntu / Debian (22.04+, Debian 12)

32-bit Architektur aktivieren (Pflicht):

sudo dpkg --add-architecture i386
sudo apt update

Wine (inkl. wineboot):

sudo apt install -y \
  wine \
  wine32 \
  wine64 \
  winetricks

Allgemeine Tools:

sudo apt install -y \
  jq \
  unzip \
  rsync \
  p7zip-full \
  unshield \
  fuseiso

Optionaler Fallback (statt fuseiso):

sudo apt install -y bchunk

------------------------------------------------------------
Verifikation

command -v wineboot
command -v winetricks
command -v jq
command -v unshield
command -v fuseiso || command -v bchunk

wine --version
wineboot -u

Erwartetes Verhalten:
- wineboot läuft fehlerfrei
- keine Warnungen über fehlendes wine32

------------------------------------------------------------
Installation eines Spiels

1) Installer in das Download-Verzeichnis legen:

$HOME/games/_downloads/<game_id>/

2) Installation starten:

./scripts/install.sh <game_id>

3) Spiel starten:

$HOME/games/<game_id>/start.sh
oder bei Wine-Disk-Media:
$HOME/games/<game_id>/install/run.sh

------------------------------------------------------------
Wichtige Regeln

- install/ niemals manuell bearbeiten
- Installer nicht vorab entpacken
- Dateinamen müssen exakt zu game.json passen
- bei Fehlern: uninstall.sh ausführen und neu installieren

------------------------------------------------------------
Typische Fehler

- Permission denied beim Start eines Skripts:
  -> Exec-Bit auf scripts/*.sh fehlt

  find scripts -type f -name '*.sh' -exec chmod +x {} +

- Wine startet, Spiele brechen aber ab:
  -> wine.i686 / wine32 fehlt

- Silent Hill 2: Videos fehlen oder binkw32.dll fehlt:
  -> scripts/tools/recover_bink_from_* verwenden

------------------------------------------------------------
Nicht-Ziele

- kein grafischer Launcher
- kein All-in-One-Frontend
- keine illegalen Inhalte

Das Repository setzt voraus, dass der Nutzer weiss,
woher er seine Installer legal bezieht.
