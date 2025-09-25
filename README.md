# Chromium Multi-Monitor Kiosk

Dieses Projekt bietet eine robuste und flexible Lösung zum Betreiben eines Kiosk-Systems mit Chromium auf mehreren Monitoren unter Linux. Es wurde für den dauerhaften Betrieb konzipiert und enthält Mechanismen zur Selbstheilung, Protokollierung und Energieverwaltung.

## Hauptmerkmale

- **Multi-Monitor-Unterstützung:** Weist verschiedenen Monitoren spezifische URLs zu.
- **Desktop-Umgebungen:** Vorkonfigurierte Skripte für GNOME (`startkiosk-gnome.sh`) und LXDE (`startkiosk-lxde.sh`).
- **Hohe Konfigurierbarkeit:** Zentrale Konfiguration über die Datei `config.sh`.
- **Robustheit:** Ein Watchdog-Mechanismus überwacht die Chromium-Prozesse und startet sie bei Bedarf neu.
- **Energieverwaltung:** Geplante, tägliche Neustarts und Herunterfahren des Systems.
- **Umfassende Protokollierung:** Detaillierte Logs in Dateien und optional im Systemd-Journal. Log-Rotation ist integriert.
- **Automatisierte Installation:** Enthält Debian-Preseed-Dateien zur einfachen Erstellung eines fertigen Kiosk-Systems.
- **Inaktivitäts-Erkennung:** Kann Seiten bei Inaktivität automatisch neu laden.

## Anforderungen

Stellen Sie sicher, dass die folgenden Abhängigkeiten auf dem System installiert sind:

- `chromium-browser` (oder `chromium`)
- `xdotool`
- `xrandr`
- `gsettings` (für die GNOME-Version)
- `curl`
- `xprintidle`

Das System muss eine **X11-Sitzung** verwenden, Wayland wird nicht unterstützt.

## Installation und Einrichtung

1.  **Repository klonen:**
    ```bash
    git clone <repository-url>
    cd chromium-multimonitor-kiosk
    ```

2.  **Konfiguration anpassen:**
    -   Öffnen Sie die Datei `config.sh` und passen Sie die Variablen nach Ihren Bedürfnissen an (z.B. `ENABLE_POWEROFF`, `RESTART_TIME`, etc.).
    -   Öffnen Sie die Datei `urls.ini`, um die URLs für die Monitore zu definieren.

3.  **Skript ausführbar machen:**
    ```bash
    chmod +x startkiosk-gnome.sh
    chmod +x startkiosk-lxde.sh
    ```

## Verwendung

Führen Sie das entsprechende Skript für Ihre Desktop-Umgebung aus:

**Für GNOME:**
```bash
./startkiosk-gnome.sh
```

**Für LXDE:**
```bash
./startkiosk-lxde.sh
```

### Autostart

Um das Kiosk-Skript automatisch beim Systemstart auszuführen, können Sie es in die Autostart-Konfiguration Ihrer Desktop-Umgebung aufnehmen (z.B. über `gnome-session-properties` oder durch einen Eintrag in `~/.config/autostart/`).

## Konfiguration

### `config.sh`

Diese Datei enthält die Hauptkonfiguration:

- `ENABLE_POWEROFF`/`POWEROFF_TIME`: Aktiviert und plant das tägliche Herunterfahren.
- `ENABLE_RESTART`/`RESTART_TIME`: Aktiviert und plant den täglichen Neustart.
- `CHECK_INTERVAL`: Intervall (in Sekunden), in dem der Watchdog die Chromium-Prozesse prüft.
- `LOG_FORMAT`: Legt das Log-Format fest (`text` oder `json`).
- `LOG_TO_JOURNAL`: Sendet Logs zusätzlich an `journald`.
- `CHROMIUM_FLAGS`: Startparameter für Chromium im Kiosk-Modus.

### `urls.ini`

In dieser Datei werden die URLs für die einzelnen Monitore festgelegt. Das Format ist einfach:

```ini
[urls]
DP-1=https://www.example.com
HDMI-1=https://www.another-site.org
```

Die Bezeichner (`DP-1`, `HDMI-1`) müssen den Namen der Monitore entsprechen, wie sie von `xrandr` ausgegeben werden.

## Protokollierung und Fehlerbehebung

Die Log-Dateien werden standardmäßig im Verzeichnis `logs` im Projektordner gespeichert. Fehler werden sowohl in die Konsole als auch in eine separate Fehler-Logdatei geschrieben, um die Fehlersuche zu erleichtern.

## Lizenz

Dieses Projekt steht unter der in der `LICENCE`-Datei angegebenen Lizenz.
