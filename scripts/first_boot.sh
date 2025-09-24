#!/usr/bin/env bash
set -euo pipefail

# One-time first-boot script to perform tasks that are unreliable during preseed
# - Runs as root (system service) on first boot
# - Performs: ensure user/home, clone repo as kiosk, chmod scripts, install user unit file
# - Removes itself / disables service on success

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

KIOSK_USER=${KIOSK_USER:-kiosk}
KIOSK_HOME=/home/${KIOSK_USER}
REPO_URL=${REPO_URL:-https://github.com/langermi/chromium-multimonitor-kiosk.git}
REPO_DIR="$KIOSK_HOME/chromium-multimonitor-kiosk"

log() { echo "[first-boot] $*"; }

ensure_user_home() {
  if ! id "$KIOSK_USER" &>/dev/null; then
    log "Benutzer $KIOSK_USER existiert nicht; Abbruch." >&2
    return 1
  fi
  mkdir -p "$KIOSK_HOME"
  chown -R "$KIOSK_USER":"$KIOSK_USER" "$KIOSK_HOME"
}

clone_repo() {
  if [[ -d "$REPO_DIR/.git" ]]; then
    log "Repo bereits vorhanden: $REPO_DIR"
    return 0
  fi
  log "Klonen des Repos nach $REPO_DIR"
  if command -v git &>/dev/null; then
    sudo -u "$KIOSK_USER" git clone "$REPO_URL" "$REPO_DIR" || true
    chown -R "$KIOSK_USER":"$KIOSK_USER" "$REPO_DIR" || true
  else
    log "git nicht installiert; überspringe Repo-Klonen"
  fi
}

make_scripts_executable() {
  if [[ -d "$REPO_DIR" ]]; then
    chmod +x "$REPO_DIR/startkiosk.sh" || true
    chmod +x "$REPO_DIR/config.sh" || true
    chmod +x "$REPO_DIR/scripts"/*.sh || true
    chown -R "$KIOSK_USER":"$KIOSK_USER" "$REPO_DIR" || true
  fi
}

install_user_unit() {
  # Install systemd --user unit by invoking the helper script as the kiosk user
  if [[ -x "$REPO_DIR/scripts/install_systemd_user_service.sh" ]]; then
    log "Installiere user systemd Unit via helper script"
    su -s /bin/bash -c "$REPO_DIR/scripts/install_systemd_user_service.sh --no-enable" "$KIOSK_USER" || true
    # Enabling of the user unit must happen in the user session; leave it for autostart
  fi
}

disable_service_and_exit() {
  # Disable the one-shot service so it won't run again
  systemctl disable --now kiosk-firstboot.service || true
  # Optionally remove unit file
  # rm -f /etc/systemd/system/kiosk-firstboot.service || true
  log "First-boot tasks abgeschlossen"
}

main() {
  log "Starte first-boot tasks"
  ensure_user_home || exit 1
  clone_repo
  make_scripts_executable
  install_user_unit
  disable_service_and_exit
}

main "$@"
