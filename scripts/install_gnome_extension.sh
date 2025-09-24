#!/bin/bash

# Script zur Installation der GNOME Extension "No overview at startup"
# URL: https://extensions.gnome.org/extension/4099/no-overview/

set -euo pipefail

# Logging-Funktion
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Extension Details
EXTENSION_ID="4099"
EXTENSION_UUID="no-overview@fthx"
EXTENSION_NAME="No overview at startup"

log "Installiere GNOME Extension: $EXTENSION_NAME"

# Prüfe ob GNOME Shell läuft
if ! pgrep -x "gnome-shell" > /dev/null; then
    log "Fehler: GNOME Shell läuft nicht. Bitte in einer GNOME Session ausführen."
    exit 1
fi

# GNOME Shell Version ermitteln
GNOME_VERSION=$(gnome-shell --version | sed 's/GNOME Shell //' | cut -d'.' -f1,2)
log "GNOME Shell Version: $GNOME_VERSION"

# Extensions-Verzeichnis erstellen
EXTENSIONS_DIR="$HOME/.local/share/gnome-shell/extensions"
mkdir -p "$EXTENSIONS_DIR"

# Extension-spezifisches Verzeichnis
EXTENSION_DIR="$EXTENSIONS_DIR/$EXTENSION_UUID"

log "Lade Extension-Metadaten..."

# Metadaten von extensions.gnome.org abrufen
METADATA_URL="https://extensions.gnome.org/extension-info/?pk=$EXTENSION_ID"
METADATA=$(curl -s "$METADATA_URL" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(json.dumps(data, indent=2))
")

log "Suche kompatible Version für GNOME $GNOME_VERSION..."

# Ermittle Download-URL für die passende Version
DOWNLOAD_URL=$(echo "$METADATA" | python3 -c "
import json, sys, re
data = json.load(sys.stdin)
shell_version_map = data.get('shell_version_map', {})
download_url = None

def extract_url(obj):
    # defensive extraction of a URL from various possible structures
    if isinstance(obj, dict):
        for key in ('download_url', 'downloadUrl', 'package_url', 'url', 'download'):
            v = obj.get(key)
            if isinstance(v, str) and v:
                return v
        # sometimes the dict may contain nested structures
        for v in obj.values():
            url = extract_url(v)
            if url:
                return url
    elif isinstance(obj, list):
        for item in obj:
            url = extract_url(item)
            if url:
                return url
    elif isinstance(obj, str):
        return obj
    return None

# Versuche exakte Version zu finden
target = '$GNOME_VERSION'
entry = shell_version_map.get(target)
if entry is not None:
    download_url = extract_url(entry)
else:
    # Fallback: neueste verfügbare Version (semantisch größtes Versionsschema)
    versions = list(shell_version_map.keys())
    if versions:
        def version_key(x):
            parts = re.split(r'[-._]', x)
            nums = []
            for p in parts:
                try:
                    nums.append(int(p))
                except:
                    break
            return nums
        latest_version = max(versions, key=version_key)
        download_url = extract_url(shell_version_map.get(latest_version))

if download_url:
    if not download_url.startswith('http'):
        print('https://extensions.gnome.org' + download_url)
    else:
        print(download_url)
else:
    sys.exit(1)
")

if [[ -z "$DOWNLOAD_URL" ]]; then
    log "Fehler: Keine kompatible Version gefunden!"
    log "Hinweis: Die Struktur der Metadata-Antwort könnte sich geändert haben. Zur Fehlersuche:"
    log "  curl -s \"$METADATA_URL\" | jq '.' > /tmp/gnome-ext-metadata.json"
    log "  und prüfen Sie /tmp/gnome-ext-metadata.json"
    exit 1
fi

log "Download-URL: $DOWNLOAD_URL"

# Temporäres Verzeichnis für Download
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

log "Lade Extension herunter..."
curl -L "$DOWNLOAD_URL" -o "$TEMP_DIR/extension.zip"

# Extension entpacken
log "Entpacke Extension..."
unzip -q "$TEMP_DIR/extension.zip" -d "$TEMP_DIR/extension/"

# Prüfe ob Extension bereits installiert ist
if [[ -d "$EXTENSION_DIR" ]]; then
    log "Extension bereits installiert. Erstelle Backup..."
    mv "$EXTENSION_DIR" "$EXTENSION_DIR.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Extension installieren
log "Installiere Extension..."
mv "$TEMP_DIR/extension" "$EXTENSION_DIR"

# Extension aktivieren
log "Aktiviere Extension..."
gnome-extensions enable "$EXTENSION_UUID"

# Warte kurz und prüfe Status
sleep 2
if gnome-extensions list --enabled | grep -q "$EXTENSION_UUID"; then
    log "Extension erfolgreich aktiviert!"
else
    log "Warnung: Extension konnte nicht automatisch aktiviert werden."
    log "Bitte manuell über gnome-extensions enable $EXTENSION_UUID aktivieren."
fi

# Prüfe ob Extension läuft
if gnome-extensions show "$EXTENSION_UUID" | grep -q "State: ENABLED"; then
    log "Extension läuft erfolgreich!"
else
    log "Extension installiert, aber möglicherweise nicht aktiv."
fi

log ""
log "Installation abgeschlossen!"
log "Extension: $EXTENSION_NAME"
log "UUID: $EXTENSION_UUID"
log ""
log "Die Extension verhindert, dass die GNOME Overview beim Login angezeigt wird."
log "Dies ist wichtig für ein Kiosk-System, da es störende Überlagerungen vermeidet."