#!/bin/bash

# Script zur Installation der GNOME Extension "No overview at startup"
# URL: https://extensions.gnome.org/extension/4099/no-overview/
#
# Usage notes / debugging:
# - KEEP_METADATA=1 : verhindert das automatische Löschen des temporären Verzeichnisses
#   und schreibt die heruntergeladene metadata.json nach /tmp/gnome-ext-metadata.json.
# - GNOME_MAJOR_OVERRIDE=48 : überschreibt die automatisch ermittelte GNOME Major-Version
#   falls du das Script in einem Build/CI ohne laufende gnome-shell ausführst.
# - Bei Fehlern wird eine fehlerhafte Download-Datei nach /tmp/gnome-ext-download-failed
#   kopiert; prüfe diese Datei mit 'file' und 'head' um zu sehen, ob HTML statt ZIP geladen wurde.
# - Optional kann man das Script zuerst mit KEEP_METADATA=1 laufen lassen, um Metadaten zu
#   inspizieren bevor das Installations-Verzeichnis verändert wird.

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

# Prüfe ob GNOME Shell läuft. Statt abzubrechen, nur Warnung ausgeben.
# Auf vielen Kiosk-Build-Systemen läuft GNOME hier nicht; wir wollen dennoch
# die Metadata-Auswahl basierend auf der Major-Version durchführen können.
if ! pgrep -x "gnome-shell" > /dev/null 2>&1; then
    log "Warnung: GNOME Shell läuft nicht. Fortfahren; GNOME-Version wird versucht zu ermitteln oder auf Major 43 (Debian 13) gesetzt."
fi

# GNOME Shell Major-Version ermitteln (nur die Major-Nummer, z.B. "43" für Debian 13)
# Wir lesen nur die Major-Version, weil extensions.gnome.org in der shell_version_map
# häufig Keys wie "43" oder "43.1" hat. Für Debian 13 ist die Major-Version 43.
# Ermögliche Überschreiben per Umgebungsvariable (z.B. in CI): GNOME_MAJOR_OVERRIDE=43
GNOME_MAJOR=${GNOME_MAJOR_OVERRIDE:-$(gnome-shell --version 2>/dev/null | sed 's/GNOME Shell //' | cut -d'.' -f1 || true)}
# Falls wir die Version nicht ermitteln können (z.B. kein gnome-shell installiert),
# für Debian 13 die Major-Version 43 standardmäßig verwenden.
if [[ -z "${GNOME_MAJOR:-}" ]]; then
    GNOME_MAJOR="43"
    log "GNOME Major-Version konnte nicht ermittelt werden — verwende Standard: $GNOME_MAJOR (Debian 13)"
else
    log "GNOME Shell Major-Version: $GNOME_MAJOR"
fi

# Extensions-Verzeichnis erstellen
EXTENSIONS_DIR="$HOME/.local/share/gnome-shell/extensions"
mkdir -p "$EXTENSIONS_DIR"

# Extension-spezifisches Verzeichnis
EXTENSION_DIR="$EXTENSIONS_DIR/$EXTENSION_UUID"

# Temporäres Verzeichnis für Download/Metadaten (früher anlegen, damit wir
# die Metadaten persistieren und bei Fehlern untersuchen können)
TEMP_DIR=$(mktemp -d)
# Wenn KEEP_METADATA=1 gesetzt ist, behalten wir das TEMP_DIR für Debug-Zwecke.
if [[ "${KEEP_METADATA:-}" == "1" ]]; then
    log "KEEP_METADATA=1 gesetzt: Temporäres Verzeichnis wird nicht automatisch gelöscht: $TEMP_DIR"
else
    trap "rm -rf \"$TEMP_DIR\"" EXIT
fi

log "Lade Extension-Metadaten..."

# Metadaten von extensions.gnome.org abrufen (User-Agent, follow redirects)
METADATA_URL="https://extensions.gnome.org/extension-info/?pk=$EXTENSION_ID"
METADATA_FILE="$TEMP_DIR/metadata.json"
if ! curl -fsSL -A "Mozilla/5.0 (X11; Linux x86_64)" "$METADATA_URL" -o "$METADATA_FILE"; then
    log "Fehler: Konnte Metadaten von $METADATA_URL nicht herunterladen."
    log "Prüfen Sie Netzwerk oder extensions.gnome.org Erreichbarkeit."
    exit 1
fi

# Prüfen ob gültiges JSON
if ! python3 -c "import sys,json
try:
    json.load(open(sys.argv[1]))
except Exception as e:
    sys.exit(2)
