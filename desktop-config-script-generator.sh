#!/bin/bash
# Desktop-Konfiguration zu Setup-Skripten
# Dieses Skript generiert aus einer extrahierten Desktop-Konfiguration die notwendigen Setup-Skripte
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

# Prüfen, ob JSON-Datei angegeben wurde
if [ -z "$1" ]; then
    log_error "Keine Konfigurationsdatei angegeben! Verwendung: $0 <konfiguration.json>"
fi

CONFIG_FILE="$1"
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Konfigurationsdatei '$CONFIG_FILE' existiert nicht!"
fi

# Ausgabeverzeichnis
OUTPUT_DIR="$(dirname "$CONFIG_FILE")/setup-scripts-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUTPUT_DIR"

# Temporäres Verzeichnis für Arbeitsdateien
TEMP_DIR=$(mktemp -d)

# Prüfen, ob Python verfügbar ist
if ! command -v python3 &> /dev/null; then
    log_error "Python 3 wird benötigt, ist aber nicht installiert. Bitte installiere Python 3."
fi

# Extrahiere Wert aus JSON für einen angegebenen Schlüssel
extract_json_value() {
    local json_file="$1"
    local key="$2"
    local default="$3"
    
    result=$(python3 -c "
import json
import sys

try:
    with open('$json_file', 'r') as f:
        data = json.load(f)
    
    keys = '$key'.split('.')
    current = data
    for k in keys:
        if k in current:
            current = current[k]
        else:
            print('$default')
            sys.exit(0)
    
    # Wenn wir hier sind, haben wir den Wert gefunden
    if isinstance(current, (dict, list)):
        print(json.dumps(current))
    else:
        print(current)
        
except Exception as e:
    print('$default')
    sys.exit(1)
" 2>/dev/null)

    echo "$result"
}

# Generiere das post_install_setup.sh Skript
generate_post_install_setup() {
    log_info "Generiere post_install_setup.sh Skript..."
    
    # Hole Desktop-Umgebung und Benutzernamen
    DESKTOP_ENV=$(extract_json_value "$CONFIG_FILE" "metadata.desktop_environment" "UNKNOWN")
    USERNAME=$(extract_json_value "$CONFIG_FILE" "user.username.txt" "$USER")
    
    # Konvertiere Desktop-Umgebung in Kleinbuchstaben und vereinfache
    DESKTOP_ENV_LOWER=$(echo "$DESKTOP_ENV" | tr '[:upper:]' '[:lower:]')
    if [[ "$DESKTOP_ENV_LOWER" == *"gnome"* ]]; then
        DESKTOP_TYPE="gnome"
        DESKTOP_DISPLAY_NAME="GNOME"
    elif [[ "$DESKTOP_ENV_LOWER" == *"kde"* || "$DESKTOP_ENV_LOWER" == *"plasma"* ]]; then
        DESKTOP_TYPE="kde"
        DESKTOP_DISPLAY_NAME="KDE Plasma"
    elif [[ "$DESKTOP_ENV_LOWER" == *"xfce"* ]]; then
        DESKTOP_TYPE="xfce"
        DESKTOP_DISPLAY_NAME="Xfce"
    else
        DESKTOP_TYPE="unknown"
        DESKTOP_DISPLAY_NAME="$DESKTOP_ENV"
    fi
    
    # Versionen ermitteln
    if [ "$DESKTOP_TYPE" = "gnome" ]; then
        DESKTOP_VERSION=$(extract_json_value "$CONFIG_FILE" "gnome.version.txt" "Unknown")
        # Extrahiere Major-Version (z.B. "GNOME Shell 42.5" -> "42")
        DESKTOP_MAJOR_VERSION=$(echo "$DESKTOP_VERSION" | grep -oE '[0-9]+\.[0-9]+' | cut -d. -f1)
    elif [ "$DESKTOP_TYPE" = "kde" ]; then
        DESKTOP_VERSION=$(extract_json_value "$CONFIG_FILE" "kde.version.txt" "Unknown")
        # Extrahiere Major-Version (z.B. "Plasma 5.24.7" -> "5")
        DESKTOP_MAJOR_VERSION=$(echo "$DESKTOP_VERSION" | grep -oE '[0-9]+\.[0-9]+' | cut -d. -f1)
    elif [ "$DESKTOP_TYPE" = "xfce" ]; then
        DESKTOP_VERSION=$(extract_json_value "$CONFIG_FILE" "xfce.version.txt" "Unknown")
        # Extrahiere Major-Version (z.B. "Xfce 4.16" -> "4")
        DESKTOP_MAJOR_VERSION=$(echo "$DESKTOP_VERSION" | grep -oE '[0-9]+\.[0-9]+' | cut -d. -f1)
    else
        DESKTOP_VERSION="Unknown"
        DESKTOP_MAJOR_VERSION=""
    fi
    
    # Tastatur- und Spracheinstellungen ermitteln
    if [ -n "$(extract_json_value "$CONFIG_FILE" "system.keyboard" "")" ]; then
        KEYBOARD_LAYOUT=$(extract_json_value "$CONFIG_FILE" "system.keyboard" "XKBLAYOUT" | grep "XKBLAYOUT" | cut -d= -f2 | tr -d '"')
    else
        KEYBOARD_LAYOUT="de"  # Standardwert
    fi
    
    LOCALE=$(extract_json_value "$CONFIG_FILE" "system.locale.txt" "de_DE.UTF-8" | grep "LANG=" | cut -d= -f2)
    LOCALE=${LOCALE:-"de_DE.UTF-8"}  # Standardwert, falls nicht gefunden
    
    TIMEZONE=$(extract_json_value "$CONFIG_FILE" "system.timezone.txt" "Europe/Berlin")
    TIMEZONE=${TIMEZONE:-"Europe/Berlin"}  # Standardwert, falls nicht gefunden
    
    # Output-Datei erstellen
    cat > "$OUTPUT_DIR/post_install_setup.sh" << EOF
#!/bin/bash
# Post-Installation Setup für systemweite Einstellungen
# Automatisch generiert aus Desktop-Konfiguration am $(date)
#
# Desktop-Umgebung: $DESKTOP_DISPLAY_NAME $DESKTOP_VERSION

# Erweiterte Logging-Funktionen
LOG_FILE="/var/log/post-install-setup.log"
mkdir -p "\$(dirname "\$LOG_FILE")"
exec > >(tee -a "\$LOG_FILE") 2>&1

echo "===== Start post-installation setup \$(date) ====="

# Hilfsfunktion für Logging
log() {
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1"
}

# Fehlerbehandlung verbessern
set -e  # Exit bei Fehlern
trap 'log "FEHLER: Ein Befehl ist fehlgeschlagen bei Zeile \$LINENO"' ERR

# Umgebungsvariablen explizit setzen
export HOME=/root
export XDG_RUNTIME_DIR=/run/user/0
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/0/bus

# Desktop-Umgebung definieren
DESKTOP_ENV="$DESKTOP_TYPE"
DESKTOP_NAME="$DESKTOP_DISPLAY_NAME"
DESKTOP_VERSION="$DESKTOP_VERSION"
DESKTOP_MAJOR_VERSION="$DESKTOP_MAJOR_VERSION"
KEYBOARD_LAYOUT="$KEYBOARD_LAYOUT"
LOCALE="$LOCALE"
TIMEZONE="$TIMEZONE"
USERNAME="$USERNAME"

log "Verwende erkannte Desktop-Umgebung: \${DESKTOP_NAME} \${DESKTOP_VERSION}"

# DBus-Session für Systembenutzer starten, falls nötig
if [ ! -e "/run/user/0/bus" ]; then
    log "Starte dbus-daemon für System-Benutzer..."
    mkdir -p /run/user/0
    dbus-daemon --session --address=unix:path=/run/user/0/bus --nofork --print-address &
    sleep 2
    export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/0/bus
fi

EOF

    # Füge Desktop-spezifische Einstellungen hinzu basierend auf dem Typ
    if [ "$DESKTOP_TYPE" = "gnome" ]; then
        generate_gnome_post_install_setup >> "$OUTPUT_DIR/post_install_setup.sh"
    elif [ "$DESKTOP_TYPE" = "kde" ]; then
        generate_kde_post_install_setup >> "$OUTPUT_DIR/post_install_setup.sh"
    elif [ "$DESKTOP_TYPE" = "xfce" ]; then
        generate_xfce_post_install_setup >> "$OUTPUT_DIR/post_install_setup.sh"
    else
        echo "# Keine spezifischen Einstellungen für diese Desktop-Umgebung verfügbar" >> "$OUTPUT_DIR/post_install_setup.sh"
    fi
    
    # Gemeinsamer Abschlussteil
    cat >> "$OUTPUT_DIR/post_install_setup.sh" << 'EOF'

# Erstelle das first_login_setup.sh Skript für Benutzereinstellungen
log "Erstelle first_login_setup.sh für benutzerspezifische Einstellungen..."
mkdir -p /usr/local/bin/

cat > /usr/local/bin/first_login_setup.sh <<'EOLOGINSETUP'
#!/bin/bash
EOF

    # Inhalt von first_login_setup.sh einfügen 
    # (wird später von einer anderen Funktion generiert)
    echo "# Dieser Inhalt wird später generiert" >> "$OUTPUT_DIR/post_install_setup.sh"
    
    # Abschluss des Post-Install-Setup-Skripts
    cat >> "$OUTPUT_DIR/post_install_setup.sh" << 'EOF'
EOLOGINSETUP

# Skript ausführbar machen
chmod 755 /usr/local/bin/first_login_setup.sh

# Autostart-Eintrag für den Benutzer erstellen
mkdir -p /etc/skel/.config/autostart
cat > /etc/skel/.config/autostart/first-login-setup.desktop <<EOAUTOSTART
[Desktop Entry]
Type=Application
Name=First Login Setup
Comment=Initial user configuration after first login
Exec=/usr/local/bin/first_login_setup.sh
Terminal=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Phase=Applications
X-GNOME-Autostart-Delay=3
NoDisplay=false
EOAUTOSTART

# Kopiere Autostart-Eintrag in Benutzerverzeichnis
mkdir -p /home/${USERNAME}/.config/autostart
cp /etc/skel/.config/autostart/first-login-setup.desktop /home/${USERNAME}/.config/autostart/
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.config

# Funktion zur Überprüfung, ob Systemkomponenten korrekt installiert wurden
check_system_setup() {
    local errors=0
    
    log "===== Validierung der Systemeinstellungen ====="
    log "Gestartet am: $(date)" 
    
    # 1. Prüfen, ob alle erforderlichen Verzeichnisse existieren
    log "Prüfe erforderliche Verzeichnisse..." 
    required_dirs=("/usr/local/bin" "/etc/skel/.config/autostart")
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log "FEHLER: Verzeichnis $dir wurde nicht erstellt!"
            ((errors++))
        else
            log "OK: Verzeichnis $dir existiert."
        fi
    done
    
    # 2. Prüfen, ob das First-Login-Setup erstellt wurde
    log "Prüfe First-Login-Setup-Skript..." 
    if [ ! -f "/usr/local/bin/first_login_setup.sh" ]; then
        log "FEHLER: First-Login-Setup-Skript fehlt!"
        ((errors++))
    else
        if [ ! -x "/usr/local/bin/first_login_setup.sh" ]; then
            log "FEHLER: First-Login-Setup-Skript ist nicht ausführbar!"
            ((errors++))
        else
            log "OK: First-Login-Setup-Skript wurde korrekt erstellt."
        fi
    fi
    
    # Ausgabe des Ergebnisses
    log "===== Validierungszusammenfassung ====="
    if [ $errors -eq 0 ]; then
        log "ERFOLG: Alle Systemeinstellungen wurden korrekt implementiert."
        return 0
    else
        log "FEHLER: $errors Probleme bei der Systemkonfiguration gefunden."
        return 1
    fi
}

# Am Ende des Skripts die Prüfung durchführen und basierend darauf entscheiden
if check_system_setup; then
    log "Selbstzerstörung des systemd-Dienstes wird eingeleitet..."
    
    # Dienst als einmalig markieren und nicht beim nächsten Start ausführen
    if [ -f "/etc/systemd/system/multi-user.target.wants/post-install-setup.service" ]; then
        rm -f "/etc/systemd/system/multi-user.target.wants/post-install-setup.service"
    fi
    
    # Skript selbst löschen (mit Verzögerung)
    (sleep 2 && rm -f "$0") &
    
    log "Post-installation setup erfolgreich abgeschlossen."
    exit 0
else
    log "Selbstzerstörung abgebrochen aufgrund von Validierungsfehlern."
    log "Das Skript bleibt erhalten für eine manuelle Behebung."
    exit 1
fi
EOF

    # Skript ausführbar machen
    chmod +x "$OUTPUT_DIR/post_install_setup.sh"
    log_info "post_install_setup.sh erfolgreich erstellt"
}

# Generiere GNOME-spezifische post-install Konfiguration
generate_gnome_post_install_setup() {
    # Extrahiere GNOME-Extensions
    ENABLED_EXTENSIONS=$(extract_json_value "$CONFIG_FILE" "gnome.extensions-enabled.txt" "")
    GTK_THEME=$(extract_json_value "$CONFIG_FILE" "gnome.gtk-theme.txt" "'Adwaita'")
    COLOR_SCHEME=$(extract_json_value "$CONFIG_FILE" "gnome.color-scheme.txt" "'default'")
    ICON_THEME=$(extract_json_value "$CONFIG_FILE" "gnome.icon-theme.txt" "'Adwaita'")
    CURSOR_THEME=$(extract_json_value "$CONFIG_FILE" "gnome.cursor-theme.txt" "'Adwaita'")
    FAVORITE_APPS=$(extract_json_value "$CONFIG_FILE" "gnome.favorite-apps.txt" "[]")
    
    # Extrahiere GNOME-Extensions-Einstellungen
    D2P_PANEL_SIZE=$(extract_json_value "$CONFIG_FILE" "gnome.dash-to-panel.txt" "" | grep "panel-size" | cut -d ' ' -f3)
    D2P_PANEL_SIZE=${D2P_PANEL_SIZE:-48}
    
    # Ausgewählte dconf-Einstellungen extrahieren
    # Hier könnten noch mehr Einstellungen hinzugefügt werden

    cat << EOF
# GNOME-spezifische Einstellungen
if [ "\$DESKTOP_ENV" = "gnome" ]; then
    log "Konfiguriere \${DESKTOP_NAME} \${DESKTOP_VERSION} Einstellungen..."
    
    # Directory für gsettings-override erstellen
    mkdir -p /usr/share/glib-2.0/schemas/
    
    # Erstelle Schema-Override-Datei für allgemeine GNOME-Einstellungen
    cat > /usr/share/glib-2.0/schemas/90_ubuntu-fde.gschema.override <<EOSETTINGS
# UbuntuFDE Schema Override für GNOME

[org.gnome.desktop.input-sources]
sources=[('xkb', '\$KEYBOARD_LAYOUT')]
xkb-options=[]

[org.gnome.desktop.wm.preferences]
button-layout='appmenu:minimize,maximize,close'
focus-mode='click'
auto-raise=false

[org.gnome.desktop.interface]
color-scheme=$COLOR_SCHEME
gtk-theme=$GTK_THEME
cursor-theme=$CURSOR_THEME
icon-theme=$ICON_THEME
clock-show-seconds=true
clock-show-weekday=true
cursor-blink=true
cursor-size=24
enable-animations=true
font-antialiasing='rgba'
font-hinting='slight'
show-battery-percentage=true

[org.gnome.settings-daemon.plugins.power]
power-button-action='interactive'
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'

[org.gnome.desktop.session]
idle-delay=uint32 0
session-name='ubuntu'

[org.gnome.shell]
favorite-apps=$FAVORITE_APPS
enabled-extensions=['user-theme@gnome-shell-extensions.gcampax.github.com']
EOSETTINGS

    # Schema-Override für den GDM-Anmeldebildschirm 
    cat > /usr/share/glib-2.0/schemas/91_gdm-settings.gschema.override <<EOGDM
# UbuntuFDE Schema Override für GDM

[org.gnome.desktop.input-sources:gdm]
sources=[('xkb', '\$KEYBOARD_LAYOUT')]
xkb-options=[]

[org.gnome.login-screen]
disable-user-list=true
banner-message-enable=false
logo=''

[org.gnome.desktop.interface:gdm]
color-scheme=$COLOR_SCHEME
gtk-theme=$GTK_THEME
cursor-theme=$CURSOR_THEME
icon-theme=$ICON_THEME
EOGDM

    # Schemas kompilieren
    log "Kompiliere glib-Schemas..."
    glib-compile-schemas /usr/share/glib-2.0/schemas/

# Installiere GNOME Shell Erweiterungen
    log "Installiere GNOME Shell Erweiterungen..."
    
    # GNOME Shell Version ermitteln
    GNOME_VERSION=\$(gnome-shell --version 2>/dev/null | cut -d ' ' -f 3 | cut -d '.' -f 1,2 || echo "")
    GNOME_MAJOR_VERSION=\$(echo \$GNOME_VERSION | cut -d '.' -f 1)
    log "Erkannte GNOME Shell Version: \$GNOME_VERSION (Major: \$GNOME_MAJOR_VERSION)"
    
    # Extension-Daten definieren
    DASH_TO_PANEL_UUID="dash-to-panel@jderose9.github.com"
    USER_THEME_UUID="user-theme@gnome-shell-extensions.gcampax.github.com"
    IMPATIENCE_UUID="impatience@gfxmonk.net"
    BURN_MY_WINDOWS_UUID="burn-my-windows@schneegans.github.com"
    SYSTEM_MONITOR_UUID="system-monitor@gnome-shell-extensions.gcampax.github.com"
    
    # Version-Mapping für alle Extensions basierend auf den HTML-Dokumenten
    declare -A DASH_TO_PANEL_VERSIONS
    DASH_TO_PANEL_VERSIONS[48]=68
    DASH_TO_PANEL_VERSIONS[47]=68
    DASH_TO_PANEL_VERSIONS[46]=68
    DASH_TO_PANEL_VERSIONS[45]=60
    DASH_TO_PANEL_VERSIONS[44]=56
    DASH_TO_PANEL_VERSIONS[43]=56
    DASH_TO_PANEL_VERSIONS[42]=56
    DASH_TO_PANEL_VERSIONS[41]=52
    DASH_TO_PANEL_VERSIONS[40]=69
    
    declare -A USER_THEME_VERSIONS
    USER_THEME_VERSIONS[48]=63
    USER_THEME_VERSIONS[47]=61
    USER_THEME_VERSIONS[46]=60
    USER_THEME_VERSIONS[45]=54
    USER_THEME_VERSIONS[44]=51
    USER_THEME_VERSIONS[43]=50
    USER_THEME_VERSIONS[42]=49
    USER_THEME_VERSIONS[41]=48
    USER_THEME_VERSIONS[40]=46
    
    declare -A IMPATIENCE_VERSIONS
    IMPATIENCE_VERSIONS[48]=28
    IMPATIENCE_VERSIONS[47]=28
    IMPATIENCE_VERSIONS[46]=28
    IMPATIENCE_VERSIONS[45]=28
    IMPATIENCE_VERSIONS[44]=22
    IMPATIENCE_VERSIONS[43]=22
    IMPATIENCE_VERSIONS[42]=22
    IMPATIENCE_VERSIONS[41]=22
    IMPATIENCE_VERSIONS[40]=22
    
    declare -A BURN_MY_WINDOWS_VERSIONS
    BURN_MY_WINDOWS_VERSIONS[48]=46
    BURN_MY_WINDOWS_VERSIONS[47]=46
    BURN_MY_WINDOWS_VERSIONS[46]=46
    BURN_MY_WINDOWS_VERSIONS[45]=46
    BURN_MY_WINDOWS_VERSIONS[44]=42
    BURN_MY_WINDOWS_VERSIONS[43]=42
    BURN_MY_WINDOWS_VERSIONS[42]=42
    BURN_MY_WINDOWS_VERSIONS[41]=42
    BURN_MY_WINDOWS_VERSIONS[40]=42
    
    declare -A SYSTEM_MONITOR_VERSIONS
    SYSTEM_MONITOR_VERSIONS[48]=8
    SYSTEM_MONITOR_VERSIONS[47]=6
    SYSTEM_MONITOR_VERSIONS[46]=5
    SYSTEM_MONITOR_VERSIONS[45]=0
    SYSTEM_MONITOR_VERSIONS[44]=0
    SYSTEM_MONITOR_VERSIONS[43]=0
    SYSTEM_MONITOR_VERSIONS[42]=0
    SYSTEM_MONITOR_VERSIONS[41]=0
    SYSTEM_MONITOR_VERSIONS[40]=0
    
    # Funktion zum Erstellen der korrekten Download-URL basierend auf Extension UUID und GNOME-Version
    get_extension_url() {
        local uuid="\$1"
        local gnome_version="\$2"
        local extension_version
        
        if [[ "\$uuid" == "\$DASH_TO_PANEL_UUID" ]]; then
            if [[ -n "\${DASH_TO_PANEL_VERSIONS[\$gnome_version]}" ]]; then
                extension_version="\${DASH_TO_PANEL_VERSIONS[\$gnome_version]}"
            else
                extension_version="68"
                log "Keine spezifische Version für GNOME \$gnome_version gefunden, verwende Version \$extension_version als Fallback"
            fi
            echo "https://extensions.gnome.org/extension-data/dash-to-paneljderose9.github.com.v\${extension_version}.shell-extension.zip"
        
        elif [[ "\$uuid" == "\$USER_THEME_UUID" ]]; then
            if [[ -n "\${USER_THEME_VERSIONS[\$gnome_version]}" ]]; then
                extension_version="\${USER_THEME_VERSIONS[\$gnome_version]}"
            else
                extension_version="63"
                log "Keine spezifische Version für GNOME \$gnome_version gefunden, verwende Version \$extension_version als Fallback"
            fi
            echo "https://extensions.gnome.org/extension-data/user-themegnome-shell-extensions.gcampax.github.com.v\${extension_version}.shell-extension.zip"
        
        elif [[ "\$uuid" == "\$IMPATIENCE_UUID" ]]; then
            if [[ -n "\${IMPATIENCE_VERSIONS[\$gnome_version]}" ]]; then
                extension_version="\${IMPATIENCE_VERSIONS[\$gnome_version]}"
            else
                extension_version="28"
                log "Keine spezifische Version für GNOME \$gnome_version gefunden, verwende Version \$extension_version als Fallback"
            fi
            echo "https://extensions.gnome.org/extension-data/impatiencegfxmonk.net.v\${extension_version}.shell-extension.zip"
        
        elif [[ "\$uuid" == "\$BURN_MY_WINDOWS_UUID" ]]; then
            if [[ -n "\${BURN_MY_WINDOWS_VERSIONS[\$gnome_version]}" ]]; then
                extension_version="\${BURN_MY_WINDOWS_VERSIONS[\$gnome_version]}"
            else
                extension_version="46"
                log "Keine spezifische Version für GNOME \$gnome_version gefunden, verwende Version \$extension_version als Fallback"
            fi
            echo "https://extensions.gnome.org/extension-data/burn-my-windowsschneegans.github.com.v\${extension_version}.shell-extension.zip"
        
        elif [[ "\$uuid" == "\$SYSTEM_MONITOR_UUID" ]]; then
            if [[ -n "\${SYSTEM_MONITOR_VERSIONS[\$gnome_version]}" ]]; then
                extension_version="\${SYSTEM_MONITOR_VERSIONS[\$gnome_version]}"
                echo "https://extensions.gnome.org/extension-data/system-monitorgnome-shell-extensions.gcampax.github.com.v\${extension_version}.shell-extension.zip"
            else
                # Da System Monitor nicht für alle Versionen verfügbar ist, geben wir hier eine Warnung aus
                log "System Monitor ist nicht für GNOME \$gnome_version verfügbar"
                return 1
            fi
        else
            log "Unbekannte Extension UUID: \$uuid"
            return 1
        fi
    }
    
    # Funktion zum Herunterladen und Installieren einer Extension
    install_extension() {
        local uuid="\$1"
        local tmp_dir=\$(mktemp -d)
        local tmp_zip="\$tmp_dir/extension.zip"
        
        # Generiere first_login_setup.sh
    generate_first_login_setup
    
    # Aktualisiere post_install_setup.sh mit dem Inhalt von first_login_setup.sh
    update_post_install_script
    
    # Erstelle README-Datei mit Anleitung
    cat > "$OUTPUT_DIR/README.md" << EOF
# Desktop-Konfiguration Setup

Diese Skripte wurden automatisch aus deiner bestehenden Desktop-Konfiguration erstellt.

## Dateien

- **post_install_setup.sh**: Wird während der Systeminstallation mit Root-Rechten ausgeführt
- **first_login_setup.sh**: Wird beim ersten Login des Benutzers ausgeführt

## Verwendung

### Option 1: Einbindung in UbuntuFDE-Skript

1. Kopiere den Inhalt von **post_install_setup.sh** in den entsprechenden Teil des UbuntuFDE-Skripts
2. Stelle sicher, dass alle Variablen korrekt gesetzt sind

### Option 2: Manuelle Ausführung nach Installation

1. Kopiere die Dateien auf das neu installierte System
2. Führe aus: \`sudo bash post_install_setup.sh\`
3. Führe beim ersten Login automatisch \`first_login_setup.sh\` aus

## Desktop-Umgebung

- Erkannter Desktop-Typ: $DESKTOP_TYPE
- Version: $(extract_json_value "$CONFIG_FILE" "$DESKTOP_TYPE.version.txt" "Unbekannt")

## Erstellungsdatum

$(date)

EOF

    log_info "README.md erstellt."
    
    # Ausgabeverzeichnis
    echo ""
    echo "Fertig! Die generierten Skripte findest du in: $OUTPUT_DIR"
    echo "- post_install_setup.sh: Führt systemweite Einstellungen mit Root-Rechten aus"
    echo "- first_login_setup.sh: Passt Benutzereinstellungen beim ersten Login an"
    echo "- README.md: Enthält Anweisungen zur Verwendung der Skripte"
    echo ""
    echo "Du kannst diese Skripte verwenden, um deine Desktop-Konfiguration in"
    echo "zukünftigen Installationen automatisch zu reproduzieren."
}

# Führe Hauptprogramm aus
main die URL basierend auf UUID und GNOME Version
        local download_url=\$(get_extension_url "\$uuid" "\$GNOME_MAJOR_VERSION")
        
        if [ -z "\$download_url" ]; then
            log "Konnte keine Download-URL für \$uuid generieren - diese Extension wird übersprungen"
            rm -rf "\$tmp_dir"
            return 1
        fi
        
        log "Installiere Extension: \$uuid"
        log "Download URL: \$download_url"
        
        # Entferne vorhandene Extension vollständig
        if [ -d "/usr/share/gnome-shell/extensions/\$uuid" ]; then
            log "Entferne vorherige Version von \$uuid"
            rm -rf "/usr/share/gnome-shell/extensions/\$uuid"
            sleep 1  # Kurze Pause, um sicherzustellen, dass Dateien gelöscht werden
        fi
        
        # Download und Installation
        if wget -q -O "\$tmp_zip" "\$download_url"; then
            log "Download erfolgreich"
            
            # Erstelle Zielverzeichnis
            mkdir -p "/usr/share/gnome-shell/extensions/\$uuid"
            
            # Entpacke die Extension
            if unzip -q -o "\$tmp_zip" -d "/usr/share/gnome-shell/extensions/\$uuid"; then
                log "Extension erfolgreich entpackt"
                
                # Überprüfe, ob extension.js vorhanden ist
                if [ -f "/usr/share/gnome-shell/extensions/\$uuid/extension.js" ]; then
                    log "extension.js gefunden"
                else
                    log "WARNUNG: extension.js nicht gefunden!"
                fi
                
                # Setze Berechtigungen
                chmod -R 755 "/usr/share/gnome-shell/extensions/\$uuid"
                
                # Passe metadata.json an, um die GNOME-Version explizit zu unterstützen
                if [ -f "/usr/share/gnome-shell/extensions/\$uuid/metadata.json" ]; then
                    log "Passe metadata.json an, um GNOME \$GNOME_VERSION zu unterstützen"
                    
                    # Sicherungskopie erstellen
                    cp "/usr/share/gnome-shell/extensions/\$uuid/metadata.json" "/usr/share/gnome-shell/extensions/\$uuid/metadata.json.bak"
                    
                    # Füge die aktuelle GNOME-Version zur Liste der unterstützten Versionen hinzu
                    if command -v jq &>/dev/null; then
                        jq --arg version "\$GNOME_MAJOR_VERSION" --arg fullversion "\$GNOME_VERSION" \
                           'if .["shell-version"] then .["shell-version"] += [\$version, \$fullversion] else .["shell-version"] = [\$version, \$fullversion] end' \
                           "/usr/share/gnome-shell/extensions/\$uuid/metadata.json.bak" > "/usr/share/gnome-shell/extensions/\$uuid/metadata.json"
                    else
                        # Fallback wenn jq nicht verfügbar ist
                        # Wir verwenden sed, um die Versionen hinzuzufügen
                        sed -i 's/"shell-version": \\[\\(.*\\)\\]/"shell-version": [\\1, "'\$GNOME_MAJOR_VERSION'", "'\$GNOME_VERSION'"]/' "/usr/share/gnome-shell/extensions/\$uuid/metadata.json"
                    fi
                    
                    log "metadata.json angepasst: Version \$GNOME_VERSION hinzugefügt"
                else
                    log "WARNUNG: metadata.json nicht gefunden"
                fi
                
                # Kompiliere Schemas, falls vorhanden
                if [ -d "/usr/share/gnome-shell/extensions/\$uuid/schemas" ]; then
                    log "Kompiliere GSettings Schemas"
                    glib-compile-schemas "/usr/share/gnome-shell/extensions/\$uuid/schemas"
                fi
                
                log "Extension \$uuid erfolgreich installiert"
                return 0
            else
                log "FEHLER: Konnte Extension nicht entpacken"
            fi
        else
            log "FEHLER: Download fehlgeschlagen für URL: \$download_url"
        fi
        
        rm -rf "\$tmp_dir"
        return 1
    }
    
    # Extensions installieren
    log "Installiere Dash to Panel..."
    install_extension "\$DASH_TO_PANEL_UUID"
    
    log "Installiere User Theme..."
    install_extension "\$USER_THEME_UUID"
    
    log "Installiere Impatience..."
    install_extension "\$IMPATIENCE_UUID"
    
    log "Installiere Burn My Windows..."
    install_extension "\$BURN_MY_WINDOWS_UUID"
    
    log "Installiere System Monitor..."
    install_extension "\$SYSTEM_MONITOR_UUID" || true  # Fortsetzung auch bei Fehler
    
fi
EOF
}

# Generiere KDE-spezifische post-install Konfiguration
generate_kde_post_install_setup() {
    # Extrahiere KDE-Einstellungen
    COLOR_SCHEME=$(extract_json_value "$CONFIG_FILE" "kde.colorscheme.txt" "")
    PLASMA_THEME=$(extract_json_value "$CONFIG_FILE" "kde.plasma-theme.txt" "")
    ICON_THEME=$(extract_json_value "$CONFIG_FILE" "kde.icon-theme.txt" "")
    CURSOR_THEME=$(extract_json_value "$CONFIG_FILE" "kde.cursor-theme.txt" "")
    
    cat << EOF
# KDE-spezifische Einstellungen
if [ "\$DESKTOP_ENV" = "kde" ]; then
    log "Konfiguriere \${DESKTOP_NAME} \${DESKTOP_VERSION} Einstellungen..."
    
    # Erstelle notwendige Verzeichnisse
    mkdir -p /etc/skel/.config
    
    # KDE Standard-Konfigurationsdateien erstellen
    cat > /etc/skel/.config/kdeglobals <<EOKDEGLOBALS
[General]
ColorScheme=$COLOR_SCHEME
widgetStyle=Breeze

[Icons]
Theme=$ICON_THEME

[KDE]
LookAndFeelPackage=org.kde.breeze.desktop
SingleClick=false
EOKDEGLOBALS

    cat > /etc/skel/.config/plasmarc <<EOPLASMARC
[Theme]
name=$PLASMA_THEME
EOPLASMARC

    cat > /etc/skel/.config/kcminputrc <<EOKCMINPUTRC
[Mouse]
cursorTheme=$CURSOR_THEME
EOKCMINPUTRC

    # Konfiguriere SDDM für automatische Anmeldung
    mkdir -p /etc/sddm.conf.d
    cat > /etc/sddm.conf.d/autologin.conf <<EOSDDM
[Autologin]
User=\${USERNAME}
Session=plasma.desktop
Relogin=false
EOSDDM
fi
EOF
}

# Generiere Xfce-spezifische post-install Konfiguration
generate_xfce_post_install_setup() {
    # Extrahiere Xfce-Einstellungen
    THEME_NAME=$(extract_json_value "$CONFIG_FILE" "xfce.theme-name.txt" "")
    ICON_THEME=$(extract_json_value "$CONFIG_FILE" "xfce.icon-theme.txt" "")
    WINDOW_THEME=$(extract_json_value "$CONFIG_FILE" "xfce.window-theme.txt" "")
    CURSOR_THEME=$(extract_json_value "$CONFIG_FILE" "xfce.cursor-theme.txt" "")
    
    cat << EOF
# Xfce-spezifische Einstellungen
if [ "\$DESKTOP_ENV" = "xfce" ]; then
    log "Konfiguriere \${DESKTOP_NAME} \${DESKTOP_VERSION} Einstellungen..."
    
    # Erstelle notwendige Verzeichnisse
    mkdir -p /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml
    
    # Xfce Standard-Konfiguration erstellen
    cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml <<EOXSETTINGS
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="$THEME_NAME"/>
    <property name="IconThemeName" type="string" value="$ICON_THEME"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="CursorThemeName" type="string" value="$CURSOR_THEME"/>
  </property>
</channel>
EOXSETTINGS

    cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml <<EOXFWM4
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="$WINDOW_THEME"/>
  </property>
</channel>
EOXFWM4

    # Konfiguriere LightDM für automatische Anmeldung
    mkdir -p /etc/lightdm
    cat > /etc/lightdm/lightdm.conf <<EOLIGHTDM
[SeatDefaults]
autologin-user=\${USERNAME}
autologin-user-timeout=0
user-session=xfce
greeter-session=lightdm-gtk-greeter
EOLIGHTDM
fi
EOF
}