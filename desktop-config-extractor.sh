#!/bin/bash
# Desktop-Konfiguration-Extraktor
# Dieses Skript erfasst die aktuelle Desktop-Konfiguration und speichert sie zur späteren Verwendung
VERSION="0.0.1"

# Farben für Ausgaben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # Keine Farbe

# Logging-Funktionen
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNUNG]${NC} $1"
}

log_error() {
    echo -e "${RED}[FEHLER]${NC} $1"
    exit 1
}

# Desktop-Umgebung erkennen
detect_desktop_env() {
    if [ -n "$XDG_CURRENT_DESKTOP" ]; then
        echo "$XDG_CURRENT_DESKTOP"
    elif [ -n "$DESKTOP_SESSION" ]; then
        echo "$DESKTOP_SESSION"
    elif pgrep -x "gnome-shell" >/dev/null; then
        echo "GNOME"
    elif pgrep -x "plasmashell" >/dev/null; then
        echo "KDE"
    elif pgrep -x "xfce4-session" >/dev/null; then
        echo "XFCE"
    else
        echo "UNKNOWN"
    fi
}

# Initialisierung
OUTPUT_DIR="$HOME/desktop-config-backup"
OUTPUT_FILE="$OUTPUT_DIR/desktop-config-$(date +%Y%m%d-%H%M%S).json"
TEMP_DIR=$(mktemp -d)

mkdir -p "$OUTPUT_DIR"

# Desktop-Umgebung erkennen
DESKTOP_ENV=$(detect_desktop_env)
log_info "Erkannte Desktop-Umgebung: $DESKTOP_ENV"

# Allgemeine Systeminformationen erfassen
collect_system_info() {
    log_info "Erfasse Systeminformationen..."
    
    mkdir -p "$TEMP_DIR/system"
    
    # Spracheinstellungen
    locale > "$TEMP_DIR/system/locale.txt"
    
    # Tastaturlayout
    if [ -f "/etc/default/keyboard" ]; then
        cp "/etc/default/keyboard" "$TEMP_DIR/system/keyboard"
    fi
    
    # Hostname
    hostname > "$TEMP_DIR/system/hostname.txt"
    
    # Zeitzone
    if [ -L "/etc/localtime" ]; then
        readlink -f /etc/localtime | sed 's|/usr/share/zoneinfo/||' > "$TEMP_DIR/system/timezone.txt"
    fi
    
    # System-Informationen
    if [ -f "/etc/os-release" ]; then
        cp "/etc/os-release" "$TEMP_DIR/system/os-release"
    fi
    
    # Installierte Pakete
    if command -v dpkg > /dev/null; then
        dpkg --get-selections > "$TEMP_DIR/system/installed-packages.txt"
    elif command -v rpm > /dev/null; then
        rpm -qa > "$TEMP_DIR/system/installed-packages.txt"
    fi
}

