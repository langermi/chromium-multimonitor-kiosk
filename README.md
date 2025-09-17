# Multi-monitor Kiosk System mit Chromium

Dieses Bash-basierte Kiosk-System startet pro erkanntem Monitor eine eigene Chromium-Instanz im Vollbildmodus. URLs können global und monitor-spezifisch gesteuert werden, Workspaces werden je Monitor isoliert, Logs rotieren automatisch, und ein Watchdog startet abgestürzte Instanzen neu.

## Kurzübersicht

- Automatische Monitorerkennung via `xrandr` (Auflösung, Position, Rotation)
- URL-Zuweisung pro Monitor über `urls.ini` (Name oder Index)
- Fenstersteuerung & Vollbild via `xdotool`
- Watchdog überwacht Chromium-PIDs, rekreiert Workspaces und startet Instanzen neu
- Logging: tägliche Logs + size-basierte Rotation, optional JSON-Output und Weiterleitung an journald

## Repository klonen

```bash
git clone https://github.com/langermi/chromium-multimonitor-kiosk.git
chmod +x startkiosk.sh config.sh scripts/install_systemd_user_service.sh scripts/create_gnome_autostart_desktop.sh
```

## Projektstruktur

Standardstruktur (bei Default-BASEDIR `$HOME/kiosk-system`):

```
kiosk-system/
├── config.sh          # Basiskonfiguration, Pfade, Konstanten
├── startkiosk.sh      # Hauptskript (Erkennung, Start, Watchdog)
├── urls.ini           # URL-Zuweisungen pro Monitor
└── logs/              # Logs (automatisch erstellt und rotiert)
```

## Voraussetzungen

- bash (dient als Interpreter für die Skripte)
- X11 (Xorg) — Wayland wird nicht unterstützt (xdotool funktioniert unter Wayland nicht)
- Browser: `chromium` oder `chromium-browser`
- Tools: `xdotool`, `xrandr`, `gsettings`, `curl`, `xprintidle`
- Optional: GNOME (empfohlen) — Extension: „No overview at startup" empfohlen

Hinweis: `xprintidle` wird zur Inaktivitätsprüfung für automatische Seitenerneuerungen verwendet; ohne dieses Tool werden Seiten nur bedingt automatisch neu geladen.

## Wichtige Konfigurationswerte (canonical defaults aus `config.sh`)

Die folgenden Werte sind die Standard-Werte, wie sie in `config.sh` gesetzt sind. Passe sie dort an oder exportiere überschreibende Umgebungsvariablen vor dem Start.

- DISPLAY=:0
- BASEDIR="$HOME/kiosk-system"
- LOGDIR="$BASEDIR/logs"
- WORKSPACES="$BASEDIR/workspaces"
- URLS_INI="$BASEDIR/urls.ini"
- DEFAULT_URL="https://example.com"
- CHECK_INTERVAL=10                # Sek. zwischen Watchdog-Zyklen
- PAGE_REFRESH_INTERVAL=600       # Sek. zwischen möglichen Page-Refreshes
- REFRESH_INACTIVITY_THRESHOLD=300 # Sek. Inaktivität bis Refresh erlaubt
- MAX_LOGS=7
- MAX_LOG_SIZE=$((10*1024*1024))  # Bytes
- LOG_MAX_BACKUPS=5
- LOG_FORMAT="text"              # "text" oder "json"
- LOG_TO_JOURNAL=true             # true/false
- LOG_DEBUG=0                      # 0/1
- ENABLE_RESTART=true
- RESTART_TIME="23:00"
- ENABLE_POWEROFF=false
- POWEROFF_TIME="04:00"
- CHROMIUM_FLAGS=( ... )           # Array mit Default-Chromium-Flags (siehe `config.sh`)

Bitte verwende `config.sh` als Referenz; die Datei enthält die komplette Standard-Flagliste und Kommentare.

## Logging — wie das Skript loggt

- Per-run logs: `config.sh` erzeugt pro Startzeitpunkt Timestamped-Logs (`kiosk-start-YYYY-MM-DD_HH-MM-SS.log` und `kiosk-error-...`).
- Laufender täglicher Log: `startkiosk.sh` schreibt standardmäßig in `logs/kiosk-YYYY-MM-DD.log` und taggt Fehler/STDERR. Diese Datei wird bei Bedarf per size-rotation (siehe `MAX_LOG_SIZE`) rotiert.
- Tägliche Kompression: Logs älter als 1 Tag werden gzipped; es werden maximal `MAX_LOGS` Archive aufbewahrt.
- JSON-Modus: Setze `LOG_FORMAT=json` für maschinenlesbare Einträge.
- Optional: `LOG_TO_JOURNAL=true` leitet Logs zusätzlich an systemd/journald (`logger`) weiter.

## Wichtige Skriptfunktionen (Kurzreferenz)

Die wichtigsten Funktionen im `startkiosk.sh` sind:

- cleanup()
  - Beendet Chromium-Prozesse (pkill) und wird beim Empfang von SIGINT/SIGTERM/SIGHUP/EXIT aufgerufen.

- check_prereqs()
  - Prüft Verfügbarkeit der benötigten Tools (`xdotool`, `xrandr`, `gsettings`, `chromium`, `curl`, `xprintidle`) und validiert Zeitformate für `RESTART_TIME`/`POWEROFF_TIME`.

- validate_urls(...)
  - Prüft jede konfigurierte URL mit `curl --head`; bei `STRICT_URL_VALIDATION=true` bricht das Skript bei Fehlern ab.

