#!/usr/bin/env bash

# Konfiguration laden (einmalig am Skriptbeginn)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/config.sh"

# Sichere IFS-Initialisierung
IFS=$'\n\t'

# Einfacher Cleanup-Handler: sauber beenden bei Signalen (SIGINT,SIGTERM,SIGHUP)
# Verwende keine log_* Funktionen hier, da sie später definiert werden.
cleanup() {
  # Best-effort: Chromium-Prozesse beenden
  pkill -x chromium chromium-browser 2>/dev/null || true
  pkill -f "chromium" 2>/dev/null || true
  # Warte kurz, damit Kinderprozesse terminiert werden
  sleep 1
}

trap 'cleanup' INT TERM HUP
trap 'cleanup' EXIT

# Einheitliches Logging: tägliches Logfile, Debug-Flag und STDERR-Redirect
mkdir -p "$LOGDIR"
# tägliches Logfile-Naming (kiosk-YYYY-MM-DD.log)
LOGFILE="${LOGDIR}/kiosk-$(date '+%F').log"
# Debug per ENV aktivierbar: setze LOG_DEBUG=1 um Debug-Logging zu aktivieren
LOG_DEBUG="${LOG_DEBUG:-0}"
# STDERR umleiten: Jede Zeile wird getaggt und in das tägliche Log geschrieben
# Speichere das originale STDERR (Konsole) auf FD 3, damit wir die Fehlermeldungen
# zusätzlich zur Log-Datei wieder an die Konsole ausgeben können.
exec 3>&2
exec 2> >(
  while IFS= read -r line; do
    ts="$(date '+%F %T')"
    if [ "${LOG_FORMAT:-text}" = "json" ]; then
      # Anführungszeichen und Backslashes für JSON escapen
      esc=$(printf '%s' "$line" | sed -e 's/\\/\\\\/g' -e 's/"/\\\"/g')
      printf '{"ts":"%s","level":"ERROR","msg":"%s"}\n' "$ts" "$esc" >>"$LOGFILE"
    else
      printf '%s [ERROR] %s\n' "$ts" "$line" >>"$LOGFILE"
    fi
    # Gebe die Original-Fehlermeldung zusätzlich an den gespeicherten STDERR (FD 3)
    printf '%s\n' "$line" >&3
    if [ "${LOG_TO_JOURNAL:-false}" = true ]; then
      printf '%s\n' "$line" | logger -t "${LOG_TAG:-kiosk}" -p user.err
    fi
  done
)

# Alte Chromium-Prozesse beenden
pkill -x chromium chromium-browser 2>/dev/null || true
sleep 1

# Prüfe Bash-Umgebung
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Dieses Skript benötigt bash. (bash startkiosk.sh)" >&2
  exit 1
fi

