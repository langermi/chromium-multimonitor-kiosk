# Vereinfachte Preseed-Konfiguration für Debian 13 Kiosk

## Problem gelöst

Die ursprüngliche preseed-Konfiguration hatte ein komplexes `early_command` Skript, das im Debian-Installer-Kontext Fehler verursachte.

## Lösung

Die neue `preseed-kiosk-debian13.cfg` verwendet **keine komplexen Skripte** mehr:

- ❌ **Entfernt**: Komplexes `early_command` Skript
- ❌ **Entfernt**: Benutzerdefinierte Partitionierungs-Rezepte  
- ✅ **Hinzugefügt**: Standard-Debian-Partitionierung
- ✅ **Hinzugefügt**: Automatische Disk-Auswahl durch den Installer

## So funktioniert es jetzt

1. **Automatische Erkennung**: Der Debian-Installer erkennt automatisch alle verfügbaren Festplatten

2. **Standard-Auswahl**: Der Installer zeigt die Standard-Partitionierungs-Dialoge an, wo Sie:
   - Die Ziel-Festplatte auswählen können
   - Die Partitionierungsmethode wählen können
   - Bestätigen können, dass die Festplatte gelöscht werden soll

3. **Automatische Installation**: Nach der Disk-Auswahl läuft die Installation vollautomatisch ab

## Vorteile der neuen Lösung

- ✅ **Keine Skript-Fehler**: Verwendet nur Standard-Debian-Mechanismen
- ✅ **Benutzerfreundlich**: Standard-GUI-Dialoge statt Kommandozeilen-Eingabe
- ✅ **Zuverlässig**: Bewährte Debian-Partitionierungslogik
- ✅ **Flexibel**: Unterstützt alle Festplatten-Typen (SATA, NVMe, USB)

## Was der Benutzer sieht

Der Debian-Installer zeigt automatisch einen Dialog wie:

```
Partitionierungsmethode:
○ Geführt - verwende ganze Festplatte
○ Geführt - verwende ganze Festplatte mit LVM
○ Geführt - verwende ganze Festplatte mit verschlüsseltem LVM  
○ Manuell
```

Danach folgt die Festplatten-Auswahl:

```
Festplatte für Partitionierung auswählen:
○ SCSI1 (0,0,0) (sda) - 500.0 GB ATA SAMSUNG SSD
○ SCSI2 (0,0,0) (sdb) - 1.0 TB NVMe INTEL SSD
```

## Backup-Dateien

- `preseed-kiosk-debian13.cfg.backup`: Ursprüngliche Version mit komplexem Skript
- `preseed-kiosk-debian13-complex.cfg.backup`: Zwischenversion mit vereinfachtem Skript