" "$METADATA_FILE"; then
    log "Fehler: Metadaten sind kein gültiges JSON. Datei: $METADATA_FILE"
    log "Inhalt (erste 200 Zeilen):"
    sed -n '1,200p' "$METADATA_FILE" | sed -n '1,200p'
    log "Tipp: curl -s '$METADATA_URL' | jq '.' > /tmp/gnome-ext-metadata.json"
    exit 1
fi

log "Suche kompatible Version für GNOME Major $GNOME_MAJOR..."

# Ermittle Download-URL für die passende Version (robuster: liest Datei)
DOWNLOAD_URL=$(python3 - "$METADATA_FILE" "$GNOME_MAJOR" <<'PY'
import json, sys, re
data = json.load(open(sys.argv[1]))
shell_version_map = data.get('shell_version_map', {})
download_url = None

def extract_url(obj):
    if isinstance(obj, dict):
        for key in ('download_url', 'downloadUrl', 'package_url', 'url', 'download'):
            v = obj.get(key)
            if isinstance(v, str) and v:
                return v
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

target = sys.argv[2] if len(sys.argv) > 2 else ''
entry = None
if target:
    entry = shell_version_map.get(target)
    if entry is None:
        for k in shell_version_map.keys():
            ks = str(k)
            if ks == target or ks.startswith(target + '.'):
                entry = shell_version_map.get(k)
                break
    if entry is None:
        for k in shell_version_map.keys():
            if str(k).split('.')[0] == target:
                entry = shell_version_map.get(k)
                break

if entry is not None:
    # If the map entry is a dict containing pk/version, construct the download URL
    if isinstance(entry, dict):
        # Prefer explicit URLs present in metadata (robust)
        download_url = extract_url(entry)
        if not download_url:
            pk = entry.get('pk') or entry.get('package') or entry.get('package_id')
            ver = entry.get('version')
            # Historically the site has exposed different download endpoints.
            # The query-string form (/download-extension/?pk=...&version=...) may
            # return 404 for some deployments. Try multiple sensible formats
            # and rely on the caller to follow redirects.
            if pk and ver:
                candidates = [
                    f"/download-extension/?pk={pk}&version={ver}",
                    f"/download-extension/{pk}/?version={ver}",
                    f"/download-extension/{pk}/{ver}/",
                ]
                # Prepend host if candidate is relative and pick the first that
                # looks valid (we'll output a fully qualified https URL)
                for c in candidates:
                    download_url = 'https://extensions.gnome.org' + c
                    # No network check here; the caller will try to curl and fail
                    # if the URL is invalid. Break after the first candidate.
                    break
            else:
                download_url = None
    else:
        download_url = extract_url(entry)
else:
    versions = list(shell_version_map.keys())
    if versions:
        def version_key(x):
            parts = re.split(r'[-._]', str(x))
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
    # Normalize relative paths
    if not download_url.startswith('http'):
        download_url = 'https://extensions.gnome.org' + download_url
    # Ensure we output only one URL and that it's HTTPS
    if download_url.startswith('http://'):
        download_url = 'https://' + download_url.split('://',1)[1]
    print(download_url)
# else: no output -> handled by shell
PY
)

if [[ -z "$DOWNLOAD_URL" ]]; then
    log "Fehler: Keine kompatible Version gefunden für GNOME Major $GNOME_MAJOR"
    # Sicherstellen, dass die Metadaten für Debug-Zwecke verfügbar sind, auch
    # wenn das temporäre Verzeichnis bereits gelöscht werden könnte.
    if [[ -f "$METADATA_FILE" ]]; then
        cp -a "$METADATA_FILE" /tmp/gnome-ext-metadata.json || true
        chmod 644 /tmp/gnome-ext-metadata.json || true
        log "Metadaten wurden nach /tmp/gnome-ext-metadata.json kopiert."
        # Zeige die Keys in shell_version_map (falls vorhanden) zur schnellen Analyse
        if python3 - <<'PY' "$METADATA_FILE" >/dev/null 2>&1
import json,sys
try:
    data=json.load(open(sys.argv[1]))
    keys=list(data.get('shell_version_map', {}).keys())
    print('\n'.join(map(str,keys)))
except Exception:
    sys.exit(2)
PY
        then
            log "Vorhandene shell_version_map keys (oben):"
        else
            log "Konnte shell_version_map keys nicht auslesen (ungültiges JSON oder anderes Problem)."
        fi
    else
        log "Metadaten-Datei $METADATA_FILE existiert nicht (wurde evtl. bereits gelöscht)."
    fi
    log "Bitte prüfen Sie /tmp/gnome-ext-metadata.json oder führen Sie das Skript mit KEEP_METADATA=1 aus."
    exit 1
