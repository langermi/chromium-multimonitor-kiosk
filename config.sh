#!/usr/bin/env bash

# Basis-Pfade und Konstanten
export DISPLAY=:0
BASEDIR="${BASEDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)}"
LOGDIR="${LOGDIR:-$BASEDIR/logs}"
WORKSPACES="${WORKSPACES:-$BASEDIR/workspaces}"
URLS_INI="${URLS_INI:-$BASEDIR/urls.ini}"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
REPO_BASENAME="$(basename "$BASEDIR")"
LOG_TAG="${LOG_TAG:-${REPO_BASENAME:-kiosk}}"
LOGFILE="${LOGDIR}/${LOG_TAG}-start-$TIMESTAMP.log"
ERRORLOG="${LOGDIR}/${LOG_TAG}-error-$TIMESTAMP.log"
CHROMIUM_BIN="$(command -v chromium-browser || command -v chromium)"
CHROMIUM_CONFIG="$HOME/.config/chromium"
REFRESH_INACTIVITY_THRESHOLD=300
PAGE_REFRESH_INTERVAL=600

# Netzwerk-Warteverhalten
NETWORK_READY_TIMEOUT=120          # Maximale Wartezeit (Sekunden) bis eine Verbindung verfügbar sein muss
NETWORK_READY_CHECK_INTERVAL=5     # Abstand zwischen Verbindungsprüfungen (Sekunden)
# Optional: feste URL, die für den Verfügbarkeitscheck verwendet wird. Leer lassen = DEFAULT_URL bzw. erste Monitor-URL.
NETWORK_READY_CHECK_URL=""

# Powersettings
ENABLE_POWEROFF=false  # true = Poweroff aktiv, false = deaktiviert
POWEROFF_TIME="04:00"
ENABLE_RESTART=true   # true = Neustart aktiv, false = deaktiviert
RESTART_TIME="23:00"

# Log-Rotation und Watchdog
MAX_LOGS=7
LOG_DEBUG=0
CHECK_INTERVAL=10

# Soll das Skript Power-/Screensaver-Einstellungen automatisch setzen?
# true = anwenden, false = überspringen
APPLY_POWER_SETTINGS=true

# Logging extras
# LOG_FORMAT: "text" or "json"
LOG_FORMAT="text"
# send logs also to systemd/journald (true/false)
LOG_TO_JOURNAL=true
# Rotation nach Größe (Bytes) und Anzahl Backups
MAX_LOG_SIZE=$((10*1024*1024)) # 10 MB
LOG_MAX_BACKUPS=5
# Tag für Journal/syslog
LOG_TAG="kiosk"

# Default-URL, falls urls.ini fehlt oder keinen Eintrag liefert
DEFAULT_URL="https://example.com"
STRICT_URL_VALIDATION=true

# Chromium Start-Parameter
CHROMIUM_FLAGS=(
  "--no-first-run"
  "--disable-session-crashed-bubble"
  "--disable-infobars"
  "--disable-save-password-bubble"
  "--disable-gcm-registration"
  "--disable-breakpad"
  "--disable-background-networking"
  "--disable-client-side-phishing-detection"
  "--disable-component-update"
  "--disable-sync"
  "--disable-translate"
  "--disable-features=PushMessaging"
  "--no-default-browser-check"
  "--disable-popup-blocking"
  "--disable-logging"
)