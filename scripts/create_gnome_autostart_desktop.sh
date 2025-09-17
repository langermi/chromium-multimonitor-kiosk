#!/usr/bin/env bash
set -euo pipefail

# Erzeugt eine GNOME Autostart-.desktop Datei, die startkiosk.sh aus dem Repository-Verzeichnis startet.
# Verwendung: ./create_gnome_autostart_desktop.sh [--hidden]

HIDDEN=false
if [[ ${1:-} == "--hidden" ]]; then
  HIDDEN=true
fi

# Bestimme Repository-Verzeichnis (angenommen: dieses Skript liegt in scripts/ im Repo-Root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$SCRIPT_DIR/startkiosk.sh" ]]; then
  KIOSK_DIR="$SCRIPT_DIR"
else
  if [[ -f "$PWD/startkiosk.sh" ]]; then
    KIOSK_DIR="$PWD"
  else
    echo "Konnte startkiosk.sh nicht finden. Bitte führen Sie dieses Installationsskript im Repo-Root aus oder legen Sie es neben startkiosk.sh ab." >&2
    exit 2
  fi
fi

AUTOSTART_DIR="$HOME/.config/autostart"
DESKTOP_PATH="$AUTOSTART_DIR/kiosk.desktop"

mkdir -p "$AUTOSTART_DIR"

if [[ -f "$DESKTOP_PATH" ]]; then
  ts=$(date +%Y%m%d_%H%M%S)
  echo "Sichere bestehende Desktop-Datei nach ${DESKTOP_PATH}.bak.${ts}"
  cp -a "$DESKTOP_PATH" "${DESKTOP_PATH}.bak.${ts}"
fi

NO_DISPLAY="false"
if $HIDDEN; then
  NO_DISPLAY="true"
fi

cat > "$DESKTOP_PATH" <<EOF
[Desktop Entry]
Type=Application
Exec=bash -c "sleep 10 && ${KIOSK_DIR}/startkiosk.sh"
Hidden=false
NoDisplay=${NO_DISPLAY}
X-GNOME-Autostart-enabled=true
Name=Start Kiosk
Comment=Startet das Kiosk-System mit 10 Sekunden Verzögerung
EOF

chmod 644 "$DESKTOP_PATH"

echo "Autostart-.desktop Datei wurde erstellt: $DESKTOP_PATH"

exit 0
