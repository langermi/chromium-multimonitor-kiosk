#!/usr/bin/env bash

# ==============================================================================
# Desktop-Umgebung & Pfade
# ==============================================================================
# Erzwingt die Nutzung des ersten lokalen X11-Displays (wichtig, wenn LXDE ohne DISPLAY gestartet wird).
export DISPLAY=:0
# Basisverzeichnis des Projekts, kann extern überschrieben werden.
BASEDIR="${BASEDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)}"
# Arbeitsverzeichnis für pro Monitor getrennte Chromium-Profile.
WORKSPACES="${WORKSPACES:-$BASEDIR/workspaces}"
# Pfad zur URL-Konfiguration im INI-Format.
URLS_INI="${URLS_INI:-$BASEDIR/urls.ini}"
# Basisverzeichnis der Chromium-Standardkonfiguration.
CHROMIUM_CONFIG="$HOME/.config/chromium"

# ==============================================================================
# Chromium-Laufzeit
# ==============================================================================
# Zu nutzender Chromium-Binary; versucht zuerst chromium-browser, fällt auf chromium zurück.
CHROMIUM_BIN="$(command -v chromium-browser || command -v chromium)"
# Liste zusätzlicher Flags, die Chromium im Kiosk-Betrieb stabiler machen.
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

# ==============================================================================
# Logging & Überwachung
# ==============================================================================
# Zeitstempel für Logdateien und Sessions.
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
# Abgeleiteter Name des Repositories/Skriptes für Log-Tags.
REPO_BASENAME="$(basename "$BASEDIR")"
# Ablageort für generierte Log-Dateien.
LOGDIR="${LOGDIR:-$BASEDIR/logs}"
# Vorbelegung für das Log-Tag (kann über Umgebungsvariable LOG_TAG überschrieben werden).
LOG_TAG="${LOG_TAG:-${REPO_BASENAME:-kiosk}}"
# Setzt das verwendete Log-Tag explizit auf "kiosk", damit alle Logsenkel einheitlich heißen.
LOG_TAG="kiosk"
# Pfad zur aktuellen Logdatei des Starts.
LOGFILE="${LOGDIR}/${LOG_TAG}-start-$TIMESTAMP.log"
# Pfad zur separaten Fehlerlogdatei.
ERRORLOG="${LOGDIR}/${LOG_TAG}-error-$TIMESTAMP.log"
# Ausgabeformat der Logdateien ("text" oder "json").
LOG_FORMAT="text"
# Parallel zum Dateilog auch ins systemd-Journal schreiben.
LOG_TO_JOURNAL=true
# Maximale Dateigröße für Logrotation (in Bytes).
MAX_LOG_SIZE=$((10*1024*1024)) # 10 MB
# Anzahl der vorzuhaltenden rotierten Logdateien.
LOG_MAX_BACKUPS=5
# 1 = Debug-Logging aktivieren, 0 = nur reguläre Logs.
LOG_DEBUG=0
# Prüfintervall (Sekunden) für den Watchdog-Loop.
CHECK_INTERVAL=10

# ==============================================================================
# Seiten-Refresh
# ==============================================================================
# Dauer (Sekunden) der benötigten Inaktivität vor einem automatischen Refresh.
REFRESH_INACTIVITY_THRESHOLD=300
# Intervall (Sekunden), in dem ein Refresh angestoßen wird.
PAGE_REFRESH_INTERVAL=600
# Globale Deaktivierung des automatischen Refresh-Mechanismus.
DISABLE_PAGE_REFRESH=true      # true = automatischer Seiten-Refresh komplett deaktivieren

# ==============================================================================
# Netzwerkbereitschaft
# ==============================================================================
# Maximale Zeit (Sekunden), die das Startskript auf eine Online-Verbindung wartet.
NETWORK_READY_TIMEOUT=120          # Maximale Wartezeit (Sekunden) bis eine Verbindung verfügbar sein muss
# Abstand zwischen einzelnen Netzwerk-Checks.
NETWORK_READY_CHECK_INTERVAL=5     # Abstand zwischen Verbindungsprüfungen (Sekunden)
# Optional: feste URL für die Konnektivitätsprüfung (fallback auf DEFAULT_URL bzw. Monitor-URL).
NETWORK_READY_CHECK_URL=""

# ==============================================================================
# Energieverwaltung & Sitzungssteuerung
# ==============================================================================
# Steuert, ob ein tägliches Herunterfahren angestoßen wird.
ENABLE_POWEROFF=false  # true = Poweroff aktiv, false = deaktiviert
# Uhrzeit für das automatisierte Herunterfahren (HH:MM, 24h-Format).
POWEROFF_TIME="04:00"
# Steuert, ob ein täglicher Neustart geplant wird.
ENABLE_RESTART=true   # true = Neustart aktiv, false = deaktiviert
# Uhrzeit für den geplanten Neustart (HH:MM, 24h-Format).
RESTART_TIME="23:00"
# Soll das Skript Power-/Screensaver-Einstellungen automatisch setzen? true = anwenden, false = überspringen.
APPLY_POWER_SETTINGS=true

# ==============================================================================
# URL-Defaults & Validierung
# ==============================================================================
# Default-URL, falls urls.ini fehlt oder keinen Eintrag liefert.
DEFAULT_URL="https://example.com"
# true = URLs müssen beim Start erreichbar sein, sonst Abbruch.
STRICT_URL_VALIDATION=true