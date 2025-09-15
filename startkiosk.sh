#!/usr/bin/env bash

# Konfiguration laden (einmalig am Skriptbeginn)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/config.sh"

# Alte Chromium-Prozesse beenden
pkill -x chromium chromium-browser 2>/dev/null || true
sleep 1

# Prüfe Bash-Umgebung
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Dieses Skript benötigt bash." >&2
  exit 1
fi

# Abhängigkeiten prüfen
check_prereqs() {
  local missing=0
  for cmd in xdotool xrandr gsettings chromium; do
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
    echo "Warnung: 'No overview at startup' nicht aktiviert." >&2
  fi
  [ "$missing" -ne 0 ] && exit 1
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
declare -A URL_BY_NAME URL_BY_INDEX
if [ -f "$URLS_INI" ]; then
  log "Lade URLs aus $URLS_INI"
  while IFS='=' read -r key val; do
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    key="${key//[[:space:]]/}"; key="${key,,}"
    val="${val##*( )}"; val="${val%%*( )}"
    if [ "$key" = "default" ]; then
      DEFAULT_URL="$val"
    elif [[ "$key" =~ ^index([0-9]+)$ ]]; then
      URL_BY_INDEX["${BASH_REMATCH[1]}"]=$val
    else
      URL_BY_NAME["$key"]=$val
    fi
  done <"$URLS_INI"
else
  log "WARN: urls.ini nicht gefunden. Nutze $DEFAULT_URL"
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
declare -A MON_URL WS_DIR MON_PID RESTART_COUNT
for idx in "${!MON_LIST[@]}"; do
  m="${MON_LIST[$idx]}"
  key="${m,,}"
  url="${URL_BY_NAME[$key]:-${URL_BY_INDEX[$idx]:-$DEFAULT_URL}}"
  ws="$WORKSPACES/$key"
  MON_URL["$m"]=$url
  WS_DIR["$m"]=$ws
  mkdir -p "$ws"
  if [ -d "$CHROMIUM_CONFIG" ]; then
    cp -r "$CHROMIUM_CONFIG/." "$ws/" 2>>"$ERRORLOG" \
      || log_error "Kopie nach $ws fehlgeschlagen"
  fi
  RESTART_COUNT["$m"]=0
  log "Setup: $m → $url (Workspace: $ws)"
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
    --no-first-run \
    --disable-session-crashed-bubble \
    --disable-infobars \
    --disable-save-password-bubble \
    --disable-gcm-registration \
    --disable-breakpad \
    --disable-background-networking \
    --disable-client-side-phishing-detection \
    --disable-component-update \
    --disable-sync \
    --disable-translate \
    --disable-features=PushMessaging \
    --user-data-dir="$ws" \
    --app="$url" \
    >>"$LOGFILE" 2> >(
      grep -v -E 'blink\.mojom\.WidgetHost|registration_request\.cc' \
      >>"$ERRORLOG"
    ) &

  MON_PID["$m"]=$!
  log "PID=${MON_PID[$m]}"

  sleep 3
  local win_id
  win_id=$(xdotool search --sync --onlyvisible --pid "${MON_PID[$m]}" | head -n1)
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
while true; do
  sleep "$CHECK_INTERVAL"
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
