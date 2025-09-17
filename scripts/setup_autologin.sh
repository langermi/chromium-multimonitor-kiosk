#!/bin/bash

# Script zur Einrichtung des automatischen Logins für Kiosk-System
# Konfiguriert GDM oder LightDM für passwordloses Login

set -euo pipefail

# Logging-Funktion
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Benutzer ermitteln (falls nicht als Parameter übergeben)
TARGET_USER="${1:-$USER}"

log "Richte automatisches Login für Benutzer '$TARGET_USER' ein..."

# Prüfe ob Benutzer existiert
if ! id "$TARGET_USER" &>/dev/null; then
    log "Fehler: Benutzer '$TARGET_USER' existiert nicht!"
    exit 1
fi

# Display Manager erkennen
detect_display_manager() {
    if systemctl is-active --quiet gdm || systemctl is-active --quiet gdm3; then
        echo "gdm"
    elif systemctl is-active --quiet lightdm; then
        echo "lightdm"
    elif systemctl is-active --quiet sddm; then
        echo "sddm"
    else
        echo "unknown"
    fi
}

DISPLAY_MANAGER=$(detect_display_manager)
log "Erkannter Display Manager: $DISPLAY_MANAGER"

case "$DISPLAY_MANAGER" in
    "gdm")
        configure_gdm_autologin
        ;;
    "lightdm")
        configure_lightdm_autologin
        ;;
    "sddm")
        configure_sddm_autologin
        ;;
    *)
        log "Fehler: Unbekannter oder nicht unterstützter Display Manager!"
        log "Bitte manuell konfigurieren oder einen unterstützten Display Manager installieren."
        exit 1
        ;;
esac

# GDM Autologin konfigurieren
configure_gdm_autologin() {
    log "Konfiguriere GDM für automatisches Login..."
    
    GDM_CUSTOM_CONF="/etc/gdm3/custom.conf"
    
    # Prüfe ob Konfigurationsdatei existiert
    if [[ ! -f "$GDM_CUSTOM_CONF" ]]; then
        log "Erstelle neue GDM Konfigurationsdatei..."
        sudo tee "$GDM_CUSTOM_CONF" > /dev/null << EOF
[daemon]
[security]
[xdmcp]
[chooser]
[debug]
EOF
    fi
    
    # Backup erstellen
    sudo cp "$GDM_CUSTOM_CONF" "$GDM_CUSTOM_CONF.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Autologin konfigurieren
    log "Aktiviere automatisches Login für '$TARGET_USER'..."
    
    # AutomaticLoginEnable hinzufügen/aktualisieren
    if grep -q "AutomaticLoginEnable" "$GDM_CUSTOM_CONF"; then
        sudo sed -i "s/.*AutomaticLoginEnable.*/AutomaticLoginEnable=true/" "$GDM_CUSTOM_CONF"
    else
        sudo sed -i '/^\[daemon\]/a AutomaticLoginEnable=true' "$GDM_CUSTOM_CONF"
    fi
    
    # AutomaticLogin Benutzer hinzufügen/aktualisieren
    if grep -q "AutomaticLogin" "$GDM_CUSTOM_CONF" && ! grep -q "AutomaticLoginEnable" <<< "AutomaticLogin"; then
        sudo sed -i "s/.*AutomaticLogin=.*/AutomaticLogin=$TARGET_USER/" "$GDM_CUSTOM_CONF"
    else
        sudo sed -i "/AutomaticLoginEnable=true/a AutomaticLogin=$TARGET_USER" "$GDM_CUSTOM_CONF"
    fi
    
    log "GDM Autologin konfiguriert"
}

# LightDM Autologin konfigurieren
configure_lightdm_autologin() {
    log "Konfiguriere LightDM für automatisches Login..."
    
    LIGHTDM_CONF="/etc/lightdm/lightdm.conf"
    
    # Backup erstellen
    if [[ -f "$LIGHTDM_CONF" ]]; then
        sudo cp "$LIGHTDM_CONF" "$LIGHTDM_CONF.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Konfiguration erstellen/aktualisieren
    sudo tee "$LIGHTDM_CONF" > /dev/null << EOF
[Seat:*]
autologin-user=$TARGET_USER
autologin-user-timeout=0
autologin-session=gnome-xorg
user-session=gnome-xorg

[XDMCPServer]

[VNCServer]
EOF
    
    log "LightDM Autologin konfiguriert"
}