fi

log "Download-URL: $DOWNLOAD_URL"

log "Lade Extension herunter..."
curl -L "$DOWNLOAD_URL" -o "$TEMP_DIR/extension.zip"

# Schnellprüfung: ist die geladene Datei wirklich ein ZIP-Archiv?
# ZIP-Dateien beginnen typischerweise mit den Bytes PK\x03\x04 (50 4b 03 04).
if ! head -c4 "$TEMP_DIR/extension.zip" | od -An -tx1 | tr -d ' \n' | grep -qi '^504b0304'; then
    log "Fehler: Die heruntergeladene Datei scheint kein ZIP-Archiv zu sein. Möglicherweise wurde eine HTML-Fehlerseite (404 / Login) geladen."
    # Für Debug-Zwecke die Datei nach /tmp kopieren, damit sie analysiert werden kann.
    cp -a "$TEMP_DIR/extension.zip" /tmp/gnome-ext-download-failed || true
    chmod 644 /tmp/gnome-ext-download-failed || true
    log "Die heruntergeladene Datei wurde nach /tmp/gnome-ext-download-failed kopiert. Erste 40 Zeilen:"
    sed -n '1,40p' /tmp/gnome-ext-download-failed | sed -n '1,40p'
    log "Auch die Metadaten wurden (falls vorhanden) nach /tmp/gnome-ext-metadata.json kopiert. Führe das Script mit KEEP_METADATA=1 aus, um weitere Details zu behalten."
    exit 1
fi

# Extension entpacken
log "Entpacke Extension..."
unzip -q "$TEMP_DIR/extension.zip" -d "$TEMP_DIR/extension/"

# Prüfe ob Extension bereits installiert ist
if [[ -d "$EXTENSION_DIR" ]]; then
    log "Extension bereits installiert. Erstelle Backup..."
    mv "$EXTENSION_DIR" "$EXTENSION_DIR.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Extension installieren (robustes Verschieben der entpackten Inhalte)
log "Installiere Extension..."
if [[ -d "$TEMP_DIR/extension" ]]; then
    # Finde Top-Level-Einträge
    mapfile -t entries < <(printf '%s\n' "$TEMP_DIR/extension"/* 2>/dev/null)
    mkdir -p "$EXTENSION_DIR"
    if (( ${#entries[@]} == 1 )) && [[ -d "${entries[0]}" ]]; then
        log "Paket enthält einen einzelnen Top-Level-Ordner: $(basename "${entries[0]}") — verschiebe dessen Inhalt nach $EXTENSION_DIR"
        mv "${entries[0]}"/* "$EXTENSION_DIR"/ || true
    else
        log "Paket enthält mehrere Dateien/Ordner im Root — verschiebe alles nach $EXTENSION_DIR"
        mv "$TEMP_DIR/extension"/* "$EXTENSION_DIR"/ || true
    fi
    # Liste Inhalte zur Verifikation
    log "Inhalte von $EXTENSION_DIR:" 
    ls -la "$EXTENSION_DIR" || true
else
    log "Fehler: Nach dem Entpacken wurde kein Ordner $TEMP_DIR/extension gefunden. Verzeichnisinhalt:" 
    ls -la "$TEMP_DIR" || true
    exit 1
fi

# Extension aktivieren (nur wenn gnome-extensions verfügbar und GNOME Shell läuft)
if command -v gnome-extensions >/dev/null 2>&1; then
    if pgrep -x "gnome-shell" > /dev/null 2>&1; then
        log "Aktiviere Extension..."
        if gnome-extensions enable "$EXTENSION_UUID"; then
            log "Extension erfolgreich aktiviert!"
        else
            log "Warnung: 'gnome-extensions enable' schlug fehl. Bitte manuell ausführen: gnome-extensions enable $EXTENSION_UUID"
        fi
        # Warte kurz und prüfe Status
        sleep 2
        if gnome-extensions list --enabled | grep -q "$EXTENSION_UUID"; then
            log "Extension ist in der Liste der aktivierten Erweiterungen."
        else
            log "Warnung: Extension wurde installiert, ist aber nicht als aktiviert gelistet."
        fi
    else
        log "GNOME Shell läuft nicht; Aktivierung übersprungen. Bitte später aktivieren: gnome-extensions enable $EXTENSION_UUID"
    fi
else
    log "gnome-extensions Tool nicht gefunden; die Extension wurde ins Zielverzeichnis kopiert. Bitte manuell aktivieren sobald verfügbar."
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