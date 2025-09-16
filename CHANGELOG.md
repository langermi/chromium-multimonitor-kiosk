# Changelog

## Unreleased

- Verbesserungen am Logging
  - Einheitliches tägliches Logfile (`kiosk-YYYY-MM-DD.log`)
  - Größenbasierte Log-Rotation mit `MAX_LOG_SIZE` und `LOG_MAX_BACKUPS`
  - Optionales JSON-Logformat (`LOG_FORMAT=json`)
  - Optionales Forwarding an systemd/journald (`LOG_TO_JOURNAL=true`, `LOG_TAG`)
  - Farbige Konsolenausgabe nach Schweregrad (INFO/WARN/ERROR/DEBUG)
  - Debug-Level via `LOG_DEBUG=1`
- Robustere Zeit-Trigger für Neustart/Poweroff (verpasstes Triggern bei großen `CHECK_INTERVAL` vermeiden)
- Aligning der Refresh-Timer nach einem Refresh (verhindert Drift)
- Validierung der `RESTART_TIME` und `POWEROFF_TIME` Formate
- Berechtigungsprüfung für Neustart/Poweroff (prüft `sudo -n` und `systemctl`-Verfügbarkeit)
- Diverse Kommentar- und Dokumentationsverbesserungen

- README synchronisiert mit `startkiosk.sh` / `config.sh` / `urls.ini`:
  - README jetzt enthält die canonical defaults aus `config.sh` (Pfad-, Logging- und Timer-Defaults)
  - Ausführliche Kurzdokumentation der wichtigsten Skriptfunktionen hinzugefügt (z. B. `start_chromium`, `validate_urls`, `check_prereqs`, `set_and_verify_gsetting`, `can_execute_reboot_or_poweroff`, `rotate_by_size`, Watchdog-Loop)
  - Logging-Verhalten (per-run logs, tägliches Log, size-basierte Rotation, JSON-Format, journald-Forwarding) dokumentiert
  - `urls.ini`-Option `norefresh` dokumentiert und Hinweis, dass Monitor-Namen kleingeschrieben werden
  - Klarstellung des Workspace-Verhaltens: bei Neustart/Crash wird das Workspace-Verzeichnis gelöscht und ggf. mit `$CHROMIUM_CONFIG` neu befüllt (Hinweis auf Datenschutz)
  - Widersprüchliche Lizenzformulierung in README bereinigt: `LICENCE` ist die maßgebliche Quelle
