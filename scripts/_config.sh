#!/bin/bash

# Can be changed according to user preferences
INSTALL_PATH="$HOME/games"
DOWNLOAD_PATH="$HOME/games/_downloads"
SAVESLOT_PATH="$HOME/games/_savegames"

# This should not change
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="$SCRIPT_DIR/../config"
