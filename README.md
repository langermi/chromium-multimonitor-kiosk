# Chromium Multi-Monitor Kiosk

Chromium Multi-Monitor Kiosk stellt ein ausfallsicheres Browser-Kiosk-System für Mehrschirm-Szenarien bereit. Das Projekt liefert Shell-Skripte für GNOME- und LXDE-Desktops, verwaltet Monitor-spezifische Start-URLs, führt watchdog-basierte Selbstheilung, Zeitsteuerung für Neustarts/Shutdowns und eine umfangreiche Protokollierung durch. Ergänzend stehen Debian-Preseed-Dateien für eine vollautomatisierte Installation zur Verfügung.

## Inhaltsverzeichnis

1. [Funktionen](#funktionen)
2. [Unterstützte Plattformen & Voraussetzungen](#unterstützte-plattformen--voraussetzungen)
3. [Schnellstart](#schnellstart)
4. [Konfiguration](#konfiguration)
    - [config.sh](#configsh)
    - [urls.ini](#urlsini)
    - [weitere Ressourcen](#weitere-ressourcen)
5. [Betrieb & Automatisierung](#betrieb--automatisierung)
6. [Protokollierung & Wartung](#protokollierung--wartung)
7. [Automatisierte Installation (Preseed)](#automatisierte-installation-preseed)
8. [Troubleshooting](#troubleshooting)
9. [Lizenz](#lizenz)

## Funktionen

- 🖥️ **Multi-Monitor-Layout:** Jeder erkannte Monitor erhält eine eigene URL und ein getrenntes Chromium-Profil.
- 🧩 **GNOME & LXDE:** Angepasste Startskripte (`startkiosk-gnome.sh`, `startkiosk-lxde.sh`) berücksichtigen Eigenheiten der jeweiligen Desktop-Umgebung.
- ⚙️ **Zentrale Konfiguration:** Alle relevanten Einstellungen befinden sich in `config.sh`.
- 🔄 **Watchdog & Selbstheilung:** Chromium-Prozesse werden überwacht, bei Absturz automatisch neu gestartet und optional regelmäßig refresht.
- ⏰ **Zeitgesteuerte Aktionen:** Geplanter Neustart/Shutdown inklusive mehrerer Fallback-Kommandos.
- 📡 **Netzwerk-Bereitschaftsprüfung:** Start wartet optional auf eine funktionierende Internetverbindung.
- 📜 **Logging & Rotation:** Dateibasierte Logs, optionale Journald-Ausgabe, Log-Rotation.
- 🛠️ **Automatisierter Rollout:** Debian-Preseed-Dateien erzeugen ein fertiges Kiosk-System mit Autologin, Service-Einbindung und vorkonfigurierten Skripten.

## Unterstützte Plattformen & Voraussetzungen

- Debian 13 (Trixie) oder kompatible Distributionen mit systemd
- X11 muss aktiv genutzt werden (Wayland wird nicht unterstützt)
- Paketabhängigkeiten:
  - `chromium-browser` oder `chromium`
  - `xdotool`, `xrandr`, `xprintidle`, `xset`
  - `curl`
  - `gsettings` (nur GNOME-Variante)
  - Optional: `nm-online` (NetworkManager) für schnellere Online-Erkennung

Beispiel (Debian/Ubuntu):

```bash
sudo apt update
sudo apt install chromium xdotool xrandr xprintidle xset curl gsettings-desktop-schemas
```

## Schnellstart

1. **Repository klonen**

    ```bash
    git clone https://github.com/langermi/chromium-multimonitor-kiosk.git
    cd chromium-multimonitor-kiosk
    ```

2. **Konfiguration anpassen**
    - `config.sh` bearbeiten (Zeitpläne, Logging, Refresh-Verhalten, Netzwerk-Timeouts, …)
    - `urls.ini` editieren (URL-Zuordnung je Monitor/Index)

3. **Skripte ausführbar machen**

    ```bash
    chmod +x startkiosk-gnome.sh startkiosk-lxde.sh
    ```

4. **Starten**
    - GNOME: `./startkiosk-gnome.sh`
    - LXDE: `./startkiosk-lxde.sh`

## Konfiguration

### `config.sh`

Die Konfigurationsdatei ist thematisch gegliedert. Wichtige Bereiche:

| Abschnitt | Wichtige Variablen | Beschreibung |
|-----------|-------------------|---------------|
| Desktop & Pfade | `DISPLAY`, `BASEDIR`, `WORKSPACES`, `URLS_INI`, `CHROMIUM_CONFIG` | Legt grundlegende Arbeitsverzeichnisse und das Ziel-Display fest. |
| Chromium-Laufzeit | `CHROMIUM_BIN`, `CHROMIUM_FLAGS` | Wählt den Chromium-Binary und zusätzliche Stabilitätsparameter. |
| Logging & Watchdog | `LOGDIR`, `LOG_FORMAT`, `LOG_TO_JOURNAL`, `MAX_LOG_SIZE`, `LOG_MAX_BACKUPS`, `LOG_DEBUG`, `CHECK_INTERVAL` | Kontrolliert Log-Ausgabe, Rotation und die Überwachungsintervalle. |
| Seiten-Refresh | `REFRESH_INACTIVITY_THRESHOLD`, `PAGE_REFRESH_INTERVAL`, `DISABLE_PAGE_REFRESH` | Definiert, wann Seiten automatisch aktualisiert werden bzw. deaktiviert den Mechanismus vollständig. |
| Netzwerk | `NETWORK_READY_TIMEOUT`, `NETWORK_READY_CHECK_INTERVAL`, `NETWORK_READY_CHECK_URL` | Verzögert den Start, bis ein definiertes Ziel erreicht wird (per `nm-online` oder HTTP-HEAD). |
| Energie & Sitzungssteuerung | `ENABLE_RESTART`, `RESTART_TIME`, `ENABLE_POWEROFF`, `POWEROFF_TIME`, `APPLY_POWER_SETTINGS` | Steuert zeitgesteuerte Neustarts/Shutdowns und Desktop-Schoner.
| URL-Defaults | `DEFAULT_URL`, `STRICT_URL_VALIDATION` | Fallback-URL sowie strikte Erreichbarkeitsprüfung aller Zielseiten. |

> 💡 Tipp: Für Testläufe ohne echten Neustart/Shutdown können die Umgebungsvariablen `TEST_REBOOT=1` bzw. `TEST_POWEROFF=1` gesetzt werden.

### `urls.ini`

Das INI-Format erlaubt URL-Zuweisung nach Namen (Monitor-ID) oder Index:

```ini
[urls]
default=https://intranet.example.org
DP-1=https://dashboards.example.org,refresh
HDMI-1=https://fallback.example.org,norefresh
index0=https://werbung.example.org
```

- Schlüssel ohne `index` beziehen sich auf Monitor-Namen, die `xrandr` liefert.
- `index<N>` ordnet URLs anhand der Reihenfolge aus `xrandr` zu.
- Optionen wie `norefresh` deaktivieren das automatische Aktualisieren für diesen Bildschirm.

### Weitere Ressourcen

- `config.sh` – zentrale Parameter (siehe oben)
- `startkiosk-gnome.sh` / `startkiosk-lxde.sh` – Startskripte mit Watchdog
- `urls.ini` – Monitor-zu-URL-Mapping
- `debianpreseed/` – automatisierte Installationsprofile (GNOME & LXDE)
- `helperscripts/` – ISO-Abbilder und Hinweise für vorkonfigurierte Installationen

## Betrieb & Automatisierung

### Manuelles Starten

```bash
# GNOME
./startkiosk-gnome.sh

# LXDE
./startkiosk-lxde.sh
```

Das Skript prüft zuerst Abhängigkeiten und Berechtigungen, wartet optional auf Netzwerk-Konnektivität und öffnet dann pro Monitor eine Vollbild-Chromium-App.

### Autostart via systemd (empfohlen)

1. **User-Service anlegen**

    ```bash
    mkdir -p ~/.config/systemd/user
    cat > ~/.config/systemd/user/kiosk.service <<'EOF'
    [Unit]
    Description=Chromium Multi-Monitor Kiosk
    After=graphical-session.target network-online.target
    Wants=graphical-session.target

    [Service]
    Type=exec
    Environment=DISPLAY=:0
    WorkingDirectory=%h/chromium-multimonitor-kiosk
    ExecStart=%h/chromium-multimonitor-kiosk/startkiosk-lxde.sh
    Restart=on-failure
    RestartSec=5

    [Install]
    WantedBy=graphical-session.target
    EOF
    ```

2. **Service aktivieren**

    ```bash
    systemctl --user daemon-reload
    systemctl --user enable --now kiosk.service
    ```

Der Debian-Preseed richtet diesen Service bereits automatisiert ein.

### Alternative Autostart-Mechanismen

- Grafische Autostart-Werkzeuge (z. B. `gnome-session-properties`)
- LXDE Autostart-Dateien (`~/.config/lxsession/LXDE/autostart`)
- Cron `@reboot`-Einträge (nur in Kombination mit gesetztem `DISPLAY` und laufendem X-Server empfohlen)

## Protokollierung & Wartung

- **Dateilogs:** liegen unter `logs/` (rotierende Tageslogs + komprimierte Historie)
- **Journald:** bei gesetztem `LOG_TO_JOURNAL=true` zusätzlich unter `journalctl --user -u kiosk`
- **Fehlerlogs:** separate Datei pro Lauf (`${LOG_TAG}-error-<timestamp>.log`)
- **Watchdog:** prüft im Intervall `CHECK_INTERVAL` auf hängende Chromium-Prozesse, erreichtes Refresh-Intervall, Inaktivität sowie geplante Neustarts/Shutdowns
- **Chromium-Workspaces:** pro Monitor eigener Profilordner unter `workspaces/`

### Aktualisierung des Deployments

```bash
cd ~/chromium-multimonitor-kiosk
git pull --ff-only
systemctl --user restart kiosk.service
```

## Automatisierte Installation (Preseed)

Im Ordner `debianpreseed/` stehen zwei Preseed-Profile bereit:

- `preseed-kiosk-debian13-minimal-gnome.cfg`
- `preseed-kiosk-debian13-minimal-lxde.cfg`

Sie erzeugen ein minimales Debian-13-System mit vorkonfiguriertem Benutzer `kiosk`, Autologin, vorinstallierten Abhängigkeiten, geklontem Repository, ausführbaren Skripten und einem aktivierten systemd-User-Service. Eventuelle Anpassungen (z. B. alternative URLs, zusätzliche Pakete) lassen sich direkt in den Preseed-Dateien vornehmen.

## Troubleshooting

| Problem | Ursache | Lösung |
|---------|---------|--------|
| Dienst startet, aber Chromium erscheint nicht | Netzwerk noch nicht verfügbar / kein Display | `NETWORK_READY_*` anpassen, sicherstellen, dass `DISPLAY=:0` erreichbar ist, ggf. `xhost +SI:localuser:kiosk` setzen |
| Geplanter Neustart findet nicht statt | Keine sudo-Rechte auf `reboot` | Überprüfe `/etc/sudoers.d/99_kiosk` oder `can_execute_reboot_or_poweroff`; ggf. NOPASSWD-Eintrag ergänzen |
| Seitenrefresh läuft nicht | Refresh global deaktiviert / Inaktivitätsschwelle nicht erreicht | `DISABLE_PAGE_REFRESH=false` setzen und `REFRESH_INACTIVITY_THRESHOLD` ≥ `PAGE_REFRESH_INTERVAL` konfigurieren |
| URLs schlagen fehl | `STRICT_URL_VALIDATION=true` bricht beim Start ab | URLs prüfen oder Option temporär auf `false` setzen |
| Logverzeichnis wächst schnell | Hohe Logfrequenz, Rotation greift nicht | `MAX_LOG_SIZE` und `LOG_MAX_BACKUPS` erhöhen oder `LOG_FORMAT=json` für kompaktere Einträge nutzen |

Weitere Hinweise findest du direkt in den Skripten (`log_debug`-Ausgaben aktivieren via `LOG_DEBUG=1`).

## Lizenz

Dieses Projekt steht unter der in `LICENCE` angegebenen Lizenz.
