#!/usr/bin/env bash

# LXDE-angepasste Variante von startkiosk.sh
# Ziel: gleiche Funktionalität wie das Original-Skript, aber ohne GNOME/GSettings-Abhängigkeit.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/config.sh"

IFS=$'\n\t'

cleanup() {
  if [ "${_CLEANUP_RUNNING:-0}" -ne 0 ]; then
    return 0
  fi
  _CLEANUP_RUNNING=1
  trap - INT TERM HUP QUIT EXIT
  log "cleanup: Empfangenes Signal -> beende Chromium-Prozesse"
  pkill -TERM -x chromium chromium-browser 2>/dev/null || true
  pkill -TERM -f "chromium" 2>/dev/null || true
  for i in 1 2 3 4 5; do
    if ! pgrep -f "chromium" >/dev/null 2>&1; then
      log "cleanup: Chromium-Prozesse beendet"
      break
    fi
    sleep 1
  done
  if pgrep -f "chromium" >/dev/null 2>&1; then
    log_warn "cleanup: Einige Chromium-Prozesse reagieren nicht -> sende SIGKILL"
    pkill -KILL -f "chromium" 2>/dev/null || true
  fi
  sleep 0.5
  exit 0
}

trap 'cleanup' INT TERM HUP QUIT
trap 'cleanup' EXIT

mkdir -p "$LOGDIR"
LOGFILE="${LOGDIR}/${LOG_TAG:-kiosk}-$(date '+%F').log"
LOG_DEBUG="${LOG_DEBUG:-0}"
exec 3>&2
exec 2> >(
  while IFS= read -r line; do
    ts="$(date '+%F %T')"
    if [ "${LOG_FORMAT:-text}" = "json" ]; then
      esc=$(printf '%s' "$line" | sed -e 's/\\/\\\\/g' -e 's/"/\\\"/g')
      printf '{"ts":"%s","level":"ERROR","msg":"%s"}\n' "$ts" "$esc" >>"$LOGFILE"
    else
      printf '%s [ERROR] %s\n' "$ts" "$line" >>"$LOGFILE"
    fi
    printf '%s\n' "$line" >&3
    if [ "${LOG_TO_JOURNAL:-false}" = true ]; then
      printf '%s\n' "$line" | logger -t "${LOG_TAG:-kiosk}" -p user.err
    fi
  done
)

pkill -x chromium chromium-browser 2>/dev/null || true
sleep 1

if [ -z "${BASH_VERSION:-}" ]; then
  echo "Dieses Skript benötigt bash. (bash startkiosk-lxde.sh)" >&2
  exit 1
fi

