#!/usr/bin/env bash
set -euo pipefail

# Installiert eine systemd --user Unit, die startkiosk.sh aus dem Repository-Verzeichnis startet.
# Verwendung: ./install_systemd_user_service.sh [--enable]

# Standardmäßig die Unit aktivieren/starten. Mit --no-enable überspringen.
ENABLE=true
if [[ ${1:-} == "--no-enable" ]]; then
  ENABLE=false
fi

# Bestimme das Verzeichnis, das startkiosk.sh enthält. Ermöglicht Aufruf von überall.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$SCRIPT_DIR/startkiosk.sh" ]]; then
  KIOSK_DIR="$SCRIPT_DIR"
else
  # Fallback: prüfe aktuelles Arbeitsverzeichnis (PWD)
  if [[ -f "$PWD/startkiosk.sh" ]]; then
    KIOSK_DIR="$PWD"
  else
  echo "Konnte startkiosk.sh nicht finden. Bitte führen Sie dieses Installationsskript im Repo-Root aus oder legen Sie es neben startkiosk.sh ab." >&2
    exit 2
  fi
fi

UNIT_DIR="$HOME/.config/systemd/user"
UNIT_PATH="$UNIT_DIR/kiosk.service"

mkdir -p "$UNIT_DIR"

if [[ -f "$UNIT_PATH" ]]; then
  ts=$(date +%Y%m%d_%H%M%S)
  echo "Sichere bestehende Unit nach ${UNIT_PATH}.bak.${ts}"
  cp -a "$UNIT_PATH" "${UNIT_PATH}.bak.${ts}"
fi

cat > "$UNIT_PATH" <<EOF
[Unit]
Description=Chromium Kiosk
After=graphical.target

[Service]
Type=simple
Environment=DISPLAY=:0
Environment=XAUTHORITY=%h/.Xauthority
WorkingDirectory=${KIOSK_DIR}
TimeoutStartSec=120
ExecStart=/bin/bash -lc "sleep 10 && ${KIOSK_DIR}/startkiosk.sh"
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

chmod 644 "$UNIT_PATH"

echo "Systemd user Unit wurde unter $UNIT_PATH installiert"

if $ENABLE; then
  if command -v systemctl >/dev/null 2>&1; then
    echo "Lade user systemd-Daemon neu und aktiviere/starte den Dienst..."
    systemctl --user daemon-reload
    systemctl --user enable --now kiosk.service
    echo "Dienst wurde aktiviert und gestartet (user Unit)."
  else
    echo "systemctl wurde nicht im PATH gefunden; Unit wurde installiert, kann aber nicht aktiviert/gestartet werden. Sie können es später mit ausführen: systemctl --user daemon-reload && systemctl --user enable --now kiosk.service" >&2
  fi
else
  echo "Unit wurde installiert. Um den Dienst zu aktivieren und zu starten, führen Sie aus: systemctl --user daemon-reload && systemctl --user enable --now kiosk.service"
fi

exit 0
