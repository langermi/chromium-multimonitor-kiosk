# Verwendung des Preseed-Files für Debian 13 netinst

Diese Anleitung beschreibt, wie du das Preseed-File `preseed-kiosk-debian13.cfg` (Deutsch, Locale `de_AT.UTF-8`) aus diesem Repository für eine automatisierte Debian 13 netinst-Installation verwendest, sowie empfohlene Anpassungen und Prüfschritte.

## Was das Preseed macht
- Legt Sprache/Locale (`de_AT.UTF-8`) und Keyboard (`de`) fest
- Partitioniert die gesamte Platte im "atomic"-Modus (ein Root-Ext4 auf `/dev/sda`)
- Legt den Benutzer `kiosk` mit dem Passwort `kioskpass` an (Standard: Klartext)
- Installiert zusätzliche Pakete (u. a. `gdm3`, `chromium`, `git`, `xserver-xorg`)
- Führt ein `late_command` aus, das u. a. die folgenden Aktionen durchführt:
  - Erstellt `/etc/sudoers.d/kiosk-nopasswd`
  - Legt `/etc/gdm3/daemon.conf.d/99_kiosk.conf` (Autologin für `kiosk`) an
  - Legt mehrere `~/.config/autostart/*.desktop`-Dateien an, die GNOME Keyring deaktivieren
  - Klont das Repo nach `/home/kiosk/chromium-multimonitor-kiosk` und setzt Berechtigungen
  - Versucht, das Skript `scripts/install_systemd_user_service.sh` als `kiosk` auszuführen (best-effort)
  - Kopiert die GNOME-Erweiterung `no-overview@fthx` systemweit (best-effort)

## Sicherheitshinweise
- Das Preseed enthält standardmäßig ein Klartext-Passwort (`kioskpass`). Das ist nur für Tests gedacht. Setze nach der Installation ein sicheres Passwort.
- Alternativ kannst du einen bereits gehashten Passwort-String (crypted) verwenden. Anleitung weiter unten.

## Zwei Möglichkeiten, das Preseed bereitzustellen

1) Preseed in die ISO einbinden (offline)

  - Mount die netinst-ISO und kopiere ihren Inhalt in ein temporäres Verzeichnis:

    ```bash
    mkdir /tmp/iso && sudo mount -o loop debian-13-netinst.iso /tmp/iso
    mkdir /tmp/iso-tree && rsync -a /tmp/iso/ /tmp/iso-tree/
    sudo umount /tmp/iso
    ```

  - Lege das Preseed-File unter `/tmp/iso-tree/preseed/preseed-kiosk-debian13.cfg` ab.
  - Passe (falls nötig) die Boot-Config (`/tmp/iso-tree/isolinux/txt.cfg` bzw. EFI-Config) an, damit beim Booten der Installer automatisch das Preseed lädt, z. B. durch Hinzufügen von `file=/cdrom/preseed/preseed-kiosk-debian13.cfg` oder `preseed/file=/cdrom/preseed/preseed-kiosk-debian13.cfg` zu den Kernel-Parametern.
  - Repacke die ISO (z. B. mit `genisoimage`/`xorriso`) und teste die ISO in einer VM.

2) Preseed per HTTP ausliefern (empfohlen für schnelle Tests)

  - Starte einen einfachen HTTP-Server im Verzeichnis mit `preseed-kiosk-debian13.cfg`:

    ```bash
    python3 -m http.server 8000
    ```

  - Boote das netinst-Medium und füge beim Booten die Kernel-Option hinzu:

    preseed/url=http://<dein-host>:8000/preseed-kiosk-debian13.cfg DEBCONF_FRONTEND=text

  - Damit liest der Installer das Preseed per HTTP.

## Passwort-Hash statt Klartext (optional, empfohlen)
1) Erzeuge auf deinem Host einen verschlüsselten Passwort-Hash (als root oder mit `sudo`):

  ```bash
  mkpasswd -m sha-512
  # oder (falls mkpasswd nicht vorhanden):
  python3 -c "import crypt, getpass; print(crypt.crypt(getpass.getpass(), crypt.mksalt(crypt.METHOD_SHA512)))"
  ```

2) Ersetze in `preseed-kiosk-debian13.cfg` die beiden Zeilen

  ```text
  d-i passwd/user-password password kioskpass
  d-i passwd/user-password-again password kioskpass
  ```

  durch

  ```text
  d-i passwd/user-password-crypted password <HASH>
  ```

  wobei `<HASH>` der mit `mkpasswd` / `crypt` erzeugte Hash ist.

Hinweis: Wenn du `passwd/user-password-crypted` benutzt, entferne die Klartext-Variablen.

## Spezielle Hinweise zum `late_command`
- Einige der Befehle (z. B. `systemctl --user` oder `gsettings`) brauchen eine echte Benutzer-Sitzung; sie sind als best-effort implementiert und mit `|| true` versehen.
- Das Skript `scripts/install_systemd_user_service.sh` wird versucht als `kiosk` auszuführen. Falls das in der chroot-Umgebung scheitert, kannst du es nach dem ersten Boot manuell ausführen:

```bash
sudo -u kiosk bash -lc '/home/kiosk/chromium-multimonitor-kiosk/scripts/install_systemd_user_service.sh'
```

## Test-Checklist (VM)
1. Installation mit dem Preseed durchführen (ISO oder HTTP).
2. Nach dem ersten Boot prüfen:
  - `id kiosk` existiert
  - `/etc/sudoers.d/kiosk-nopasswd` ist vorhanden und hat Modus 0440
  - `/etc/gdm3/daemon.conf.d/99_kiosk.conf` enthält `AutomaticLogin=kiosk` und `WaylandEnable=false`
  - Repo ist unter `/home/kiosk/chromium-multimonitor-kiosk` geklont
  - Scripts in `/home/kiosk/chromium-multimonitor-kiosk` sind ausführbar
3. Optional: Melde dich als `kiosk` an (lokal/SSH) und führe `systemctl --user status` aus, um user Units zu prüfen.

## Anpassungen, die du wahrscheinlich machen willst
- Passwort: Unbedingt anpassen (siehe Passwort-Hash oben).
- Partitionierung: Wenn du mehrere Disks/Partitionen brauchst, passe die `partman-auto/expert_recipe` an.
- Pakete: Prüfe noch einmal, ob alle Paketnamen in `pkgsel/include` auf Debian 13 verfügbar sind (besonders GUI/Chromium-Pakete können je nach Mirror abweichen).

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