# Abhängigkeiten prüfen
check_prereqs() {
  local missing=0
  for cmd in xdotool xrandr gsettings chromium curl xprintidle; do
    if ! command -v "$cmd" &>/dev/null; then
      log_error "Fehler: '$cmd' nicht gefunden. Bitte installieren."
      missing=1
    fi
  done
  if [ "${XDG_SESSION_TYPE,,}" = "wayland" ]; then
    log_error "Fehler: Wayland läuft. Bitte unter X11 starten."
    missing=1
  fi
  if ! gsettings get org.gnome.shell enabled-extensions \
       | grep -qE "nooverview|no-overview"; then
    log_warn "GNOME Extension 'No overview at startup' nicht aktiviert oder installiert."
  fi
  if [ "$missing" -ne 0 ]; then
    log_error "Abbruch aufgrund fehlender Abhängigkeiten."
    exit 1
  fi


  if [[ ! "$RESTART_TIME" =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
    log_error "Ungültiges RESTART_TIME Format: $RESTART_TIME"
    exit 1
  fi
  if [[ ! "$POWEROFF_TIME" =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
    log_error "Ungültiges POWEROFF_TIME Format: $POWEROFF_TIME"
    exit 1
  fi

  # Prüfe Rechte für Neustart / Poweroff (nur notwendig, wenn aktiviert)
  if [ "${ENABLE_RESTART:-true}" = "true" ]; then
    if ! can_execute_reboot_or_poweroff; then
      log_error "Neustart ist aktiviert (ENABLE_RESTART=true), aber der Benutzer hat keine ausreichenden Rechte für 'reboot' oder 'systemctl reboot'."
      exit 1
    fi
  fi
  if [ "${ENABLE_POWEROFF:-true}" = "true" ]; then
    if ! can_execute_reboot_or_poweroff; then
      log_error "Poweroff ist aktiviert (ENABLE_POWEROFF=true), aber der Benutzer hat keine ausreichenden Rechte für 'poweroff' oder 'systemctl poweroff'."
      exit 1
    fi
  fi
}

# Logging-Funktionen (ein Logfile, mit Level-Tags)
# ANSI-Farbcodes für die Konsole
_COLOR_RESET="\e[0m"
_COLOR_INFO="\e[32m"   # grün
_COLOR_WARN="\e[33m"   # gelb
_COLOR_ERROR="\e[31m"  # rot

# Hilfsfunktionen
json_escape() {
  # Backslashes und doppelte Anführungszeichen für JSON-Ausgabe escapen
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\\"/g'
}

rotate_by_size() {
  local file="$1"
  local max_size=${MAX_LOG_SIZE:-$((10*1024*1024))}
  local backups=${LOG_MAX_BACKUPS:-5}
  [ -f "$file" ] || return 0
  local size
  if size=$(stat -c%s "$file" 2>/dev/null); then :; else size=$(stat -f%z "$file" 2>/dev/null); fi
  [ -n "$size" ] || return 0
  if [ "$size" -le "$max_size" ]; then return 0; fi
  for ((i=backups-1;i>=1;i--)); do
    if [ -f "${file}.$i" ]; then mv "${file}.$i" "${file}.$((i+1))"; fi
  done
  mv "$file" "${file}.1"
  if [ -f "${file}.$((backups+1))" ]; then rm -f "${file}.$((backups+1))"; fi
}

# Prüfe, ob der aktuelle Benutzer Neustart/Poweroff ohne interaktives Passwort ausführen kann
can_execute_reboot_or_poweroff() {
  # Prüfe, ob der Benutzer Neustart/Poweroff durchführen kann.
  # `systemctl --user` ermöglicht normalerweise kein System-Reboot

  # Teste mit sudo -n (non-interactive), ob sudo ohne Passwort möglich ist
  if sudo -n true 2>/dev/null; then
    log_debug "can_execute_reboot_or_poweroff: sudo -n true -> allowed"
    return 0
  fi

  # Prüfe explizit, ob spezielle Befehle per sudo ohne Passwort ausführbar sind
  if sudo -n systemctl reboot &>/dev/null; then
    log_debug "can_execute_reboot_or_poweroff: sudo -n systemctl reboot -> allowed"
    return 0
  fi
  if sudo -n /sbin/reboot &>/dev/null; then
    log_debug "can_execute_reboot_or_poweroff: sudo -n /sbin/reboot -> allowed"
    return 0
  fi

  # Falls polkit die direkte Ausführung von `systemctl reboot` ohne sudo erlaubt,
  # kann ein Aufruf ohne Passwort erfolgreich sein. Wir testen eine harmlose
  # systemctl-Abfrage auf dieselbe Weise — falls sie erfolgreich ist, zählen
  # wir das nicht automatisch als Berechtigung zum Reboot (safety-first).

  return 1
}

log() {
  local msg="[$(date '+%F %T')] [INFO] $*"
  echo -e "${_COLOR_INFO}${msg}${_COLOR_RESET}" >&1
  rotate_by_size "$LOGFILE"
  local ts="$(date '+%F %T')"
  local text="$*"
  local esc
  esc=$(json_escape "$text")
  if [ "${LOG_FORMAT:-text}" = "json" ]; then
    printf '{"ts":"%s","level":"INFO","msg":"%s"}\n' "$ts" "$esc" >>"$LOGFILE"
  else
    printf '%s [INFO] %s\n' "$ts" "$text" >>"$LOGFILE"
  fi
  if [ "${LOG_TO_JOURNAL:-false}" = true ]; then
    printf '%s\n' "[$ts] [INFO] $text" | logger -t "${LOG_TAG:-kiosk}" -p user.info
  fi
}

log_warn() {
  local msg="[$(date '+%F %T')] [WARN] $*"
  echo -e "${_COLOR_WARN}${msg}${_COLOR_RESET}" >&1
  rotate_by_size "$LOGFILE"
  local ts="$(date '+%F %T')"
  local text="$*"
  local esc
  esc=$(json_escape "$text")
  if [ "${LOG_FORMAT:-text}" = "json" ]; then
    printf '{"ts":"%s","level":"WARN","msg":"%s"}\n' "$ts" "$esc" >>"$LOGFILE"
  else
    printf '%s [WARN] %s\n' "$ts" "$text" >>"$LOGFILE"
  fi
  if [ "${LOG_TO_JOURNAL:-false}" = true ]; then
    printf '%s\n' "[$ts] [WARN] $text" | logger -t "${LOG_TAG:-kiosk}" -p user.warn
  fi
}

log_error() {
  local msg="[$(date '+%F %T')] [ERROR] $*"
  echo -e "${_COLOR_ERROR}${msg}${_COLOR_RESET}" >&2
  rotate_by_size "$LOGFILE"
  local ts="$(date '+%F %T')"
  local text="$*"
  local esc
  esc=$(json_escape "$text")
  if [ "${LOG_FORMAT:-text}" = "json" ]; then
    printf '{"ts":"%s","level":"ERROR","msg":"%s"}\n' "$ts" "$esc" >>"$LOGFILE"
  else
    printf '%s [ERROR] %s\n' "$ts" "$text" >>"$LOGFILE"
  fi
  if [ "${LOG_TO_JOURNAL:-false}" = true ]; then
    printf '%s\n' "[$ts] [ERROR] $text" | logger -t "${LOG_TAG:-kiosk}" -p user.err
  fi
}

# Debug-Logging (nur wenn LOG_DEBUG=1)
log_debug() {
  [ "$LOG_DEBUG" -eq 1 ] || return 0
  local msg="[$(date '+%F %T')] [DEBUG] $*"
  echo -e "\e[36m${msg}${_COLOR_RESET}" >&1
  rotate_by_size "$LOGFILE"
  local ts="$(date '+%F %T')"
  local text="$*"
  local esc
  esc=$(json_escape "$text")
  if [ "${LOG_FORMAT:-text}" = "json" ]; then
    printf '{"ts":"%s","level":"DEBUG","msg":"%s"}\n' "$ts" "$esc" >>"$LOGFILE"
  else
    printf '%s [DEBUG] %s\n' "$ts" "$text" >>"$LOGFILE"
  fi
  if [ "${LOG_TO_JOURNAL:-false}" = true ]; then
    printf '%s\n' "[$ts] [DEBUG] $text" | logger -t "${LOG_TAG:-kiosk}" -p user.debug
  fi
}

# Drucke eine kurze, lesbare Zusammenfassung wichtiger Konfigurationsvariablen
print_config_summary() {
  log "Konfiguration (Kurzüberblick):"
  log "  BASEDIR=$BASEDIR"
  log "  LOGDIR=$LOGDIR"
  log "  WORKSPACES=$WORKSPACES"
  log "  URLS_INI=$URLS_INI"
  log "  DEFAULT_URL=${DEFAULT_URL:-(unset)}"
  log "  CHROMIUM_BIN=${CHROMIUM_BIN:-(not found)}"
  log "  CHROMIUM_CONFIG=${CHROMIUM_CONFIG:-(unset)}"
  log "  CHECK_INTERVAL=${CHECK_INTERVAL:-(unset)}s"
  log "  PAGE_REFRESH_INTERVAL=${PAGE_REFRESH_INTERVAL:-(unset)}s"
  log "  REFRESH_INACTIVITY_THRESHOLD=${REFRESH_INACTIVITY_THRESHOLD:-(unset)}s"
  log "  APPLY_POWER_SETTINGS=${APPLY_POWER_SETTINGS:-true}"
  log "  ENABLE_RESTART=${ENABLE_RESTART:-true} RESTART_TIME=${RESTART_TIME:-(unset)}"
  log "  ENABLE_POWEROFF=${ENABLE_POWEROFF:-false} POWEROFF_TIME=${POWEROFF_TIME:-(unset)}"
  log "  LOG_FORMAT=${LOG_FORMAT:-text} LOG_TO_JOURNAL=${LOG_TO_JOURNAL:-false} LOG_DEBUG=${LOG_DEBUG:-0}"
  log "  MAX_LOGS=${MAX_LOGS:-7} MAX_LOG_SIZE=${MAX_LOG_SIZE:-0} LOG_MAX_BACKUPS=${LOG_MAX_BACKUPS:-5}"
  # Verbale Debug-Ausgabe der Chromium-Flags (nicht in main-log, sondern nur im Debug-Log)
  log_debug "CHROMIUM_FLAGS=${CHROMIUM_FLAGS[*]:-(none)}"
}

# URLs aus der Konfiguration validieren
validate_urls() {
    local url_valid=true
    local url
    for url in "$@"; do
        # URL testen
        if ! curl --output /dev/null --silent --head --fail "$url"; then
            log_error "URL nicht erreichbar: $url"
            url_valid=false
        else
            log "URL validiert: $url"
        fi
    done
    
    if [ "$url_valid" = false ]; then
        if [ "$STRICT_URL_VALIDATION" = true ]; then
            log_error "Strikte URL-Validierung fehlgeschlagen - Abbruch"
            exit 1
        else
            log_error "URL-Validierung fehlgeschlagen - Fortfahren mit Warnungen"
        fi
    fi
}


# Log-Rotation durchführen
rotate_logs() {
  mkdir -p "$LOGDIR"
  find "$LOGDIR" -type f -name "*.log" ! -name "*.gz" -mtime +1 -exec gzip {} \;
  ls -tp "$LOGDIR"/*.log.gz 2>/dev/null \
    | tail -n +$((MAX_LOGS+1)) \
    | xargs -r rm --
}
rotate_logs
log "=== Kiosk-Skript gestartet ==="
log_debug "CONFIG: CHECK_INTERVAL=$CHECK_INTERVAL PAGE_REFRESH_INTERVAL=$PAGE_REFRESH_INTERVAL RESTART_TIME=$RESTART_TIME POWEROFF_TIME=$POWEROFF_TIME LOG_DEBUG=$LOG_DEBUG"
log "Logging in $LOGFILE"

# Schreibe eine Kurz-Zusammenfassung der wichtigsten Konfigurationswerte ins Log
print_config_summary

# Prüfe Abhängigkeiten und Rechte jetzt, damit Meldungen ins Log gehen
check_prereqs

# Funktion für Systemneustart
restart_system() {
  log "Automatischer Neustart um $RESTART_TIME ausgelöst"
  sudo systemctl reboot
}

poweroff_system() {
  log "Automatischer Poweroff um $POWEROFF_TIME ausgelöst"
  sudo systemctl poweroff
}

# Bildschirmschoner und Notifications deaktivieren (mit Verifikation)
if [ "${APPLY_POWER_SETTINGS:-true}" = true ]; then
  log "Deaktiviere Bildschirmschoner und Notifications"

  # xset-Einstellungen (falls verfügbar)
  if command -v xset &>/dev/null; then
  if xset s off; then
    log "xset: Bildschirmschoner deaktiviert (s off)"
  else
    log_warn "xset: Konnte Bildschirmschoner (s off) nicht deaktivieren"
  fi

  if xset -dpms; then
    log "xset: DPMS deaktiviert"
  else
    log_warn "xset: Konnte DPMS nicht deaktivieren"
  fi

  if xset s noblank; then
    log "xset: Bildschirm-Blanking deaktiviert"
  else
    log_warn "xset: Konnte Bildschirm-Blanking nicht deaktivieren"
  fi
  else
    log_warn "xset nicht gefunden; überspringe lokale X-Settings"
  fi

# Hilfsfunktion: gsettings setzen und verifizieren
set_and_verify_gsetting() {
  local schema="$1" key="$2" value="$3"
  if ! command -v gsettings &>/dev/null; then
    log_warn "gsettings nicht verfügbar; $schema $key nicht gesetzt"
    return 1
  fi
  if gsettings set "$schema" "$key" $value 2>>"$LOGFILE"; then
    actual=$(gsettings get "$schema" "$key" 2>>"$LOGFILE" || true)
    # Normalisiere mögliche GVariant-Typpräfixe wie: uint32 0, b true, 'string'
    # Entferne GVariant-Typen (alles bis zum ersten Leerzeichen, falls es ein Typ gibt)
    # sowie umschließende Anführungszeichen und führende/folgenden Whitespace.
    # Vergleiche in Kleinbuchstaben für Robustheit.
    normalize() {
      local v="$1"
      # Entferne GVariant type prefix (e.g. "uint32 0" -> "0", "b true" -> "true")
      v=$(echo "$v" | sed -E 's/^[[:alnum:]_]+[[:space:]]+//')
      # Entferne umschließende einfache oder doppelte Anführungszeichen
      v=$(echo "$v" | sed -e "s/^['\"]//" -e "s/['\"]$//")
      # Trim
      v=$(echo "$v" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
      # Lowercase
      echo "$v" | tr '[:upper:]' '[:lower:]'
    }

    actual_s=$(normalize "$actual")
    expected_s=$(normalize "$value")
    if [ "$actual_s" = "$expected_s" ]; then
      log "gsettings: $schema $key auf $value gesetzt (verifiziert)"
      return 0
    else
      log_warn "gsettings: $schema $key gesetzt, Bestätigung weicht ab (erwartet: $expected_s, erhalten: $actual_s)"
      return 2
    fi
  else
    log_error "gsettings: konnte $schema $key nicht auf $value setzen"
    return 1
  fi
}

  # Gnome/GSettings Einstellungen setzen und prüfen
  set_and_verify_gsetting org.gnome.desktop.session idle-delay 0
  set_and_verify_gsetting org.gnome.desktop.screensaver idle-activation-enabled false
  set_and_verify_gsetting org.gnome.desktop.screensaver lock-enabled false
  set_and_verify_gsetting org.gnome.desktop.notifications show-banners false
  set_and_verify_gsetting org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type "'nothing'"
  set_and_verify_gsetting org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type "'nothing'"
else
  log_warn "APPLY_POWER_SETTINGS ist deaktiviert; Power-/Screensaver-Einstellungen werden übersprungen"
fi
# Clean-exit in Chromium prefs abschalten
PREFS="$CHROMIUM_CONFIG/Default/Preferences"
  if [ -f "$PREFS" ]; then
  sed -i 's/"exited_cleanly":false/"exited_cleanly":true/' "$PREFS" 2>>"$LOGFILE"
  sed -i 's/"exit_type":"Crashed"/"exit_type":"Normal"/'  "$PREFS" 2>>"$LOGFILE"
fi

# URLs einlesen
declare -A URL_BY_NAME URL_BY_INDEX REFRESH_BY_NAME REFRESH_BY_INDEX
declare -a ALL_URLS
DEFAULT_REFRESH_ENABLED=true

if [ -f "$URLS_INI" ]; then
  log "Lade URLs aus $URLS_INI"
  while IFS='=' read -r key val; do
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    key="${key//[[:space:]]/}"; key="${key,,}"
    val="${val##*( )}"; val="${val%%*( )}"

    url_part="${val%%,*}"
    option_part="${val#*,}"

    ALL_URLS+=("$url_part")
    refresh_enabled=true
    if [[ "$option_part" == "norefresh" ]]; then
      refresh_enabled=false
    fi

    if [ "$key" = "default" ]; then
      DEFAULT_URL="$url_part"
      DEFAULT_REFRESH_ENABLED=$refresh_enabled
    elif [[ "$key" =~ ^index([0-9]+)$ ]]; then
      URL_BY_INDEX["${BASH_REMATCH[1]}"]=$url_part
      REFRESH_BY_INDEX["${BASH_REMATCH[1]}"]=$refresh_enabled
    else
      URL_BY_NAME["$key"]=$url_part
      REFRESH_BY_NAME["$key"]=$refresh_enabled
    fi
  done <"$URLS_INI"
  validate_urls "${ALL_URLS[@]}"
else
  log "WARN: urls.ini nicht gefunden. Nutze $DEFAULT_URL"
  validate_urls "$DEFAULT_URL"
fi

# Monitore auslesen
declare -a MON_LIST
declare -A MON_W MON_H MON_X MON_Y MON_ROT
while read -r line; do
  [[ "$line" != *" connected "* ]] && continue
  name=$(awk '{print $1}' <<<"$line")
  modepos=$(grep -oE '[0-9]+x[0-9]+\+[0-9]+\+[0-9]+' <<<"$line")
  rot=$(grep -oE '\b(normal|left|right|inverted)\b' <<<"$line")
  if [ -n "$modepos" ]; then
    IFS='x+' read -r w h x y <<<"$modepos"
    MON_LIST+=("$name")
    MON_W["$name"]=$w
    MON_H["$name"]=$h
    MON_X["$name"]=$x
    MON_Y["$name"]=$y
    MON_ROT["$name"]=$rot
  fi
done < <(xrandr --query)

if [ "${#MON_LIST[@]}" -eq 0 ]; then
  log_error "Keine Monitore erkannt. Abbruch."
  exit 1
fi

for m in "${MON_LIST[@]}"; do
  log "Monitor $m: ${MON_W[$m]}x${MON_H[$m]} @ +${MON_X[$m]},${MON_Y[$m]} rot=${MON_ROT[$m]}"
done

# Workspaces erstellen und URLs zuweisen
declare -A MON_URL WS_DIR MON_PID RESTART_COUNT MON_REFRESH_ENABLED
for idx in "${!MON_LIST[@]}"; do
  m="${MON_LIST[$idx]}"
  key="${m,,}"
  
  # URL und Refresh-Einstellung ermitteln
  url="${URL_BY_NAME[$key]:-${URL_BY_INDEX[$idx]:-$DEFAULT_URL}}"
  refresh_setting="${REFRESH_BY_NAME[$key]:-${REFRESH_BY_INDEX[$idx]:-$DEFAULT_REFRESH_ENABLED}}"

  ws="$WORKSPACES/$key"
  MON_URL["$m"]=$url
  MON_REFRESH_ENABLED["$m"]=$refresh_setting
  WS_DIR["$m"]=$ws
  mkdir -p "$ws"
  if [ -d "$CHROMIUM_CONFIG" ]; then
    cp -r "$CHROMIUM_CONFIG/." "$ws/" 2>>"$LOGFILE" \
      || log_error "Kopie nach $ws fehlgeschlagen"
  fi
  RESTART_COUNT["$m"]=0
  log "Setup: $m → $url (Workspace: $ws, Refresh: ${MON_REFRESH_ENABLED[$m]})"
done

# Funktion zum Starten von Chromium
start_chromium() {
  local m=$1 url=${MON_URL[$m]}
  local x=${MON_X[$m]} y=${MON_Y[$m]}
  local w=${MON_W[$m]} h=${MON_H[$m]}
  local ws=${WS_DIR[$m]}

  log "Starte Chromium auf $m → $url"

  "$CHROMIUM_BIN" \
    "${CHROMIUM_FLAGS[@]}" \
    --user-data-dir="$ws" \
    --app="$url" \
    >>"$LOGFILE" 2> >(
      grep -v -E 'blink\.mojom\.WidgetHost|registration_request\.cc' \
      >>"$LOGFILE"
    ) &

  MON_PID["$m"]=$!
  log "PID=${MON_PID[$m]}"

  # Warte bis zu 10 Sekunden auf das Fenster
  local win_id
  for ((i=0; i<10; i++)); do
    win_id=$(xdotool search --sync --onlyvisible --pid "${MON_PID[$m]}" | head -n1)
    [ -n "$win_id" ] && break
    sleep 1
  done

  if [ -n "$win_id" ]; then
    xdotool windowmove  "$win_id" "$x" "$y"
    xdotool windowsize "$win_id" "$w" "$h"
    xdotool windowactivate "$win_id"
    xdotool key --window "$win_id" F11
    log "Fenster $win_id auf $m in Fullscreen"
  else
    log_error "Fenster für $m (PID ${MON_PID[$m]}) nicht gefunden"
  fi
}

# Chromium initial starten
for m in "${MON_LIST[@]}"; do
  start_chromium "$m"
  sleep 1
done

# Watchdog-Schleife
last_refresh_time=$(date +%s)
# letzter timestamp wird verwendet somit werden auch verpasste Events erkannt
prev_check_time=$(date +%s)
while true; do
  sleep "$CHECK_INTERVAL"

  # Aktuelle Zeit einmal ermitteln (für Refresh + Zeit-Trigger)
  now=$(date +%s)
  # Sekunden seit Mitternacht (für robuste Zeitvergleichs-Logik)
  prev_mod=$(( prev_check_time % 86400 ))
  now_mod=$(( now % 86400 ))
  if (( now - last_refresh_time > PAGE_REFRESH_INTERVAL )); then
      # Inaktivitätsdauer auslesen (in Sekunden) mit xprintidle
      if command -v xprintidle &>/dev/null; then
        idle_time_ms=$(xprintidle)
      fi
      idle_seconds=$((idle_time_ms / 1000))

      if [ "$idle_seconds" -ge "${REFRESH_INACTIVITY_THRESHOLD:-300}" ]; then
        log "Inaktivität ($idle_seconds s) überschreitet Schwellenwert. Führe Seiten-Refresh aus."
        for m in "${MON_LIST[@]}"; do
          if [ "${MON_REFRESH_ENABLED[$m]}" = true ]; then
            pid=${MON_PID[$m]}
            if kill -0 "$pid" &>/dev/null; then
              win_id=$(xdotool search --sync --onlyvisible --pid "$pid" | head -n1)
              if [ -n "$win_id" ]; then
                xdotool key --window "$win_id" F5
                log "Refresh für Fenster $win_id auf Monitor $m gesendet."
              fi
            fi
          else
            log "Refresh für Monitor $m übersprungen (deaktiviert)."
          fi
        done
  # Aligniere last_refresh_time so, dass die nächsten Refreshes wieder
  # im korrekten Rhythmus erfolgen, auch wenn mehrere Intervalle verpasst wurden.
  elapsed=$(( now - last_refresh_time ))
  # Restzeit bis zum nächsten vollen Intervall
  remainder=$(( elapsed % PAGE_REFRESH_INTERVAL ))
  # Setze last_refresh_time so, dass der nächste erwartete = jetzt + (PAGE_REFRESH_INTERVAL - verbleibende Zeit)
  last_refresh_time=$(( now - remainder ))
      else
        log "Refresh übersprungen. System ist aktiv (Inaktivität: $idle_seconds s)."
      fi
  fi  # Zeit prüfen und ggf. Neustart auslösen
  # Prüfe, ob die konfigurierten Zeiten (Restart / Poweroff) zwischen prev_check_time und jetzt lagen.
  # Vergleiche auf Sekunden seit Mitternacht das vermeidet verpasste Trigger bei großen CHECK_INTERVAL.
  if [ "${ENABLE_RESTART:-true}" = "true" ]; then
    target_restart_mod=$(awk -F: '{print ($1*3600)+($2*60)}' <<<"$RESTART_TIME")
    # Normalfall (kein Tageswechsel zwischen den Zeitpunkten)
    if [ "$now_mod" -ge "$prev_mod" ]; then
      if [ "$target_restart_mod" -gt "$prev_mod" ] && [ "$target_restart_mod" -le "$now_mod" ]; then
  restart_system 2>>"$LOGFILE" || log_error "Neustart fehlgeschlagen"
        exit 0
      fi
    else
      # Tageswechsel (z.B. prev 23:59, now 00:01)
      if [ "$target_restart_mod" -gt "$prev_mod" ] || [ "$target_restart_mod" -le "$now_mod" ]; then
  restart_system 2>>"$LOGFILE" || log_error "Neustart fehlgeschlagen"
        exit 0
      fi
    fi
  fi

  if [ "${ENABLE_POWEROFF:-true}" = "true" ]; then
    target_power_mod=$(awk -F: '{print ($1*3600)+($2*60)}' <<<"$POWEROFF_TIME")
    if [ "$now_mod" -ge "$prev_mod" ]; then
      if [ "$target_power_mod" -gt "$prev_mod" ] && [ "$target_power_mod" -le "$now_mod" ]; then
  poweroff_system 2>>"$LOGFILE" || log_error "Poweroff fehlgeschlagen"
        exit 0
      fi
    else
      if [ "$target_power_mod" -gt "$prev_mod" ] || [ "$target_power_mod" -le "$now_mod" ]; then
  poweroff_system 2>>"$LOGFILE" || log_error "Poweroff fehlgeschlagen"
        exit 0
      fi
    fi
  fi

  # Aktualisiere prev_check_time für die nächste Iteration
  prev_check_time=$now


  for m in "${MON_LIST[@]}"; do
    pid=${MON_PID[$m]}
    if ! kill -0 "$pid" &>/dev/null; then
      RESTART_COUNT["$m"]=$((RESTART_COUNT[$m]+1))
      log_error "Chromium auf $m (PID $pid) beendet. Neustart #${RESTART_COUNT[$m]}"
      ws=${WS_DIR[$m]}
      log "Reinitialisiere Workspace $ws"
      rm -rf "$ws" && mkdir -p "$ws"
      if [ -d "$CHROMIUM_CONFIG" ]; then
        cp -r "$CHROMIUM_CONFIG/." "$ws/" 2>>"$LOGFILE" \
          || log_error "Kopie nach $ws fehlgeschlagen"
      fi
      start_chromium "$m"
    fi
  done
done
