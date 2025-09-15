# Multi-monitor kiosk system with Chromium

Dieses Bash-basierte Kiosk-System startet pro erkanntem Monitor eine eigene Chromium-Instanz im Vollbildmodus. URLs können global und monitor-spezifisch gesteuert werden, Workspaces werden je Monitor isoliert, Logs rotieren automatisch, und ein Watchdog startet abgestürzte Instanzen neu.

---

## Überblick

- **Automatische Monitorerkennung:** Liest Auflösung, Position und Rotation per `xrandr` aus.
- **URL-Zuweisung pro Monitor:** Konfiguration über `urls.ini` via Monitorname oder Index.
- **Vollbild und Positionierung:** Steuert Fenster mit `xdotool` gezielt auf jeden Bildschirm.
- **Stabile Laufzeit:** Watchdog überwacht Prozesse, bereinigt Workspaces und startet neu.
- **Saubere Logs:** Getrennte Logs für Ablauf und Fehler, mit täglicher Komprimierung und Aufbewahrung.
- **Testmodus:** Startparameter `--test` zum Trockenlauf ohne Chromium.
- **Chromium Konfiguration:** Alle Chromium einstellungen werden aus dem default Profil entnommen. So muss nicht jede instanz einzeln konfiguriert werden

---

## Projektstruktur und voraussetzungen

### Projektstruktur

```
kiosk-system/
├── config.sh          # Basiskonfiguration, Pfade, Konstanten
├── startkiosk.sh      # Hauptskript (Erkennung, Start, Watchdog)
├── urls.ini           # URL-Zuweisungen pro Monitor
└── logs/              # Logs (automatisch erstellt und rotiert)
```

### Voraussetzungen

- **Shell und Umgebung:** bash, X11 Session (kein Wayland)
- **Browser:** chromium oder chromium-browser
- **Tools:** xdotool, xrandr, gsettings
- **Desktop:** GNOME empfohlen; Hinweis auf Extension „No overview at startup“

> Hinweis: Unter Wayland funktioniert die Fenstersteuerung mit xdotool nicht. Bitte eine Xorg-Session verwenden.

---

## Installation und konfiguration

### Installation

1. **Repository klonen**
   ```bash
   git clone https://github.com/<dein-benutzername>/kiosk-system.git
   cd kiosk-system
   ```
2. **Skripte ausführbar machen**
   ```bash
   chmod +x startkiosk.sh config.sh
   ```

### Konfiguration in config.sh

- **Display und Pfade:**  
  ```bash
  export DISPLAY=:0
  BASEDIR="$HOME/kiosk-system"
  LOGDIR="$BASEDIR/logs"
  WORKSPACES="$BASEDIR/workspaces"
  ```
- **Chromium-Binary und Profilpfad:**  
  ```bash
  CHROMIUM_BIN="$(command -v chromium-browser || command -v chromium)"
  CHROMIUM_CONFIG="$HOME/.config/chromium"
  ```
- **Logging und Watchdog:**  
  ```bash
  MAX_LOGS=7
  CHECK_INTERVAL=10
  ```
- **Fallback-URL:**  
  ```bash
  DEFAULT_URL="https://example.com"
  ```

### Konfiguration in urls.ini

- **Standard-URL für alle Monitore**
  ```ini
  default=https://google.at
  ```
- **Monitor-spezifische Zuordnung per Name**  
  Die Namen kommen aus `xrandr` (in Kleinbuchstaben verwenden):
  ```ini
  displayport-0=https://www.bing.com
  displayport-1=https://www.duckduckgo.com
  ```
- **Alternative Zuordnung per Index**  
  Wenn keine namensbasierte URL existiert, wird der Index der Array-Reihenfolge aus `xrandr` verwendet:
  ```ini
  index0=https://example.org
  index1=https://example.net
  ```