check_prereqs() {
  local missing=0
  # LXDE-spezifische Empfehlungen: xscreensaver oder light-locker, lxsession, notification-daemon
  for cmd in xdotool xrandr chromium curl xprintidle xset; do
    if ! command -v "$cmd" &>/dev/null; then
      log_error "Fehler: '$cmd' nicht gefunden. Bitte installieren."
      missing=1
    fi
  done

  # Prüfe, ob Wayland läuft (LXDE typischerweise X11)
  if [ "${XDG_SESSION_TYPE,,}" = "wayland" ]; then
    log_error "Fehler: Wayland läuft. Bitte unter X11 starten.";
    missing=1
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

# Logging functions (kopiert aus dem Original)
_COLOR_RESET="\e[0m"
_COLOR_INFO="\e[32m"
_COLOR_WARN="\e[33m"
_COLOR_ERROR="\e[31m"

json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\\"/g'; }

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

can_execute_reboot_or_poweroff() {
  if [ "$(id -u)" -eq 0 ]; then
    log_debug "can_execute_reboot_or_poweroff: running as root -> allowed"
    return 0
  fi
  if sudo -n true 2>/dev/null; then
    log_debug "can_execute_reboot_or_poweroff: sudo -n true -> allowed"
    return 0
  fi
  local sudo_list
  sudo_list=$(sudo -n -l 2>&1) || sudo_list="$sudo_list"
  if [ -n "$sudo_list" ]; then
    log_debug "can_execute_reboot_or_poweroff: sudo -l output: $(echo "$sudo_list" | tr '\n' ' ' | sed -e 's/  */ /g' -e 's/"/\\"/g')"
    if echo "$sudo_list" | grep -E -q '/sbin/(reboot|poweroff)\b|\breboot\b|\bpoweroff\b|systemctl[^\n]*reboot|systemctl[^\n]*poweroff'; then
      log_debug "can_execute_reboot_or_poweroff: sudo -l zeigt reboot/poweroff erlaubt"
      return 0
    fi
    if echo "$sudo_list" | grep -E -q 'NOPASSWD:.*ALL|NOPASSWD:\s*\b(reboot|poweroff)\b'; then
      log_debug "can_execute_reboot_or_poweroff: sudo -l zeigt NOPASSWD-Regel -> allowed"
      return 0
    fi
  fi
  if command -v loginctl &>/dev/null; then
    log_debug "can_execute_reboot_or_poweroff: loginctl vorhanden (berechtigungen ungetestet)"
    return 0
  fi
  if command -v dbus-send &>/dev/null; then
    log_debug "can_execute_reboot_or_poweroff: dbus-send vorhanden (berechtigungen ungetestet)"
    return 0
  fi
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

log_warn() { local msg="[$(date '+%F %T')] [WARN] $*"; echo -e "${_COLOR_WARN}${msg}${_COLOR_RESET}" >&1; rotate_by_size "$LOGFILE"; local ts="$(date '+%F %T')"; local text="$*"; local esc; esc=$(json_escape "$text"); if [ "${LOG_FORMAT:-text}" = "json" ]; then printf '{"ts":"%s","level":"WARN","msg":"%s"}\n' "$ts" "$esc" >>"$LOGFILE"; else printf '%s [WARN] %s\n' "$ts" "$text" >>"$LOGFILE"; fi; if [ "${LOG_TO_JOURNAL:-false}" = true ]; then printf '%s\n' "[$ts] [WARN] $text" | logger -t "${LOG_TAG:-kiosk}" -p user.warn; fi }

log_error() { local msg="[$(date '+%F %T')] [ERROR] $*"; echo -e "${_COLOR_ERROR}${msg}${_COLOR_RESET}" >&2; rotate_by_size "$LOGFILE"; local ts="$(date '+%F %T')"; local text="$*"; local esc; esc=$(json_escape "$text"); if [ "${LOG_FORMAT:-text}" = "json" ]; then printf '{"ts":"%s","level":"ERROR","msg":"%s"}\n' "$ts" "$esc" >>"$LOGFILE"; else printf '%s [ERROR] %s\n' "$ts" "$text" >>"$LOGFILE"; fi; if [ "${LOG_TO_JOURNAL:-false}" = true ]; then printf '%s\n' "[$ts] [ERROR] $text" | logger -t "${LOG_TAG:-kiosk}" -p user.err; fi }

log_debug() { [ "$LOG_DEBUG" -eq 1 ] || return 0; local msg="[$(date '+%F %T')] [DEBUG] $*"; echo -e "\e[36m${msg}${_COLOR_RESET}" >&1; rotate_by_size "$LOGFILE"; local ts="$(date '+%F %T')"; local text="$*"; local esc; esc=$(json_escape "$text"); if [ "${LOG_FORMAT:-text}" = "json" ]; then printf '{"ts":"%s","level":"DEBUG","msg":"%s"}\n' "$ts" "$esc" >>"$LOGFILE"; else printf '%s [DEBUG] %s\n' "$ts" "$text" >>"$LOGFILE"; fi; if [ "${LOG_TO_JOURNAL:-false}" = true ]; then printf '%s\n' "[$ts] [DEBUG] $text" | logger -t "${LOG_TAG:-kiosk}" -p user.debug; fi }

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
  log_debug "CHROMIUM_FLAGS=${CHROMIUM_FLAGS[*]:-(none)}"
}

validate_urls() {
    local url_valid=true
    local url
    for url in "$@"; do
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

rotate_logs() {
  mkdir -p "$LOGDIR"
  find "$LOGDIR" -type f -name "*.log" ! -name "*.gz" -mtime +1 -exec gzip {} \;
  ls -tp "$LOGDIR"/*.log.gz 2>/dev/null |
    tail -n +$((MAX_LOGS+1)) |
    xargs -r rm --
}
rotate_logs
log "=== Kiosk-Skript (LXDE) gestartet ==="
log_debug "CONFIG: CHECK_INTERVAL=$CHECK_INTERVAL PAGE_REFRESH_INTERVAL=$PAGE_REFRESH_INTERVAL RESTART_TIME=$RESTART_TIME POWEROFF_TIME=$POWEROFF_TIME LOG_DEBUG=$LOG_DEBUG"
log "Logging in $LOGFILE"
print_config_summary
check_prereqs

wait_for_network() {
  local deadline=$(( $(date +%s) + ${NETWORK_READY_TIMEOUT:-120} ))
  local check_interval=${NETWORK_READY_CHECK_INTERVAL:-5}
  local urls=("$@")
  local target="${NETWORK_READY_CHECK_URL:-}"
  if [ -z "$target" ]; then
    if [ ${#urls[@]} -gt 0 ]; then
      target="${urls[0]}"
    elif [ -n "${DEFAULT_URL:-}" ]; then
      target="$DEFAULT_URL"
    else
      target="https://example.com"
    fi
  fi

  if command -v nm-online &>/dev/null; then
    log "Prüfe Netzwerkverbindung via nm-online (Timeout ${NETWORK_READY_TIMEOUT:-120}s)."
  else
    log "Prüfe Netzwerkverbindung über HTTP-HEAD auf $target (Timeout ${NETWORK_READY_TIMEOUT:-120}s)."
  fi

  local nm_supported=0
  if command -v nm-online &>/dev/null; then
    nm_supported=1
  fi

  while [ $(date +%s) -le "$deadline" ]; do
    if [ "$nm_supported" -eq 1 ]; then
      if nm-online -q --timeout=1; then
        log "NetworkManager meldet Online-Status."
        return 0
      fi
    fi

    if curl --output /dev/null --silent --head --fail "$target"; then
      log "Netzwerkverbindung zu $target hergestellt."
      return 0
    fi

    sleep "$check_interval"
  done

  log_error "Netzwerk wurde innerhalb von ${NETWORK_READY_TIMEOUT:-120}s nicht erreichbar (letztes Prüfziel: $target)."
  return 1
}

if [ "${PAGE_REFRESH_INTERVAL:-0}" -lt "${REFRESH_INACTIVITY_THRESHOLD:-0}" ]; then
  log_error "Konfigurationsfehler: PAGE_REFRESH_INTERVAL (${PAGE_REFRESH_INTERVAL}s) ist kleiner als REFRESH_INACTIVITY_THRESHOLD (${REFRESH_INACTIVITY_THRESHOLD}s). Bitte korrigieren."
  exit 1
fi

# LXDE-spezifische Power-/Screensaver-Deaktivierung
if [ "${APPLY_POWER_SETTINGS:-true}" = true ]; then
  log "Deaktiviere Bildschirmschoner und Notifications (LXDE)"
  if command -v xset &>/dev/null; then
    xset s off || log_warn "xset: Konnte Bildschirmschoner (s off) nicht deaktivieren"
    xset -dpms || log_warn "xset: Konnte DPMS nicht deaktivieren"
    xset s noblank || log_warn "xset: Konnte Bildschirm-Blanking nicht deaktivieren"
  else
    log_warn "xset nicht gefunden; überspringe lokale X-Settings"
  fi

  # Versuche mögliche Bildschirmschoner/lockers zu stoppen
  for proc in xscreensaver light-locker lxsession-notify notification-daemon; do
    if pgrep -x "$proc" >/dev/null 2>&1; then
      pkill -TERM -x "$proc" 2>/dev/null || true
      log "Beende $proc";
    fi
  done
else
  log_warn "APPLY_POWER_SETTINGS ist deaktiviert; Power-/Screensaver-Einstellungen werden übersprungen"
fi

# Clean-exit in Chromium prefs abschalten (wie Original)
PREFS="$CHROMIUM_CONFIG/Default/Preferences"
if [ -f "$PREFS" ]; then
  sed -i 's/"exited_cleanly":false/"exited_cleanly":true/' "$PREFS" 2>>"$LOGFILE" || true
  sed -i 's/"exit_type":"Crashed"/"exit_type":"Normal"/'  "$PREFS" 2>>"$LOGFILE" || true
fi

# URLs einlesen (kopiert unverändert)
declare -A URL_BY_NAME URL_BY_INDEX REFRESH_BY_NAME REFRESH_BY_INDEX
declare -a ALL_URLS
DEFAULT_REFRESH_ENABLED=true

URL_VALIDATION_RETRIES=${URL_VALIDATION_RETRIES:-3}
URL_VALIDATION_RETRY_INTERVAL=${URL_VALIDATION_RETRY_INTERVAL:-5}

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
  if [ -n "${DEFAULT_URL:-}" ]; then
    found=false
    for u in "${ALL_URLS[@]}"; do
      if [ "$u" = "$DEFAULT_URL" ]; then
        found=true
        break
      fi
    done
    if [ "$found" = false ]; then
      ALL_URLS+=("$DEFAULT_URL")
    fi
  fi
else
  log "WARN: urls.ini nicht gefunden. Nutze $DEFAULT_URL"
  if [ -n "${DEFAULT_URL:-}" ]; then
    ALL_URLS+=("$DEFAULT_URL")
  fi
fi

if ! wait_for_network "${ALL_URLS[@]}"; then
  log_error "Abbruch: Netzwerkverbindung konnte nicht aufgebaut werden."
  exit 1
fi

if [ ${#ALL_URLS[@]} -gt 0 ]; then
  for attempt in $(seq 1 "$URL_VALIDATION_RETRIES"); do
    if validate_urls "${ALL_URLS[@]}"; then
      break
    fi
    if [ "$attempt" -lt "$URL_VALIDATION_RETRIES" ]; then
      log_warn "validate_urls failed (attempt $attempt/$URL_VALIDATION_RETRIES) - retrying in ${URL_VALIDATION_RETRY_INTERVAL}s"
      sleep "$URL_VALIDATION_RETRY_INTERVAL"
    else
      log_error "validate_urls failed after $URL_VALIDATION_RETRIES attempts"
    fi
  done
fi

# Monitore auslesen (unverändert)
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

declare -A MON_URL WS_DIR MON_PID RESTART_COUNT MON_REFRESH_ENABLED
for idx in "${!MON_LIST[@]}"; do
  m="${MON_LIST[$idx]}"
  key="${m,,}"
  url="${URL_BY_NAME[$key]:-${URL_BY_INDEX[$idx]:-$DEFAULT_URL}}"
  refresh_setting="${REFRESH_BY_NAME[$key]:-${REFRESH_BY_INDEX[$idx]:-$DEFAULT_REFRESH_ENABLED}}"
  ws="$WORKSPACES/$key"
  MON_URL["$m"]=$url
  MON_REFRESH_ENABLED["$m"]=$refresh_setting
  WS_DIR["$m"]=$ws
  mkdir -p "$ws"
  if [ -d "$CHROMIUM_CONFIG" ]; then
    cp -r "$CHROMIUM_CONFIG/." "$ws/" 2>>"$LOGFILE" || log_error "Kopie nach $ws fehlgeschlagen"
  fi
  RESTART_COUNT["$m"]=0
  log "Setup: $m → $url (Workspace: $ws, Refresh: ${MON_REFRESH_ENABLED[$m]})"
done

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

for m in "${MON_LIST[@]}"; do
  start_chromium "$m"
  sleep 1
done

last_refresh_time=$(date +%s)
prev_check_time=$(date +%s)
while true; do
  sleep "$CHECK_INTERVAL"
  now=$(date +%s)
  prev_mod=$((10#$(date -d "@${prev_check_time}" +%H)*3600 + 10#$(date -d "@${prev_check_time}" +%M)*60 + 10#$(date -d "@${prev_check_time}" +%S)))
  now_mod=$((10#$(date +%H)*3600 + 10#$(date +%M)*60 + 10#$(date +%S)))
  if (( now - last_refresh_time >= PAGE_REFRESH_INTERVAL )); then
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
                if xdotool windowactivate "$win_id" 2>>"$LOGFILE"; then
                  if xdotool key --window "$win_id" F5 2>>"$LOGFILE"; then
                    log "Refresh (F5) für Fenster $win_id auf Monitor $m gesendet."
                  else
                    log_warn "Fehler beim Senden von F5 an Fenster $win_id auf Monitor $m. Versuche Ctrl+R als Fallback."
                    if xdotool key --window "$win_id" ctrl+r 2>>"$LOGFILE"; then
                      log "Refresh (Ctrl+R Fallback) für Fenster $win_id auf Monitor $m gesendet."
                    else
                      log_error "Refresh konnte nicht an Fenster $win_id auf Monitor $m gesendet werden."
                    fi
                  fi
                else
                  log_warn "Konnte Fenster $win_id auf Monitor $m nicht aktivieren (xdotool windowactivate fehlgeschlagen)."
                fi
              fi
            fi
          else
            log "Refresh für Monitor $m übersprungen (deaktiviert)."
          fi
        done
        elapsed=$(( now - last_refresh_time ))
        remainder=$(( elapsed % PAGE_REFRESH_INTERVAL ))
        last_refresh_time=$(( now - remainder ))
      else
        log "Refresh übersprungen. System ist aktiv (Inaktivität: $idle_seconds s)."
      fi
  fi
  if [ "${ENABLE_RESTART:-true}" = "true" ]; then
    target_restart_mod=$(awk -F: '{print ($1*3600)+($2*60)}' <<<"$RESTART_TIME")
    log_debug "time-check restart: prev_mod=$prev_mod now_mod=$now_mod target_restart_mod=$target_restart_mod"
    if [ "$now_mod" -ge "$target_restart_mod" ]; then
      age_since_target=$(( now_mod - target_restart_mod ))
    else
      age_since_target=$(( now_mod + 24*3600 - target_restart_mod ))
    fi
    log_debug "restart: age_since_target=${age_since_target}s CHECK_INTERVAL=${CHECK_INTERVAL}s"
    if [ "$now_mod" -ge "$prev_mod" ]; then
          if [ "$target_restart_mod" -gt "$prev_mod" ] && [ "$target_restart_mod" -le "$now_mod" ] && [ "$age_since_target" -le "$CHECK_INTERVAL" ]; then
            if restart_system 2>>"$LOGFILE"; then
              log "restart_system: erfolgreich ausgelöst. Beende Watchdog." 
              exit 0
            else
              log_error "Neustart fehlgeschlagen (alle Methoden). Weiterer Watchdog-Lauf wird fortgesetzt."
            fi
          fi
    else
      if ([ "$target_restart_mod" -gt "$prev_mod" ] || [ "$target_restart_mod" -le "$now_mod" ]) && [ "$age_since_target" -le "$CHECK_INTERVAL" ]; then
        if restart_system 2>>"$LOGFILE"; then
          log "restart_system: erfolgreich ausgelöst. Beende Watchdog." 
          exit 0
        else
          log_error "Neustart fehlgeschlagen (alle Methoden). Weiterer Watchdog-Lauf wird fortgesetzt."
        fi
      fi
    fi
  fi
  if [ "${ENABLE_POWEROFF:-true}" = "true" ]; then
    target_power_mod=$(awk -F: '{print ($1*3600)+($2*60)}' <<<"$POWEROFF_TIME")
    log_debug "time-check poweroff: prev_mod=$prev_mod now_mod=$now_mod target_power_mod=$target_power_mod"
    if [ "$now_mod" -ge "$target_power_mod" ]; then
      age_since_target=$(( now_mod - target_power_mod ))
    else
      age_since_target=$(( now_mod + 24*3600 - target_power_mod ))
    fi
    log_debug "poweroff: age_since_target=${age_since_target}s CHECK_INTERVAL=${CHECK_INTERVAL}s"
    if [ "$now_mod" -ge "$prev_mod" ]; then
      if [ "$target_power_mod" -gt "$prev_mod" ] && [ "$target_power_mod" -le "$now_mod" ] && [ "$age_since_target" -le "$CHECK_INTERVAL" ]; then
        if poweroff_system 2>>"$LOGFILE"; then
          log "poweroff_system: erfolgreich ausgelöst. Beende Watchdog." 
          exit 0
        else
          log_error "Poweroff fehlgeschlagen (alle Methoden). Weiterer Watchdog-Lauf wird fortgesetzt."
        fi
      fi
    else
      if ([ "$target_power_mod" -gt "$prev_mod" ] || [ "$target_power_mod" -le "$now_mod" ]) && [ "$age_since_target" -le "$CHECK_INTERVAL" ]; then
        if poweroff_system 2>>"$LOGFILE"; then
          log "poweroff_system: erfolgreich ausgelöst. Beende Watchdog." 
          exit 0
        else
          log_error "Poweroff fehlgeschlagen (alle Methoden). Weiterer Watchdog-Lauf wird fortgesetzt."
        fi
      fi
    fi
  fi
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
        cp -r "$CHROMIUM_CONFIG/." "$ws/" 2>>"$LOGFILE" || log_error "Kopie nach $ws fehlgeschlagen"
      fi
      start_chromium "$m"
    fi
  done
done
