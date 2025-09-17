Anleitung: cloud-init für Debian 13 (Kiosk)

Datei: `cloud-init/kiosk-debian13.yaml`

Kurz: Diese cloud-init user-data richtet auf einem Debian 13 Image einen Benutzer `kiosk` ein, installiert die nötigen Pakete, setzt GDM Autologin, trägt die nötige sudoers-Zeile für Neustart/Herunterfahren ein, klont das Kiosk-Repository in `/home/kiosk/chromium-multimonitor-kiosk` und aktiviert einen systemd --user Dienst, der `startkiosk.sh` startet.

Wichtig / Hinweise

- Standardpasswort ist in der cloud-init aus Gründen der Demo `kioskpass`. Bitte sofort nach dem Erststart ändern.
- Die Datei fügt `/etc/sudoers.d/kiosk-nopasswd` hinzu mit der Zeile
  `kiosk ALL=(ALL) NOPASSWD: /bin/systemctl reboot, /bin/systemctl poweroff` — das entspricht dem Wunsch in der README des Repos.
- GNOME Keyring: Autologin führt oft dazu, dass der GNOME Keyring verschlüsselt ist und Anwendungen nach Passwörtern fragen. In der cloud-init wird ein pragmatischer Workaround angewendet: die standardmäßigen gnome-keyring autostart Desktop-Einträge werden via `~/.config/autostart` deaktiviert, so dass Schlüsselring-Komponenten nicht automatisch starten. Das ist einfach, funktioniert für reinen Kiosk-Betrieb, hat aber Sicherheitsimplikationen (kein Passwort-Schutz für gespeicherte Geheimnisse).

Alternativen zum Keyring-Workaround

- Provisioniere ein leeres oder bekanntes Passwort für den Keyring und synchronisiere es mit dem Nutzerpasswort (komplizierter während cloud-init). Tools wie `secret-tool`/`gnome-keyring` können verwendet werden, aber meist ist ein manuelles Setzen oder ein PAM-Binding nötig.
- Verwende keine GNOME Keyring-abhängigen Funktionen im Kiosk oder speichere Geheimnisse außerhalb des Keyrings.

Wie anwenden

1. Platziere `kiosk-debian13.yaml` als cloud-init user-data beim Erzeugen einer VM (z.B. Proxmox, OpenStack, cloud-images). In Proxmox: setze 'user-data' auf den Inhalt der Datei.
2. Starte die VM; cloud-init installiert die Pakete, legt den User an und aktiviert autologin.
3. Nach dem ersten Boot: melde dich nicht interaktiv an; die GDM-Autologin startet die grafische Sitzung und `startkiosk.sh` wird per systemd --user gestartet.

Verwendung von einem USB-Stick / minimalen Debian 13 netinst
--------------------------------------------------------

Die cloud-init user-data wurde ursprünglich für Cloud-Images entworfen. Du kannst sie aber auch beim Installieren von Debian 13 von einem minimalen netinst-ISO bzw. von einem USB-Stick verwenden. Hier zwei gebräuchliche Optionen:

A) Empfohlen: NoCloud (CIDATA) auf separatem USB-Stick

1. Formatiere einen USB-Stick FAT32 und lege zwei Dateien darauf:
   - `user-data` (der Inhalt von `cloud-init/kiosk-debian13.yaml`)
   - `meta-data` mit mindestens:

```
instance-id: kiosk-001
local-hostname: kiosk
```

2. Stecke den USB-Stick neben dem Debian netinst-Installationsmedium in die Maschine. Moderne Debian-Installer erkennen das NoCloud/CIDATA Medium, und cloud-init wird nach dem ersten Boot die user-data beim ersten Start anwenden.

Hinweise:
- Stelle sicher, dass der USB-Stick als `/dev/sdX` verfügbar ist — bei einigen Images muss der Stick an einem bestimmten Port stecken.
- Manche Installationsumgebungen entfernen externe Laufwerke nach der Installation; falls das passiert, verwende die netinst 'late-commands' Methode (unten).

B) Alternative: Debian netinst 'autoinstall' / late-commands

Wenn du die klassische Debian 13 autoinstall Methode benutzt, kannst du während der Installation ein kleines Script ausführen lassen, das die cloud-init user-data auf das fertige System kopiert und cloud-init dort auslöst.

Beispiel für `late-commands` in der autoinstall config:

```
late-commands:
  - curtin in-target --target=/target /bin/bash -c "mkdir -p /target/etc/cloud && cp /cdrom/user-data /target/etc/cloud/user-data || true"
  - curtin in-target --target=/target /bin/bash -c "chroot /target systemctl enable systemd-networkd || true"
```

Oder: boote das frisch installierte System einmal mit dem USB-Stick eingesteckt und kopiere dann per `late-commands` die Datei in `/target/etc/cloud/`.

Praxis-Tipps
- Teste zuerst in einer VM (z.B. QEMU/VirtualBox) bevor du physische Hardware bedienst.
- Entferne `ssh_pwauth: True` und kopiere stattdessen deinen öffentlichen SSH-Key in `/home/kiosk/.ssh/authorized_keys` in der cloud-init, wenn du SSH-Only Zugang bevorzugst.
- Nach dem ersten Boot: überprüfe `sudo journalctl -b` und `cloud-init.log` in `/var/log/cloud-init.log` bzw. `/var/log/cloud-init-output.log` auf Fehler.

Beispiel: USB NoCloud erstellen (macOS / Linux)

```
# Partitioniere USB als FAT32, mounte /media/cidata und kopiere Dateien
mkdir -p /tmp/cidata
echo "instance-id: kiosk-001" > /tmp/cidata/meta-data
cp cloud-init/kiosk-debian13.yaml /tmp/cidata/user-data
# dann mit dd das ISO schreiben (oder FAT32-USB mit den Dateien befüllen)
```

Sicherheit

- Der sudoers-Eintrag erlaubt Neustart/Poweroff ohne Passwort. Stelle sicher, dass der Kiosk-User keine weiteren Shell-Zugriffsberechtigungen erhält, oder schränke sudo weiter ein, falls nötig.
- Entferne das Defaultpasswort und konfiguriere SSH-Schlüssel für direkten Zugang falls nötig.