- **Auflösungsreihenfolge prüfen**  
  Mit `xrandr --query` siehst du die Monitor-Namen wie `HDMI-1`, `DP-1`, `DisplayPort-0`. Diese bitte exakt (in Kleinbuchstaben) in `urls.ini` verwenden.

---

## Nutzung und verhalten

### Starten

- **Normaler Start**
  ```bash
  ./startkiosk.sh
  ```
- **Testmodus (ohne Chromium-Start)**
  ```bash
  ./startkiosk.sh --test
  ```

### Laufzeitverhalten

- **Monitorhandling:**  
  Für jeden erkannten Monitor wird ein Workspace unter `workspaces/<monitorname>/` angelegt. Optional vorhandene Chromium-Profile aus `~/.config/chromium` werden initial hineinkopiert.
- **Fenstersteuerung:**  
  Das Fenster wird exakt auf die Monitorposition verschoben, in der Größe angepasst und mit `F11` in den Vollbildmodus gesetzt.
- **Watchdog:**  
  Die PIDs werden überwacht. Beim Ende eines Prozesses werden Workspace neu initialisiert und die Instanz neu gestartet. Die Anzahl der Neustarts je Monitor wird mitgezählt.
- **Logging:**  
  Ablauf-Log: `logs/kiosk-start-YYYY-MM-DD_HH-MM-SS.log`  
  Fehler-Log: `logs/kiosk-error-YYYY-MM-DD_HH-MM-SS.log`  
  Ältere Logs werden täglich komprimiert und nach `MAX_LOGS` Archiven aufgeräumt.

---

## Autostart und fehlerbehebung

### Autostart als systemd User Service

1. **Service-Datei anlegen**
   ```ini
   # ~/.config/systemd/user/kiosk.service
   [Unit]
   Description=Chromium Kiosk
   After=graphical-session.target

   [Service]
   Type=simple
   Environment=DISPLAY=:0
   WorkingDirectory=%h/kiosk-system
   ExecStart=%h/kiosk-system/startkiosk.sh
   Restart=always
   RestartSec=10

   [Install]
   WantedBy=default.target
   ```
2. **Aktivieren**
   ```bash
   systemctl --user daemon-reload
   systemctl --user enable --now kiosk.service
   ```

### Autostart als .desktop-Datei (GNOME)

```ini
# ~/.config/autostart/kiosk.desktop
[Desktop Entry]
Type=Application
Name=Kiosk
Exec=/bin/bash -lc "$HOME/kiosk-system/startkiosk.sh"
X-GNOME-Autostart-enabled=true
```

### Häufige probleme

- **Chromium startet nicht:**  
  Prüfe `CHROMIUM_BIN` in `config.sh` und ob `chromium` oder `chromium-browser` installiert ist.
- **Fenster bewegen sich nicht / kein Vollbild:**  
  Stelle sicher, dass du eine Xorg-Session nutzt und `xdotool` installiert ist.
- **Gnome-Übersicht stört:**  
  Aktiviere die Extension „No overview at startup“ oder deaktiviere die Übersicht per GNOME-Tweak-Tool.
- **Monitornamen stimmen nicht:**  
  Mit `xrandr --query` prüfen und Namen in `urls.ini` exakt in Kleinbuchstaben übernehmen.
- **Berechtigungen/Dateien:**  
  Existiert `logs/`? Skripte ausführbar? Schreibrechte im HOME-Verzeichnis vorhanden?

---

## Hinweise und lizenz

- **Sicherheit:**  
  Workspaces enthalten Browserdaten der jeweiligen Instanzen. Plane Berechtigungen und regelmäßige Bereinigung nach Bedarf ein.
- **Locale/Eingabe:**  
  Der Übersetzer und Crashed-Bubbles werden in den Chromium-Preferences unterdrückt, um einen unterbrechungsfreien Betrieb zu gewährleisten.
- **Erweiterungen:**  
  Eigene Policies/Flags kannst du in `start_chromium()` ergänzen.