# GNOME-Einstellungen erfassen
collect_gnome_settings() {
    log_info "Erfasse GNOME-Einstellungen..."
    
    mkdir -p "$TEMP_DIR/gnome"
    
    # dconf-Einstellungen
    if command -v dconf > /dev/null; then
        dconf dump / > "$TEMP_DIR/gnome/dconf-settings.ini"
    fi
    
    # Installierte GNOME-Extensions
    if command -v gnome-extensions > /dev/null; then
        gnome-extensions list > "$TEMP_DIR/gnome/extensions-list.txt"
        
        # Liste mit aktivierten Extensions erstellen
        gnome-extensions list --enabled > "$TEMP_DIR/gnome/extensions-enabled.txt"
        
        # Detaillierte Informationen zu Extensions
        mkdir -p "$TEMP_DIR/gnome/extensions"
        while read -r extension; do
            ext_info=$(gnome-extensions info "$extension" 2>/dev/null)
            if [ $? -eq 0 ]; then
                echo "$ext_info" > "$TEMP_DIR/gnome/extensions/$extension.info"
            fi
        done < "$TEMP_DIR/gnome/extensions-list.txt"
    elif [ -d "$HOME/.local/share/gnome-shell/extensions" ]; then
        # Fallback, wenn gnome-extensions Befehl nicht verfügbar ist
        find "$HOME/.local/share/gnome-shell/extensions" -maxdepth 1 -type d | grep -v "^$HOME/.local/share/gnome-shell/extensions$" > "$TEMP_DIR/gnome/extensions-list.txt"
        
        # Extrahiere IDs aus Pfaden
        sed -i 's|.*/||' "$TEMP_DIR/gnome/extensions-list.txt"
        
        # Prüfen, welche Extensions aktiviert sind
        if command -v gsettings > /dev/null; then
            gsettings get org.gnome.shell enabled-extensions > "$TEMP_DIR/gnome/extensions-enabled-raw.txt"
            # Bereinigen und in ein Format pro Zeile umwandeln
            cat "$TEMP_DIR/gnome/extensions-enabled-raw.txt" | tr -d "[]'" | tr , '\n' | sed 's/^ *//' > "$TEMP_DIR/gnome/extensions-enabled.txt"
        fi
    fi
    
    # Hintergrundbilder
    if command -v gsettings > /dev/null; then
        gsettings get org.gnome.desktop.background picture-uri > "$TEMP_DIR/gnome/background-uri.txt"
        gsettings get org.gnome.desktop.background picture-uri-dark > "$TEMP_DIR/gnome/background-uri-dark.txt" 2>/dev/null || true
    fi
    
    # GTK-Theme
    if command -v gsettings > /dev/null; then
        gsettings get org.gnome.desktop.interface gtk-theme > "$TEMP_DIR/gnome/gtk-theme.txt"
        gsettings get org.gnome.desktop.interface icon-theme > "$TEMP_DIR/gnome/icon-theme.txt"
        gsettings get org.gnome.desktop.interface cursor-theme > "$TEMP_DIR/gnome/cursor-theme.txt"
        gsettings get org.gnome.desktop.interface font-name > "$TEMP_DIR/gnome/font-name.txt"
        gsettings get org.gnome.desktop.interface color-scheme > "$TEMP_DIR/gnome/color-scheme.txt" 2>/dev/null || echo "'default'" > "$TEMP_DIR/gnome/color-scheme.txt"
    fi
    
    # Nautilus (Dateimanager) Einstellungen
    if command -v gsettings > /dev/null; then
        gsettings list-recursively org.gnome.nautilus > "$TEMP_DIR/gnome/nautilus-settings.txt" 2>/dev/null || true
    fi
    
    # GNOME Terminal Einstellungen
    if command -v gsettings > /dev/null; then
        gsettings list-recursively org.gnome.Terminal > "$TEMP_DIR/gnome/terminal-settings.txt" 2>/dev/null || true
    fi
    
    # Tastaturkürzel
    if command -v gsettings > /dev/null; then
        gsettings list-recursively org.gnome.settings-daemon.plugins.media-keys > "$TEMP_DIR/gnome/keyboard-shortcuts.txt"
        gsettings list-recursively org.gnome.desktop.wm.keybindings >> "$TEMP_DIR/gnome/keyboard-shortcuts.txt"
    fi
    
    # Dash-to-Panel oder Dash-to-Dock Einstellungen
    if command -v gsettings > /dev/null; then
        gsettings list-recursively org.gnome.shell.extensions.dash-to-panel > "$TEMP_DIR/gnome/dash-to-panel.txt" 2>/dev/null || true
        gsettings list-recursively org.gnome.shell.extensions.dash-to-dock > "$TEMP_DIR/gnome/dash-to-dock.txt" 2>/dev/null || true
    fi
    
    # Weitere Extensions-Einstellungen (wenn vorhanden)
    if command -v gsettings > /dev/null; then
        # Impatience (Animation Speed)
        gsettings list-recursively org.gnome.shell.extensions.impatience > "$TEMP_DIR/gnome/impatience.txt" 2>/dev/null || true
        
        # Burn My Windows
        gsettings list-recursively org.gnome.shell.extensions.burn-my-windows > "$TEMP_DIR/gnome/burn-my-windows.txt" 2>/dev/null || true
        
        # User Themes
        gsettings list-recursively org.gnome.shell.extensions.user-theme > "$TEMP_DIR/gnome/user-theme.txt" 2>/dev/null || true
        
        # System Monitor
        gsettings list-recursively org.gnome.shell.extensions.system-monitor > "$TEMP_DIR/gnome/system-monitor.txt" 2>/dev/null || true
    fi
    
    # Favoriten in der Dash
    if command -v gsettings > /dev/null; then
        gsettings get org.gnome.shell favorite-apps > "$TEMP_DIR/gnome/favorite-apps.txt"
    fi
    
    # GNOME Shell Version
    if command -v gnome-shell > /dev/null; then
        gnome-shell --version > "$TEMP_DIR/gnome/version.txt" 2>/dev/null || echo "Unbekannt" > "$TEMP_DIR/gnome/version.txt"
    fi
}