- rotate_by_size(file)
  - Rotiert `file` in nummerierte Backups wenn es größer als `MAX_LOG_SIZE` wird (begrenzt durch `LOG_MAX_BACKUPS`).

- can_execute_reboot_or_poweroff()
  - Prüft, ob Neustart/Poweroff ohne interaktives Passwort möglich ist (testet `systemctl --user` und `sudo -n`).

- set_and_verify_gsetting(schema,key,value)
  - Schreibt GNOME gsettings und verifiziert durch Auslesen; wird für Screensaver/Power-Einstellungen verwendet.

- start_chromium(monitor)
  - Startet Chromium mit `--user-data-dir` und `--app=<url>`, wartet auf das Fenster (xdotool), positioniert es, passt Größe an und sendet `F11` für Vollbild. Weitere startparameter werden in der `config.sh` konfiguriert
  - Im Testmodus (`./startkiosk.sh --test`) wird Chromium-Start übersprungen.

- restart_system()/poweroff_system()
  - Führen `sudo systemctl reboot` bzw. `sudo systemctl poweroff` aus. Werden durch die Watchdog-Zeitlogik zu `RESTART_TIME` / `POWEROFF_TIME` ausgelöst (sofern aktiviert).

- Watchdog loop
  - Überwacht PIDs, führt Refreshes (F5) bei Inaktivität aus, prüft geplante Restart/Poweroff-Zeiten und startet abgestürzte Instanzen neu (löscht und rekreiert Workspace vorher).

Hinweis: Beim Neustart einer abgestürzten Instanz wird das Workspace-Verzeichnis (`WORKSPACES/<monitor>`) gelöscht (`rm -rf`) und neu erstellt; vorhandene Profilkopien aus `$CHROMIUM_CONFIG` werden erneut hineinkopiert (falls gesetzt). Das bedeutet: Browserdaten werden dabei zurückgesetzt — plane dies bei persistenten Daten ein.

## `urls.ini` — Syntax & Optionen

Beispiel:

```ini
default=https://www.google.com
displayport-0=https://www.bing.com
displayport-1=https://www.duckduckgo.com,norefresh
# index-basierte Alternative:
# index0=https://example.org
```

- Keys:
  - `default` – Fallback-URL, falls keine Monitor-Zuweisung vorhanden ist
  - `<monitor-name>=<url>[,norefresh]` – Monitorname wie von `xrandr` (wird im Skript kleingeschrieben)
  - `indexN` – alternative Zuweisung nach erkannter Reihenfolge (0-basiert)
- Option `norefresh`: Wenn angehängt, wird der automatische periodische F5-Refresh für diesen Monitor deaktiviert.

Wichtig: Monitor-Namen werden aus `xrandr --query` entnommen, in Kleinbuchstaben konvertiert und Whitespace entfernt, die Einträge in `urls.ini` sollten entsprechend angepasst werden.

## Start und Betrieb

- Normaler Start:
```
./startkiosk.sh
```
- Testmodus (kein Chromium-Start, prüft Konfiguration und Logging):
```
./startkiosk.sh --test
```

### Autostart als systemd user service (empfohlen als user unit)

Beispiel `~/.config/systemd/user/kiosk.service` (passe WorkingDirectory/ExecStart an):

```ini
[Unit]
Description=Chromium Kiosk
After=graphical.target

[Service]
Type=simple
Environment=DISPLAY=:0
Environment=XAUTHORITY=%h/.Xauthority
WorkingDirectory=%h/kiosk-system
TimeoutStartSec=120
ExecStart=/bin/bash -lc "sleep 10 && $HOME/kiosk-system/startkiosk.sh"
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
```

Aktivieren:

```bash
systemctl --user daemon-reload
systemctl --user enable --now kiosk.service
```

Hinweis: `graphical.target` oder der genaue Target-Name kann distributionsabhängig variieren.

### Alternativ: Autostart als .desktop-Datei (GNOME)

```ini
# ~/.config/autostart/kiosk.desktop
[Desktop Entry]
Type=Application
Exec=bash -c "sleep 10 && $HOME/kiosk-system/startkiosk.sh"
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Start Kiosk
Comment=Startet das Kiosk-System mit 10 Sekunden Verzögerung
```

## Troubleshooting (häufige Probleme)

- Chromium startet nicht: Prüfe `CHROMIUM_BIN` (in `config.sh`) und Installation von `chromium` bzw. `chromium-browser`.
- Fenster lassen sich nicht bewegen / kein Vollbild: Verwende eine Xorg-Session, stelle sicher, dass `xdotool` installiert ist.
- GNOME-Übersicht stört: Aktiviere die Extension „No overview at startup" oder konfiguriere GNOME entsprechend.
- URLs werden abgelehnt: Bei `STRICT_URL_VALIDATION=true` bricht das Skript ab, wenn `validate_urls()` fehlschlägt. Setze `STRICT_URL_VALIDATION=false`, um nur zu warnen.
- Automatischer Neustart schlägt fehl: Prüfe, ob `can_execute_reboot_or_poweroff()` einen Weg findet, Neustart/Poweroff ohne Passwort auszuführen (systemctl --user oder sudo-NOPASSWD Konfiguration). Am einfachsten ist es dem User die Restartberechtigungen ohne Passwort zu erlauben. Dazu in der sudoers Datei folgendes hinzufügen
```bash
deinbenutzername ALL=(ALL) NOPASSWD: /bin/systemctl reboot, /bin/systemctl poweroff
```
## Lizenz

Siehe `LICENCE` im Repository. Dieses Dokument ist die maßgebliche Quelle für Lizenzbedingungen

Kontakt für Fragen: michael+git@langer.tirol
