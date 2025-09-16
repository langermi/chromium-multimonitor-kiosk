#!/usr/bin/env bash

# Konfiguration laden (einmalig am Skriptbeginn)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/config.sh"

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
      echo "Fehler: '$cmd' nicht gefunden. Bitte installieren." >&2
      missing=1
    fi
  done
  if [ "${XDG_SESSION_TYPE,,}" = "wayland" ]; then
    echo "Fehler: Wayland läuft. Bitte unter X11 starten." >&2
    missing=1
  fi
  if ! gsettings get org.gnome.shell enabled-extensions \
       | grep -qE "nooverview|no-overview"; then
    echo "Warnung: 'No overview at startup' nicht aktiviert oder Installiert." >&2
  fi
  [ "$missing" -ne 0 ] && exit 1

      if ! touch "$SCRIPT_DIR/test" 2>/dev/null; then
        echo "Fehler: Keine Schreibrechte in $LOGDIR"
        exit 1
      fi
    if [[ ! "$RESTART_TIME" =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
        echo "Ungültiges RESTART_TIME Format: $RESTART_TIME" >&2
        exit 1
    fi
  
}
check_prereqs

# Testmodus aktivieren
if [[ "$1" == "--test" ]]; then
  TESTMODE=1
  echo "Testmodus aktiviert – Chromium start Übersprungen"
fi

# Logging-Funktionen
log()       { echo "[$(date '+%F %T')] $*"    >> "$LOGFILE"; }
log_error() { echo "[$(date '+%F %T')] [ERROR] $*" >> "$ERRORLOG"; }

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

# Funktion für Systemneustart
restart_system() {
  log "Automatischer Neustart um $RESTART_TIME ausgelöst"
  sudo shutdown -r now
}

# Bildschirmschoner und Notifications deaktivieren
xset s off            # Bildschirmschoner ausschalten
xset -dpms            # Energiesparfunktionen deaktivieren
xset s noblank        # Bildschirm nicht ausblenden
gsettings set org.gnome.desktop.session idle-delay 0 2>>"$ERRORLOG"
gsettings set org.gnome.desktop.screensaver idle-activation-enabled false 2>>"$ERRORLOG"
gsettings set org.gnome.desktop.screensaver lock-enabled false 2>>"$ERRORLOG"
gsettings set org.gnome.desktop.notifications show-banners false 2>>"$ERRORLOG"

# Clean-exit & Übersetzer in Chromium prefs abschalten
PREFS="$CHROMIUM_CONFIG/Default/Preferences"
if [ -f "$PREFS" ]; then
  sed -i 's/"exited_cleanly":false/"exited_cleanly":true/' "$PREFS" 2>>"$ERRORLOG"
  sed -i 's/"exit_type":"Crashed"/"exit_type":"Normal"/'  "$PREFS" 2>>"$ERRORLOG"
  sed -i 's/"translate":{"enabled":true}/"translate":{"enabled":false}/' "$PREFS" 2>>"$ERRORLOG"
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
    cp -r "$CHROMIUM_CONFIG/." "$ws/" 2>>"$ERRORLOG" \
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
  if [ "${TESTMODE:-0}" -eq 1 ]; then
    log "Testmodus – Start übersprungen"
    MON_PID["$m"]=0
    return
  fi

  "$CHROMIUM_BIN" \
    "${CHROMIUM_FLAGS[@]}" \
    --user-data-dir="$ws" \
    --app="$url" \
    >>"$LOGFILE" 2> >(
      grep -v -E 'blink\.mojom\.WidgetHost|registration_request\.cc' \
      >>"$ERRORLOG"
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
while true; do
  sleep "$CHECK_INTERVAL"

  # Periodischer Seiten-Refresh bei Inaktivität
if [ "${PAGE_REFRESH_INTERVAL:-0}" -gt 0 ]; then
    now=$(date +%s)
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
        last_refresh_time=$now # Zeit nur nach erfolgreichem Refresh zurücksetzen
      else
        log "Refresh übersprungen. System ist aktiv (Inaktivität: $idle_seconds s)."
      fi
    fi
  fi  # Zeit prüfen und ggf. Neustart auslösen
  current_time=$(date '+%H:%M')
  if [ "${ENABLE_RESTART:-true}" = "true" ] && [ "$current_time" = "$RESTART_TIME" ]; then
    log "Initiire restart $current_time"
    restart_system 2>>"$ERRORLOG" || log_error "Neustart fehlgeschlagen"
    exit 0
  fi

  for m in "${MON_LIST[@]}"; do
    pid=${MON_PID[$m]}
    if ! kill -0 "$pid" &>/dev/null; then
      RESTART_COUNT["$m"]=$((RESTART_COUNT[$m]+1))
      log_error "Chromium auf $m (PID $pid) beendet. Neustart #${RESTART_COUNT[$m]}"
      ws=${WS_DIR[$m]}
      log "Reinitialisiere Workspace $ws"
      rm -rf "$ws" && mkdir -p "$ws"
      if [ -d "$CHROMIUM_CONFIG" ]; then
        cp -r "$CHROMIUM_CONFIG/." "$ws/" 2>>"$ERRORLOG" \
          || log_error "Kopie nach $ws fehlgeschlagen"
      fi
      start_chromium "$m"
    fi
  done
done
