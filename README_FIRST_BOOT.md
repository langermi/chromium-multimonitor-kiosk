First-boot helper
=================

Dieses Repository enthält ein optionales One-time First-Boot Skript und eine systemd
Service-Unit, die beim ersten Start des frisch installierten Systems ausgeführt
wird, um user-spezifische Aktionen durchzuführen (Repo klonen, Berechtigungen
setzen, user-systemd unit vorbereiten). Das ist robuster als die Ausführung
aller Aktionen während der `preseed`-Phase.

Installations-Beispiel (preseed/late_command):

    in-target /bin/bash -c "install -m 0755 /tmp/kiosk-first-boot.sh /usr/local/bin/kiosk-first-boot.sh || true" && \
    in-target /bin/bash -c "install -m 0644 /tmp/kiosk-firstboot.service /etc/systemd/system/kiosk-firstboot.service || true" && \
    in-target /bin/bash -c "systemctl enable kiosk-firstboot.service || true"

Hinweis: Kopiere die Dateien (kiosk-first-boot.sh und kiosk-firstboot.service)
während der Installation in das Ziel (z.B. `/target/tmp/...`) und führe die
obenstehenden Befehle via `late_command` aus. Die Service-Unit startet das Skript
als root beim nächsten Boot; das Skript deaktiviert die Unit am Ende automatisch.