# SDDM Autologin konfigurieren
configure_sddm_autologin() {
    log "Konfiguriere SDDM für automatisches Login..."
    
    SDDM_CONF="/etc/sddm.conf"
    SDDM_CONF_DIR="/etc/sddm.conf.d"
    
    # Verwende Konfigurationsverzeichnis falls vorhanden
    if [[ -d "$SDDM_CONF_DIR" ]]; then
        SDDM_CONF="$SDDM_CONF_DIR/autologin.conf"
    fi
    
    # Backup erstellen falls Datei existiert
    if [[ -f "$SDDM_CONF" ]]; then
        sudo cp "$SDDM_CONF" "$SDDM_CONF.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    sudo tee "$SDDM_CONF" > /dev/null << EOF
[Autologin]
User=$TARGET_USER
Session=gnome-xorg.desktop

[General]
HaltCommand=/usr/bin/systemctl poweroff
RebootCommand=/usr/bin/systemctl reboot
EOF
    
    log "SDDM Autologin konfiguriert"
}

# Benutzer zur autologin-Gruppe hinzufügen (falls erforderlich)
log "Füge Benutzer zu relevanten Gruppen hinzu..."

# Gruppen die für Autologin hilfreich sein können
GROUPS=("autologin" "nopasswdlogin")

for group in "${GROUPS[@]}"; do
    if getent group "$group" >/dev/null 2>&1; then
        if ! groups "$TARGET_USER" | grep -q "$group"; then
            sudo usermod -a -G "$group" "$TARGET_USER"
            log "Benutzer '$TARGET_USER' zu Gruppe '$group' hinzugefügt"
        else
            log "Benutzer '$TARGET_USER' bereits in Gruppe '$group'"
        fi
    fi
done

# Zusätzliche Konfigurationen für Kiosk-System
log "Konfiguriere zusätzliche Einstellungen für Kiosk-Betrieb..."

# AccountsService Konfiguration für automatisches Login
ACCOUNTS_USER_FILE="/var/lib/AccountsService/users/$TARGET_USER"
if [[ -f "$ACCOUNTS_USER_FILE" ]]; then
    sudo cp "$ACCOUNTS_USER_FILE" "$ACCOUNTS_USER_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    
    # AutomaticLogin aktivieren
    if ! sudo grep -q "AutomaticLogin=true" "$ACCOUNTS_USER_FILE"; then
        echo "AutomaticLogin=true" | sudo tee -a "$ACCOUNTS_USER_FILE" > /dev/null
        log "AutomaticLogin=true zu AccountsService hinzugefügt"
    fi
    
    # X11 Session erzwingen
    if ! sudo grep -q "XSession=gnome-xorg" "$ACCOUNTS_USER_FILE"; then
        echo "XSession=gnome-xorg" | sudo tee -a "$ACCOUNTS_USER_FILE" > /dev/null
        log "XSession=gnome-xorg zu AccountsService hinzugefügt"
    fi
fi

# Polkit-Regel für passwordlose Aktionen erstellen
log "Erstelle Polkit-Regeln für Kiosk-Benutzer..."

POLKIT_RULE_FILE="/etc/polkit-1/rules.d/50-kiosk-autologin.rules"
sudo tee "$POLKIT_RULE_FILE" > /dev/null << EOF
// Polkit-Regeln für Kiosk-System
// Erlaubt dem Kiosk-Benutzer bestimmte Aktionen ohne Passwort

polkit.addRule(function(action, subject) {
    if (subject.user == "$TARGET_USER") {
        // Neustart und Herunterfahren erlauben
        if (action.id == "org.freedesktop.systemd1.manage-units" ||
            action.id == "org.freedesktop.login1.reboot" ||
            action.id == "org.freedesktop.login1.power-off") {
            return polkit.Result.YES;
        }
        
        // Netzwerk-Manager Aktionen
        if (action.id.indexOf("org.freedesktop.NetworkManager") == 0) {
            return polkit.Result.YES;
        }
    }
});
EOF

log "Polkit-Regeln erstellt"

log ""
log "Automatisches Login erfolgreich konfiguriert!"
log "Benutzer: $TARGET_USER"
log "Display Manager: $DISPLAY_MANAGER"
log ""
log "WICHTIG: System muss neu gestartet werden, damit die Änderungen wirksam werden."
log "Nach dem Neustart sollte sich '$TARGET_USER' automatisch anmelden."