# KDE-Einstellungen erfassen
collect_kde_settings() {
    log_info "Erfasse KDE-Einstellungen..."
    
    mkdir -p "$TEMP_DIR/kde"
    
    # Plasma-Version
    if command -v plasmashell > /dev/null; then
        plasmashell --version > "$TEMP_DIR/kde/version.txt" 2>/dev/null || echo "Unbekannt" > "$TEMP_DIR/kde/version.txt"
    fi
    
    # Desktop-Theme und Erscheinungsbild
    if command -v kreadconfig5 > /dev/null; then
        kreadconfig5 --group "KDE" --key "LookAndFeelPackage" > "$TEMP_DIR/kde/lookandfeel.txt" 2>/dev/null || true
        kreadconfig5 --group "KDE" --key "ColorScheme" > "$TEMP_DIR/kde/colorscheme.txt" 2>/dev/null || true
        kreadconfig5 --group "plasmarc" --key "Theme" > "$TEMP_DIR/kde/plasma-theme.txt" 2>/dev/null || true
        kreadconfig5 --group "kdeglobals" --key "widgetStyle" > "$TEMP_DIR/kde/widget-style.txt" 2>/dev/null || true
        kreadconfig5 --group "kdeglobals" --key "Name" --file "kcminputrc" > "$TEMP_DIR/kde/cursor-theme.txt" 2>/dev/null || true
        kreadconfig5 --group "Icons" --key "Theme" > "$TEMP_DIR/kde/icon-theme.txt" 2>/dev/null || true
    fi
    
    # Panel-Konfiguration (komplexer, nur Dateien kopieren)
    if [ -d "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" ]; then
        cp "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" "$TEMP_DIR/kde/"
    fi
    
    # Tastaturkürzel
    if [ -f "$HOME/.config/kglobalshortcutsrc" ]; then
        cp "$HOME/.config/kglobalshortcutsrc" "$TEMP_DIR/kde/"
    fi
    
    # Dolphin (Dateimanager) Einstellungen
    if [ -f "$HOME/.config/dolphinrc" ]; then
        cp "$HOME/.config/dolphinrc" "$TEMP_DIR/kde/"
    fi
    
    # Konsole (Terminal) Einstellungen
    if [ -d "$HOME/.local/share/konsole" ]; then
        mkdir -p "$TEMP_DIR/kde/konsole"
        cp -r "$HOME/.local/share/konsole/"* "$TEMP_DIR/kde/konsole/" 2>/dev/null || true
    fi
    
    # Kopiere wichtige KDE-Konfigurationsdateien
    CONFIG_FILES=(
        "kdeglobals"
        "kwinrc"
        "kcminputrc"
        "kscreenlockerrc"
        "plasmarc"
        "plasmashellrc"
        "plasma-org.kde.plasma.desktop-appletsrc"
        "ksmserverrc"
    )
    
    for file in "${CONFIG_FILES[@]}"; do
        if [ -f "$HOME/.config/$file" ]; then
            cp "$HOME/.config/$file" "$TEMP_DIR/kde/" 2>/dev/null || true
        fi
    done
    
    # Plasma-Widgets erfassen
    if command -v kpackagetool5 > /dev/null; then
        kpackagetool5 -l -t Plasma/Applet > "$TEMP_DIR/kde/plasma-widgets.txt" 2>/dev/null || true
    fi
    
    # Plasma-Aktiviertes Theme
    if [ -f "$HOME/.config/plasmarc" ]; then
        grep "Theme=" "$HOME/.config/plasmarc" > "$TEMP_DIR/kde/active-theme.txt" 2>/dev/null || true
    fi
    
    # Hintergrundbilder
    if command -v kreadconfig5 > /dev/null; then
        kreadconfig5 --group "Wallpaper" --key "Image" --file "plasma-org.kde.plasma.desktop-appletsrc" > "$TEMP_DIR/kde/wallpaper.txt" 2>/dev/null || true
    fi
}

