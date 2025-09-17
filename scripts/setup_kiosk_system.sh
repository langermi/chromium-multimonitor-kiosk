#!/bin/bash

# Kiosk System Setup Script
# Automatisiert die Konfiguration für ein Multi-Monitor Chromium Kiosk System
# - Deaktiviert Wayland und erzwingt X11
# - Installiert GNOME Extension "No overview at startup"
# - Richtet automatisches Login ein

set -euo pipefail

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging-Funktion mit Farben
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✓${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠${NC} $1"
}

# Script-Verzeichnis ermitteln
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Banner
echo -e "${BLUE}"
cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║                    KIOSK SYSTEM SETUP                       ║
║          Multi-Monitor Chromium Kiosk Configuration         ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Parameter
TARGET_USER="${1:-$USER}"
SKIP_REBOOT="${2:-false}"

log "Setup für Benutzer: $TARGET_USER"
log "Basis-Verzeichnis: $BASE_DIR"

# Voraussetzungen prüfen
check_prerequisites() {
    log "Prüfe Voraussetzungen..."
    
    local missing_deps=()
    
    # Benötigte Pakete
    local required_packages=(
        "curl" "unzip" "xdotool" "xrandr" "gsettings" 
        "gnome-shell" "gnome-shell-extensions" "python3"
    )
    
    for package in "${required_packages[@]}"; do
        if ! command -v "$package" &> /dev/null; then
            missing_deps+=("$package")
        fi
    done
    
    # Chromium prüfen
    if ! command -v chromium &> /dev/null && ! command -v chromium-browser &> /dev/null; then
        missing_deps+=("chromium oder chromium-browser")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Fehlende Abhängigkeiten: ${missing_deps[*]}"
        log "Installiere fehlende Pakete mit:"
        log "sudo apt update && sudo apt install -y ${missing_deps[*]}"
        return 1
    fi
    
    # Prüfe GNOME Session
    if [[ "$XDG_CURRENT_DESKTOP" != *"GNOME"* ]]; then
        log_warning "Nicht in einer GNOME Session. Einige Features funktionieren möglicherweise nicht korrekt."
    fi
    
    # Prüfe sudo-Berechtigung
    if ! sudo -v &> /dev/null; then
        log_error "Sudo-Berechtigung erforderlich für Systemkonfiguration"
        return 1
    fi
    
    log_success "Alle Voraussetzungen erfüllt"
    return 0
}

# Backup-Funktion
create_backup() {
    local backup_dir="$BASE_DIR/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    log "Erstelle Backup in: $backup_dir"
    
    # Wichtige Konfigurationsdateien sichern
    local files_to_backup=(
        "/etc/gdm3/custom.conf"
        "/etc/lightdm/lightdm.conf"
        "$HOME/.profile"
        "$HOME/.xprofile"
    )
    
    for file in "${files_to_backup[@]}"; do
        if [[ -f "$file" ]]; then
            sudo cp "$file" "$backup_dir/" 2>/dev/null || cp "$file" "$backup_dir/" 2>/dev/null || true
            log "Backup erstellt: $(basename "$file")"
        fi
    done
    
    echo "$backup_dir" > "$BASE_DIR/.last_backup"
    log_success "Backup abgeschlossen"
}

# Wayland deaktivieren
disable_wayland() {
    log "Schritt 1/3: Deaktiviere Wayland und aktiviere X11..."
    
    if [[ -x "$SCRIPT_DIR/disable_wayland.sh" ]]; then
        "$SCRIPT_DIR/disable_wayland.sh"
        log_success "Wayland erfolgreich deaktiviert"
    else
        log_error "Script nicht gefunden: $SCRIPT_DIR/disable_wayland.sh"
        return 1
    fi
}

# GNOME Extension installieren
install_gnome_extension() {
    log "Schritt 2/3: Installiere GNOME Extension 'No overview at startup'..."
    
    if [[ -x "$SCRIPT_DIR/install_gnome_extension.sh" ]]; then
        "$SCRIPT_DIR/install_gnome_extension.sh"
        log_success "GNOME Extension erfolgreich installiert"
    else
        log_error "Script nicht gefunden: $SCRIPT_DIR/install_gnome_extension.sh"
        return 1
    fi
}

# Autologin einrichten
setup_autologin() {
    log "Schritt 3/3: Richte automatisches Login ein..."
    
    if [[ -x "$SCRIPT_DIR/setup_autologin.sh" ]]; then
        "$SCRIPT_DIR/setup_autologin.sh" "$TARGET_USER"
        log_success "Automatisches Login erfolgreich eingerichtet"
    else
        log_error "Script nicht gefunden: $SCRIPT_DIR/setup_autologin.sh"
        return 1
    fi
}

