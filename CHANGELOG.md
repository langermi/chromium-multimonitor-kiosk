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
