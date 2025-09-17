#!/bin/bash

# Script zur Deaktivierung von Wayland und Erzwingung von X11
# Notwendig für das Kiosk-System, da xdotool unter Wayland nicht funktioniert

set -euo pipefail

# Logging-Funktion
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Deaktiviere Wayland und aktiviere X11..."

# GDM Konfiguration für Wayland-Deaktivierung
GDM_CUSTOM_CONF="/etc/gdm3/custom.conf"
if [[ -f "$GDM_CUSTOM_CONF" ]]; then
    log "Bearbeite GDM Konfiguration: $GDM_CUSTOM_CONF"
    
    # Backup erstellen
    sudo cp "$GDM_CUSTOM_CONF" "$GDM_CUSTOM_CONF.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Wayland deaktivieren
    if ! grep -q "WaylandEnable=false" "$GDM_CUSTOM_CONF"; then
        sudo sed -i '/^\[daemon\]/a WaylandEnable=false' "$GDM_CUSTOM_CONF"
        log "WaylandEnable=false zu $GDM_CUSTOM_CONF hinzugefügt"
    else
        log "WaylandEnable=false bereits in $GDM_CUSTOM_CONF vorhanden"
    fi
    
    # X11 als Standard erzwingen
    if ! grep -q "DefaultSession=gnome-xorg" "$GDM_CUSTOM_CONF"; then
        sudo sed -i '/^\[daemon\]/a DefaultSession=gnome-xorg' "$GDM_CUSTOM_CONF"
        log "DefaultSession=gnome-xorg zu $GDM_CUSTOM_CONF hinzugefügt"
    else
        log "DefaultSession=gnome-xorg bereits in $GDM_CUSTOM_CONF vorhanden"
    fi
else
    log "Warnung: $GDM_CUSTOM_CONF nicht gefunden. Erstelle neue Konfiguration..."
    sudo tee "$GDM_CUSTOM_CONF" > /dev/null << EOF
[daemon]
WaylandEnable=false
DefaultSession=gnome-xorg

[security]

[xdmcp]

[chooser]

[debug]
EOF
    log "Neue GDM Konfiguration erstellt"
fi

# Alternative: LIGHTDM Konfiguration (falls verwendet)
LIGHTDM_CONF="/etc/lightdm/lightdm.conf"
if [[ -f "$LIGHTDM_CONF" ]]; then
    log "LightDM erkannt. Bearbeite Konfiguration: $LIGHTDM_CONF"
    
    # Backup erstellen
    sudo cp "$LIGHTDM_CONF" "$LIGHTDM_CONF.backup.$(date +%Y%m%d_%H%M%S)"
    
    # X11 Session erzwingen
    if ! grep -q "user-session=gnome-xorg" "$LIGHTDM_CONF"; then
        sudo sed -i '/^\[Seat:\*\]/a user-session=gnome-xorg' "$LIGHTDM_CONF"
        log "user-session=gnome-xorg zu $LIGHTDM_CONF hinzugefügt"
    fi
fi

# Benutzer-spezifische Wayland-Deaktivierung
log "Setze Umgebungsvariablen für X11..."

# .profile bearbeiten
PROFILE_FILE="$HOME/.profile"
if [[ -f "$PROFILE_FILE" ]]; then
    if ! grep -q "export XDG_SESSION_TYPE=x11" "$PROFILE_FILE"; then
        echo "export XDG_SESSION_TYPE=x11" >> "$PROFILE_FILE"
        log "XDG_SESSION_TYPE=x11 zu $PROFILE_FILE hinzugefügt"
    fi
    if ! grep -q "export GDK_BACKEND=x11" "$PROFILE_FILE"; then
        echo "export GDK_BACKEND=x11" >> "$PROFILE_FILE"
        log "GDK_BACKEND=x11 zu $PROFILE_FILE hinzugefügt"
    fi
else
    tee "$PROFILE_FILE" > /dev/null << EOF
# X11 Session erzwingen
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
EOF
    log "Neue $PROFILE_FILE erstellt"
fi

# .xprofile für zusätzliche X11-Konfiguration
XPROFILE_FILE="$HOME/.xprofile"
tee "$XPROFILE_FILE" > /dev/null << 'EOF'
#!/bin/bash
# X11 Konfiguration für Kiosk-System

# Screensaver deaktivieren
xset s off
xset -dpms
xset s noblank

# Mauszeiger ausblenden nach Inaktivität
unclutter -idle 1 -root &

# DISPLAY exportieren
export DISPLAY=:0
EOF

chmod +x "$XPROFILE_FILE"
log ".xprofile erstellt"

log "Wayland-Deaktivierung abgeschlossen!"
log ""
log "WICHTIG: System muss neu gestartet werden, damit die Änderungen wirksam werden."
log "Nach dem Neustart sollte eine X11-Session verwendet werden."
log ""
log "Überprüfung nach Neustart mit: echo \$XDG_SESSION_TYPE (sollte 'x11' ausgeben)"