# Xfce-Einstellungen erfassen
collect_xfce_settings() {
    log_info "Erfasse Xfce-Einstellungen..."
    
    mkdir -p "$TEMP_DIR/xfce"
    
    # Xfce-Version
    if command -v xfce4-about > /dev/null; then
        xfce4-about --version > "$TEMP_DIR/xfce/version.txt" 2>/dev/null || echo "Unbekannt" > "$TEMP_DIR/xfce/version.txt"
    elif command -v xfce4-session > /dev/null; then
        xfce4-session --version > "$TEMP_DIR/xfce/version.txt" 2>/dev/null || echo "Unbekannt" > "$TEMP_DIR/xfce/version.txt"
    fi
    
    # Alle Xfce-Einstellungen mit xfconf-query
    if command -v xfconf-query > /dev/null; then
        # Liste aller Kanäle
        xfconf-query -l > "$TEMP_DIR/xfce/channels.txt"
        
        # Erstelle Datei für jeden Kanal
        while read -r channel; do
            xfconf-query -c "$channel" -lv > "$TEMP_DIR/xfce/$channel.txt" 2>/dev/null || true
        done < "$TEMP_DIR/xfce/channels.txt"
    fi
    
    # Desktop-Hintergrund
    if command -v xfconf-query > /dev/null; then
        mkdir -p "$TEMP_DIR/xfce/desktop"
        # Der Wert muss für jede Arbeitsfläche einzeln abgefragt werden
        property_list=$(xfconf-query -c xfce4-desktop -p /backdrop -l | grep "last-image")
        for property in $property_list; do
            screen_name=$(echo "$property" | cut -d/ -f3)
            monitor_name=$(echo "$property" | cut -d/ -f4)
            workspace_name=$(echo "$property" | cut -d/ -f5)
            xfconf-query -c xfce4-desktop -p "$property" > "$TEMP_DIR/xfce/desktop/background-${screen_name}-${monitor_name}-${workspace_name}.txt" 2>/dev/null || true
        done
    fi
    
    # Theme-Einstellungen
    if command -v xfconf-query > /dev/null; then
        xfconf-query -c xsettings -p /Net/ThemeName > "$TEMP_DIR/xfce/theme-name.txt" 2>/dev/null || true
        xfconf-query -c xsettings -p /Net/IconThemeName > "$TEMP_DIR/xfce/icon-theme.txt" 2>/dev/null || true
        xfconf-query -c xfwm4 -p /general/theme > "$TEMP_DIR/xfce/window-theme.txt" 2>/dev/null || true
        xfconf-query -c xsettings -p /Gtk/CursorThemeName > "$TEMP_DIR/xfce/cursor-theme.txt" 2>/dev/null || true
    fi
    
    # Panel-Konfiguration
    if command -v xfconf-query > /dev/null; then
        xfconf-query -c xfce4-panel -lv > "$TEMP_DIR/xfce/panel-settings.txt" 2>/dev/null || true
    fi
    
    # Thunar (Dateimanager) Einstellungen
    if [ -f "$HOME/.config/Thunar/thunarrc" ]; then
        cp "$HOME/.config/Thunar/thunarrc" "$TEMP_DIR/xfce/"
    fi
    
    # Terminal-Einstellungen
    if [ -f "$HOME/.config/xfce4/terminal/terminalrc" ]; then
        cp "$HOME/.config/xfce4/terminal/terminalrc" "$TEMP_DIR/xfce/"
    fi
    
    # Tastaturkürzel
    if [ -f "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml" ]; then
        cp "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml" "$TEMP_DIR/xfce/"
    fi
    
    # Startmenü-Favoriten und andere wichtige XML-Dateien
    XML_CONFIGS=(
        "xfce4-panel.xml"
        "xfce4-session.xml"
        "xfwm4.xml"
        "xsettings.xml"
        "xfce4-desktop.xml"
        "displays.xml"
        "xfce4-power-manager.xml"
    )
    
    for config in "${XML_CONFIGS[@]}"; do
        if [ -f "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/$config" ]; then
            cp "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/$config" "$TEMP_DIR/xfce/" 2>/dev/null || true
        fi
    done
}