# Zusätzliche Kiosk-Konfigurationen
configure_kiosk_settings() {
    log "Konfiguriere zusätzliche Kiosk-Einstellungen..."
    
    # GNOME Einstellungen für Kiosk-Betrieb
    log "Setze GNOME Einstellungen..."
    
    # Screensaver deaktivieren
    gsettings set org.gnome.desktop.screensaver lock-enabled false
    gsettings set org.gnome.desktop.screensaver idle-activation-enabled false
    gsettings set org.gnome.desktop.session idle-delay 0
    
    # Power Management
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
    gsettings set org.gnome.settings-daemon.plugins.power idle-dim false
    
    # Notifications deaktivieren
    gsettings set org.gnome.desktop.notifications show-banners false
    gsettings set org.gnome.desktop.notifications show-in-lock-screen false
    
    # Activities Overview deaktivieren (zusätzlich zur Extension)
    gsettings set org.gnome.shell.extensions.dash-to-dock autohide false
    gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false
    gsettings set org.gnome.shell.extensions.dash-to-dock intellihide false
    
    # Automatische Software-Updates deaktivieren
    gsettings set org.gnome.software allow-updates false
    gsettings set org.gnome.software download-updates false
    
    log_success "GNOME Einstellungen für Kiosk-Betrieb konfiguriert"
}

# Berechtigungen für Scripts setzen
set_script_permissions() {
    log "Setze Ausführungsberechtigungen für Scripts..."
    
    local scripts=(
        "$BASE_DIR/startkiosk.sh"
        "$BASE_DIR/config.sh"
        "$SCRIPT_DIR/disable_wayland.sh"
        "$SCRIPT_DIR/install_gnome_extension.sh"
        "$SCRIPT_DIR/setup_autologin.sh"
        "$SCRIPT_DIR/create_gnome_autostart_desktop.sh"
        "$SCRIPT_DIR/install_systemd_user_service.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            chmod +x "$script"
            log "Berechtigungen gesetzt: $(basename "$script")"
        fi
    done
    
    log_success "Script-Berechtigungen konfiguriert"
}

# Zusammenfassung anzeigen
show_summary() {
    echo -e "\n${GREEN}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║                    SETUP ABGESCHLOSSEN                      ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    log_success "Kiosk-System erfolgreich konfiguriert!"
    echo
    log "Konfigurierte Komponenten:"
    log "  ✓ Wayland deaktiviert, X11 aktiviert"
    log "  ✓ GNOME Extension 'No overview at startup' installiert"
    log "  ✓ Automatisches Login für Benutzer '$TARGET_USER' eingerichtet"
    log "  ✓ Kiosk-spezifische GNOME Einstellungen konfiguriert"
    log "  ✓ Script-Berechtigungen gesetzt"
    echo
    log "Nächste Schritte:"
    log "  1. URLs in $BASE_DIR/urls.ini konfigurieren"
    log "  2. Kiosk-Service einrichten:"
    log "     $SCRIPT_DIR/install_systemd_user_service.sh"
    log "  3. System neu starten für vollständige Aktivierung"
    echo
    log "Kiosk-System starten:"
    log "  $BASE_DIR/startkiosk.sh"
    echo
    log "Testmodus:"
    log "  $BASE_DIR/startkiosk.sh --test"
}

# Haupt-Setup-Funktion
main() {
    log "Starte Kiosk-System Setup..."
    
    # Voraussetzungen prüfen
    if ! check_prerequisites; then
        log_error "Setup abgebrochen: Voraussetzungen nicht erfüllt"
        exit 1
    fi
    
    # Backup erstellen
    create_backup
    
    # Setup-Schritte ausführen
    disable_wayland
    install_gnome_extension
    setup_autologin "$TARGET_USER"
    configure_kiosk_settings
    set_script_permissions
    
    # Zusammenfassung
    show_summary
    
    # Neustart-Erinnerung
    if [[ "$SKIP_REBOOT" != "true" ]]; then
        echo
        log_warning "WICHTIGER HINWEIS:"
        log_warning "Ein Neustart ist erforderlich, damit alle Änderungen wirksam werden!"
        echo
        read -p "System jetzt neu starten? (j/N): " -r
        if [[ $REPLY =~ ^[JjYy]$ ]]; then
            log "System wird neu gestartet..."
            sudo systemctl reboot
        else
            log "Neustart übersprungen. Bitte manuell neu starten."
        fi
    fi
}

# Error Handler
error_handler() {
    log_error "Fehler in Zeile $1: $2"
    log "Setup abgebrochen"
    exit 1
}

trap 'error_handler $LINENO "$BASH_COMMAND"' ERR

# Hilfe anzeigen
show_help() {
    cat << EOF
Kiosk System Setup Script

VERWENDUNG:
    $0 [BENUTZER] [SKIP_REBOOT]

PARAMETER:
    BENUTZER     - Benutzername für Autologin (Standard: aktueller Benutzer)
    SKIP_REBOOT  - 'true' um automatischen Neustart zu überspringen

BEISPIELE:
    $0                    # Setup für aktuellen Benutzer
    $0 kiosk             # Setup für Benutzer 'kiosk'
    $0 kiosk true        # Setup ohne automatischen Neustart

Das Script konfiguriert:
- Wayland-Deaktivierung (X11-Erzwingung)
- GNOME Extension "No overview at startup"
- Automatisches Login
- Kiosk-spezifische Systemeinstellungen
EOF
}

# Parameter prüfen
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
    exit 0
fi

# Hauptfunktion ausführen
main "$@"