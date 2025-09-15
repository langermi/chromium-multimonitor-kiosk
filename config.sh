#!/usr/bin/env bash

# Basis-Pfade und Konstanten
export DISPLAY=:0
BASEDIR="$HOME/kiosk-system"
LOGDIR="$BASEDIR/logs"
WORKSPACES="$BASEDIR/workspaces"
URLS_INI="$BASEDIR/urls.ini"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
LOGFILE="$LOGDIR/kiosk-start-$TIMESTAMP.log"
ERRORLOG="$LOGDIR/kiosk-error-$TIMESTAMP.log"
CHROMIUM_BIN="$(command -v chromium-browser || command -v chromium)"
CHROMIUM_CONFIG="$HOME/.config/chromium"

# Log-Rotation und Watchdog
MAX_LOGS=7
CHECK_INTERVAL=10

# Default-URL, falls urls.ini fehlt oder keinen Eintrag liefert
DEFAULT_URL="https://example.com"