# Allgemeine Benutzereinstellungen erfassen
collect_user_settings() {
    log_info "Erfasse allgemeine Benutzereinstellungen..."
    
    mkdir -p "$TEMP_DIR/user"
    
    # Benutzername und UID/GID
    whoami > "$TEMP_DIR/user/username.txt"
    id > "$TEMP_DIR/user/id.txt"
    
    # Shell und Umgebungsvariablen
    echo "$SHELL" > "$TEMP_DIR/user/shell.txt"
    env | sort > "$TEMP_DIR/user/environment.txt"
    
    # Bash/Zsh-Konfiguration
    if [ -f "$HOME/.bashrc" ]; then
        cp "$HOME/.bashrc" "$TEMP_DIR/user/"
    fi
    
    if [ -f "$HOME/.bash_profile" ]; then
        cp "$HOME/.bash_profile" "$TEMP_DIR/user/"
    fi
    
    if [ -f "$HOME/.zshrc" ]; then
        cp "$HOME/.zshrc" "$TEMP_DIR/user/"
    fi
    
    # Autostart-Anwendungen
    if [ -d "$HOME/.config/autostart" ]; then
        mkdir -p "$TEMP_DIR/user/autostart"
        cp -r "$HOME/.config/autostart/"* "$TEMP_DIR/user/autostart/" 2>/dev/null || true
    fi
    
    # Installierte Flatpak-Anwendungen
    if command -v flatpak > /dev/null; then
        flatpak list --user > "$TEMP_DIR/user/flatpak-list.txt" 2>/dev/null || true
    fi
    
    # Snap-Anwendungen
    if command -v snap > /dev/null; then
        snap list > "$TEMP_DIR/user/snap-list.txt" 2>/dev/null || true
    fi
}

# Alle Einstellungen in eine JSON-Datei umwandeln
create_json_output() {
    log_info "Erstelle JSON-Ausgabedatei..."
    
    # Einfaches JSON-Generierungsskript
    python3 -c "
import json
import os
import sys
from datetime import datetime

def read_file_content(file_path):
    try:
        with open(file_path, 'r') as f:
            return f.read().strip()
    except:
        return None

def process_directory(directory):
    result = {}
    for item in os.listdir(directory):
        item_path = os.path.join(directory, item)
        if os.path.isdir(item_path):
            result[item] = process_directory(item_path)
        else:
            content = read_file_content(item_path)
            if content is not None:
                result[item] = content
    return result

data = {
    'metadata': {
        'version': '$VERSION',
        'desktop_environment': '$DESKTOP_ENV',
        'created_at': datetime.now().isoformat(),
        'username': os.environ.get('USER', 'unknown')
    }
}

temp_dir = '$TEMP_DIR'
for section in os.listdir(temp_dir):
    section_path = os.path.join(temp_dir, section)
    if os.path.isdir(section_path):
        data[section] = process_directory(section_path)

with open('$OUTPUT_FILE', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null

    # Prüfen, ob die Datei erfolgreich erstellt wurde
    if [ -f "$OUTPUT_FILE" ]; then
        log_info "JSON-Datei erfolgreich erstellt: $OUTPUT_FILE"
    else
        log_error "Fehler beim Erstellen der JSON-Datei!"
    fi
}

# Hauptprogramm
main() {
    log_info "Desktop-Konfiguration-Extraktor v$VERSION wird gestartet..."
    log_info "Temporäres Verzeichnis: $TEMP_DIR"
    log_info "Ausgabedatei: $OUTPUT_FILE"
    
    # Systeminfo sammeln
    collect_system_info
    
    # Benutzereinstellungen sammeln
    collect_user_settings
    
    # Desktop-spezifische Einstellungen sammeln
    case "$DESKTOP_ENV" in
        *GNOME*)
            collect_gnome_settings
            ;;
        *KDE*|*Plasma*)
            collect_kde_settings
            ;;
        *XFCE*)
            collect_xfce_settings
            ;;
        *)
            log_warn "Nicht unterstützte oder unbekannte Desktop-Umgebung: $DESKTOP_ENV"
            log_warn "Es werden nur allgemeine System- und Benutzereinstellungen erfasst."
            ;;
    esac
    
    # Einstellungen in JSON umwandeln
    create_json_output
    
    # Aufräumen
    log_info "Temporäre Dateien aufräumen..."
    rm -rf "$TEMP_DIR"
    
    log_info "Fertig! Du findest die exportierten Einstellungen in: $OUTPUT_FILE"
    echo ""
    echo "Um diese Einstellungen zu verwenden, kannst du das Extraktions-Tool ausführen,"
    echo "das die erste_login_setup.sh und post_install_setup.sh Skripte automatisch generiert."
    echo "Befehl: desktop-config-extractor-to-setup.sh $OUTPUT_FILE"
}

# Führe Hauptprogramm aus
main