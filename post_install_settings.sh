#!/bin/bash
# Erweiterte Logging-Funktionen
LOG_FILE="/var/log/post-install-settings.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "===== Start post-installation setup $(date) ====="

# Hilfsfunktion für Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Fehlerbehandlung verbessern
set -e  # Exit bei Fehlern
trap 'log "FEHLER: Ein Befehl ist fehlgeschlagen bei Zeile $LINENO"' ERR

# Umgebungsvariablen explizit setzen
export HOME=/root
export XDG_RUNTIME_DIR=/run/user/0
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/0/bus
# ...

# Prüfe GNOME-Komponenten
log "Prüfe GNOME-Komponenten..."
if [ -f /usr/bin/gnome-shell ]; then
    log "GNOME Shell gefunden: $(gnome-shell --version)"
else
    log "WARNUNG: GNOME Shell nicht gefunden!"
fi

# DBus-Session für Systembenutzer starten
if [ ! -e "/run/user/0/bus" ]; then
    log "Starte dbus-daemon für System-Benutzer..."
    mkdir -p /run/user/0
    dbus-daemon --session --address=unix:path=/run/user/0/bus --nofork --print-address &
    sleep 2
    export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/0/bus
fi

# Post-Installation Einstellungen
# Wird beim ersten Start ausgeführt und löscht sich selbst

# Prüfen, ob das Skript mit Root-Rechten ausgeführt wird
if [ "$(id -u)" -ne 0 ]; then
    echo "Dieses Skript muss mit Root-Rechten ausgeführt werden."
    echo "Erneuter Start mit sudo..."
    sudo "$0"
    exit $?
fi

# Desktop-Umgebung erkennen
if [ -f /usr/bin/gnome-shell ]; then
    DESKTOP_ENV="gnome"
elif [ -f /usr/bin/plasmashell ]; then
    DESKTOP_ENV="kde"
elif [ -f /usr/bin/xfce4-session ]; then
    DESKTOP_ENV="xfce"
else
    DESKTOP_ENV="unknown"
fi

echo "Erkannte Desktop-Umgebung: $DESKTOP_ENV"

# GNOME-spezifische Einstellungen
if [ "$DESKTOP_ENV" = "gnome" ]; then
    echo "Konfiguriere GNOME-Einstellungen..."
    
    # Directory für gsettings-override erstellen
    mkdir -p /usr/share/glib-2.0/schemas/
    
    # Erstelle Schema-Override-Datei für allgemeine GNOME-Einstellungen
    cat > /usr/share/glib-2.0/schemas/90_ubuntu-fde.gschema.override <<EOSETTINGS
# UbuntuFDE Schema Override für GNOME

[org.gnome.desktop.input-sources]
sources=[('xkb', '${KEYBOARD_LAYOUT}')]
xkb-options=[]

[org.gnome.desktop.wm.preferences]
button-layout='appmenu:minimize,maximize,close'
focus-mode='click'
auto-raise=false
raise-on-click=true
action-double-click-titlebar='toggle-maximize'
action-middle-click-titlebar='lower'
action-right-click-titlebar='menu'
mouse-button-modifier='<Super>'
resize-with-right-button=true
visual-bell=false
audible-bell=false
num-workspaces=4

[org.gnome.desktop.interface]
color-scheme='prefer-dark'
gtk-theme='Adwaita-dark'
accent-color='brown'
cursor-theme='Adwaita'
clock-show-seconds=true
clock-show-weekday=true
cursor-blink=true
cursor-size=24
enable-animations=true
font-antialiasing='rgba'
font-hinting='slight'
show-battery-percentage=true
text-scaling-factor=1.0
toolbar-style='both-horiz'

[org.gnome.settings-daemon.plugins.power]
power-button-action='interactive'
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
sleep-inactive-ac-timeout=0
sleep-inactive-battery-timeout=0
idle-dim=false
ambient-enabled=false
idle-brightness=30
power-saver-profile-on-low-battery=true

[org.gnome.desktop.session]
idle-delay=uint32 0
session-name='ubuntu'

[org.gnome.desktop.background]
picture-uri='file:///usr/share/backgrounds/OrioleMascot_by_Vladimir_Moskalenko_dark.png'
picture-uri-dark='file:///usr/share/backgrounds/OrioleMascot_by_Vladimir_Moskalenko_dark.png'
primary-color='#955733'
secondary-color='#955733'
picture-options='zoom'
color-shading-type='solid'

[org.gnome.settings-daemon.plugins.media-keys]
home=['<Super>e']
screensaver=['']
logout=['<Super>l']
custom-keybindings=['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']

[org.gnome.settings-daemon.plugins.media-keys.custom-keybindings.custom0]
binding='<Primary><Alt>Delete'
command='gnome-system-monitor'
name='System-Monitor'

[org.gnome.desktop.screensaver]
idle-activation-enabled=false
lock-enabled=false
logout-enabled=true
logout-delay=uint32 5
user-switch-enabled=true
picture-uri=''
picture-options='none'
color-shading-type='solid'
primary-color='#000000'
secondary-color='#000000'
lock-delay=uint32 0

[org.gnome.desktop.lockdown]
disable-user-switching=false
disable-lock-screen=true
disable-log-out=false
user-administration-disabled=false
disable-printing=false
disable-print-setup=false
disable-save-to-disk=false
disable-application-handlers=false
disable-command-line=false

[org.gnome.desktop.privacy]
show-full-name-in-top-bar=false
disable-microphone=false
disable-camera=false
remember-recent-files=true
remove-old-trash-files=false
remove-old-temp-files=false
old-files-age=uint32 7
report-technical-problems=false

[org.gnome.nautilus.preferences]
default-folder-viewer='list-view'
default-sort-order='type'
search-filter-time-type='last_modified'
show-create-link=true
show-delete-permanently=true
show-directory-item-counts='always'
show-image-thumbnails='always'
thumbnail-limit=uint64 100

[org.gnome.nautilus.list-view]
default-column-order=['name', 'size', 'type', 'owner', 'group', 'permissions', 'mime_type', 'where', 'date_modified', 'date_modified_with_time', 'date_accessed', 'recency', 'starred']
default-visible-columns=['name', 'size', 'type', 'date_modified']
default-zoom-level='small'
use-tree-view=false

[org.gnome.nautilus.icon-view]
default-zoom-level='large'
captions=['none', 'size', 'date_modified']

[org.gnome.terminal.legacy]
theme-variant='dark'
default-show-menubar=false
menu-accelerator-enabled=true
schema-version=uint32 3
shortcuts-enabled=true

[org.gnome.terminal.legacy.keybindings]
close-tab='<Primary>w'
close-window='<Primary>q'
copy='<Primary>c'
paste='<Primary>v'
new-tab='<Primary>t'
new-window='<Primary>n'
select-all='<Primary>a'

[org.gnome.shell]
always-show-log-out=true
disable-user-extensions=false
enabled-extensions=['user-theme@gnome-shell-extensions.gcampax.github.com']
favorite-apps=['org.gnome.Nautilus.desktop', 'firefox.desktop', 'gnome-control-center.desktop', 'org.gnome.Terminal.desktop']
welcome-dialog-last-shown-version='42.0'

[org.gnome.shell.app-switcher]
current-workspace-only=false

[org.gnome.mutter]
attach-modal-dialogs=false
center-new-windows=true
dynamic-workspaces=true
edge-tiling=true
workspaces-only-on-primary=true

[org.gnome.mutter.keybindings]
toggle-tiled-left=['<Super>Left']
toggle-tiled-right=['<Super>Right']

[org.gnome.SessionManager]
logout-prompt=false
EOSETTINGS

    # Schema-Override für den GDM-Anmeldebildschirm 
    cat > /usr/share/glib-2.0/schemas/91_gdm-settings.gschema.override <<EOGDM
# UbuntuFDE Schema Override für GDM

[org.gnome.desktop.input-sources:gdm]
sources=[('xkb', '${KEYBOARD_LAYOUT}')]
xkb-options=[]

[org.gnome.login-screen]
disable-user-list=true
banner-message-enable=false
banner-message-text='Zugriff nur für autorisierte Benutzer'
logo=''
enable-password-authentication=true
enable-fingerprint-authentication=true
enable-smartcard-authentication=false
allowed-failures=3

[org.gnome.desktop.interface:gdm]
color-scheme='prefer-dark'
gtk-theme='Adwaita-dark'
cursor-theme='Adwaita'
cursor-size=24
clock-show-seconds=true
clock-show-date=true
clock-show-weekday=true
icon-theme='Adwaita'

[org.gnome.desktop.background:gdm]
picture-uri=''
picture-uri-dark=''
primary-color='#000000'
secondary-color='#000000'
color-shading-type='solid'
picture-options='none'
EOGDM

    # Schemas kompilieren
    echo "Kompiliere glib-Schemas..."
    glib-compile-schemas /usr/share/glib-2.0/schemas/

# Installiere GNOME Shell Erweiterungen
    echo "Installiere GNOME Shell Erweiterungen..."
    
    # GNOME Shell Version ermitteln
    GNOME_VERSION=$(gnome-shell --version | cut -d ' ' -f 3 | cut -d '.' -f 1,2)
    GNOME_MAJOR_VERSION=$(echo $GNOME_VERSION | cut -d '.' -f 1)
    echo "Erkannte GNOME Shell Version: $GNOME_VERSION (Major: $GNOME_MAJOR_VERSION)"
    
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
        local uuid="$1"
        local gnome_version="$2"
        local extension_version
        
        if [[ "$uuid" == "$DASH_TO_PANEL_UUID" ]]; then
            if [[ -n "${DASH_TO_PANEL_VERSIONS[$gnome_version]}" ]]; then
                extension_version="${DASH_TO_PANEL_VERSIONS[$gnome_version]}"
            else
                extension_version="68"
                echo "Keine spezifische Version für GNOME $gnome_version gefunden, verwende Version $extension_version als Fallback"
            fi
            echo "https://extensions.gnome.org/extension-data/dash-to-paneljderose9.github.com.v${extension_version}.shell-extension.zip"
        
        elif [[ "$uuid" == "$USER_THEME_UUID" ]]; then
            if [[ -n "${USER_THEME_VERSIONS[$gnome_version]}" ]]; then
                extension_version="${USER_THEME_VERSIONS[$gnome_version]}"
            else
                extension_version="63"
                echo "Keine spezifische Version für GNOME $gnome_version gefunden, verwende Version $extension_version als Fallback"
            fi
            echo "https://extensions.gnome.org/extension-data/user-themegnome-shell-extensions.gcampax.github.com.v${extension_version}.shell-extension.zip"
        
        elif [[ "$uuid" == "$IMPATIENCE_UUID" ]]; then
            if [[ -n "${IMPATIENCE_VERSIONS[$gnome_version]}" ]]; then
                extension_version="${IMPATIENCE_VERSIONS[$gnome_version]}"
            else
                extension_version="28"
                echo "Keine spezifische Version für GNOME $gnome_version gefunden, verwende Version $extension_version als Fallback"
            fi
            echo "https://extensions.gnome.org/extension-data/impatiencegfxmonk.net.v${extension_version}.shell-extension.zip"
        
        elif [[ "$uuid" == "$BURN_MY_WINDOWS_UUID" ]]; then
            if [[ -n "${BURN_MY_WINDOWS_VERSIONS[$gnome_version]}" ]]; then
                extension_version="${BURN_MY_WINDOWS_VERSIONS[$gnome_version]}"
            else
                extension_version="46"
                echo "Keine spezifische Version für GNOME $gnome_version gefunden, verwende Version $extension_version als Fallback"
            fi
            echo "https://extensions.gnome.org/extension-data/burn-my-windowsschneegans.github.com.v${extension_version}.shell-extension.zip"
        
        elif [[ "$uuid" == "$SYSTEM_MONITOR_UUID" ]]; then
            if [[ -n "${SYSTEM_MONITOR_VERSIONS[$gnome_version]}" ]]; then
                extension_version="${SYSTEM_MONITOR_VERSIONS[$gnome_version]}"
                echo "https://extensions.gnome.org/extension-data/system-monitorgnome-shell-extensions.gcampax.github.com.v${extension_version}.shell-extension.zip"
            else
                # Da System Monitor nicht für alle Versionen verfügbar ist, geben wir hier eine Warnung aus
                echo "System Monitor ist nicht für GNOME $gnome_version verfügbar"
                return 1
            fi
        else
            echo "Unbekannte Extension UUID: $uuid"
            return 1
        fi
    }
    
    # Funktion zum Herunterladen und Installieren einer Extension
    install_extension() {
        local uuid="$1"
        local tmp_dir=$(mktemp -d)
        local tmp_zip="$tmp_dir/extension.zip"
        
        # Generiere die URL basierend auf UUID und GNOME Version
        local download_url=$(get_extension_url "$uuid" "$GNOME_MAJOR_VERSION")
        
        if [ -z "$download_url" ]; then
            echo "Konnte keine Download-URL für $uuid generieren - diese Extension wird übersprungen"
            rm -rf "$tmp_dir"
            return 1
        fi
        
        echo "Installiere Extension: $uuid"
        echo "Download URL: $download_url"
        
        # Entferne vorhandene Extension vollständig
        if [ -d "/usr/share/gnome-shell/extensions/$uuid" ]; then
            echo "Entferne vorherige Version von $uuid"
            rm -rf "/usr/share/gnome-shell/extensions/$uuid"
            sleep 1  # Kurze Pause, um sicherzustellen, dass Dateien gelöscht werden
        fi
        
        # Download und Installation
        if wget -q -O "$tmp_zip" "$download_url"; then
            echo "Download erfolgreich"
            
            # Erstelle Zielverzeichnis
            mkdir -p "/usr/share/gnome-shell/extensions/$uuid"
            
            # Entpacke die Extension
            if unzip -q -o "$tmp_zip" -d "/usr/share/gnome-shell/extensions/$uuid"; then
                echo "Extension erfolgreich entpackt"
                
                # Überprüfe, ob extension.js vorhanden ist
                if [ -f "/usr/share/gnome-shell/extensions/$uuid/extension.js" ]; then
                    echo "extension.js gefunden"
                else
                    echo "WARNUNG: extension.js nicht gefunden!"
                fi
                
                # Setze Berechtigungen
                chmod -R 755 "/usr/share/gnome-shell/extensions/$uuid"
                
                # Passe metadata.json an, um die GNOME-Version explizit zu unterstützen
                if [ -f "/usr/share/gnome-shell/extensions/$uuid/metadata.json" ]; then
                    echo "Passe metadata.json an, um GNOME $GNOME_VERSION zu unterstützen"
                    
                    # Sicherungskopie erstellen
                    cp "/usr/share/gnome-shell/extensions/$uuid/metadata.json" "/usr/share/gnome-shell/extensions/$uuid/metadata.json.bak"
                    
                    # Füge die aktuelle GNOME-Version zur Liste der unterstützten Versionen hinzu
                    jq --arg version "$GNOME_MAJOR_VERSION" --arg fullversion "$GNOME_VERSION" \
                       'if .["shell-version"] then .["shell-version"] += [$version, $fullversion] else .["shell-version"] = [$version, $fullversion] end' \
                       "/usr/share/gnome-shell/extensions/$uuid/metadata.json.bak" > "/usr/share/gnome-shell/extensions/$uuid/metadata.json"
                    
                    echo "metadata.json angepasst: Version $GNOME_VERSION hinzugefügt"
                else
                    echo "WARNUNG: metadata.json nicht gefunden"
                fi
                
                # Kompiliere Schemas, falls vorhanden
                if [ -d "/usr/share/gnome-shell/extensions/$uuid/schemas" ]; then
                    echo "Kompiliere GSettings Schemas"
                    glib-compile-schemas "/usr/share/gnome-shell/extensions/$uuid/schemas"
                fi
                
                echo "Extension $uuid erfolgreich installiert"
                return 0
            else
                echo "FEHLER: Konnte Extension nicht entpacken"
            fi
        else
            echo "FEHLER: Download fehlgeschlagen für URL: $download_url"
        fi
        
        rm -rf "$tmp_dir"
        return 1
    }
    
    # Extensions installieren
    echo "Installiere Dash to Panel..."
    install_extension "$DASH_TO_PANEL_UUID"
    
    echo "Installiere User Theme..."
    install_extension "$USER_THEME_UUID"
    
    echo "Installiere Impatience..."
    install_extension "$IMPATIENCE_UUID"
    
    echo "Installiere Burn My Windows..."
    install_extension "$BURN_MY_WINDOWS_UUID"
    
    echo "Installiere System Monitor..."
    install_extension "$SYSTEM_MONITOR_UUID"
    
    # Extensions aktivieren (für alle Benutzer)
    echo "Aktiviere Extensions für alle Benutzer..."
    mkdir -p /etc/dconf/db/local.d/
    cat > /etc/dconf/db/local.d/00-extensions <<EOE
[org/gnome/shell]
enabled-extensions=['$DASH_TO_PANEL_UUID', '$USER_THEME_UUID', '$IMPATIENCE_UUID', '$BURN_MY_WINDOWS_UUID', '$SYSTEM_MONITOR_UUID']

# Impatience Konfiguration für schnellere Animationen
[org/gnome/shell/extensions/impatience]
speed-factor=0.3

# Burn My Windows Konfiguration
[org/gnome/shell/extensions/burn-my-windows]
close-effect='pixelwipe'
open-effect='pixelwipe'
animation-time=300
pixelwipe-pixel-size=7
EOE

    # Erstelle einen Profilordner, damit dconf die Konfiguration anwendet
    mkdir -p /etc/dconf/profile/
    echo "user-db:user system-db:local" > /etc/dconf/profile/user

    # Stelle sicher, dass die Einstellungen für den aktuellen Benutzer sofort wirksam werden
    CURRENT_USER="${USERNAME}"
    CURRENT_USER_UID=$(id -u "$CURRENT_USER" 2>/dev/null || echo "1000")
    DBUS_SESSION="unix:path=/run/user/$CURRENT_USER_UID/bus"
    
    # Versuche, die Einstellungen anzuwenden
    sudo -u "$CURRENT_USER" env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION" gsettings set org.gnome.desktop.input-sources sources "[('xkb', '${KEYBOARD_LAYOUT}')]"
    sudo -u "$CURRENT_USER" env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION" gsettings set org.gnome.shell.extensions.impatience speed-factor 0.3 2>/dev/null || true
    sudo -u "$CURRENT_USER" env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION" gsettings set org.gnome.shell.extensions.burn-my-windows close-effect 'pixelwipe' 2>/dev/null || true
    sudo -u "$CURRENT_USER" env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION" gsettings set org.gnome.shell.extensions.burn-my-windows open-effect 'pixelwipe' 2>/dev/null || true
    sudo -u "$CURRENT_USER" env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION" gsettings set org.gnome.shell.extensions.burn-my-windows animation-time 300 2>/dev/null || true
    sudo -u "$CURRENT_USER" env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION" gsettings set org.gnome.shell.extensions.burn-my-windows pixelwipe-pixel-size 7 2>/dev/null || true

    # Dconf-Datenbank aktualisieren
    dconf update

    # Auto-Update für GNOME Shell Erweiterungen einrichten
    echo "Richte automatische Updates für GNOME Shell Erweiterungen ein..."
    
    # Skript erstellen, das Extensions aktualisiert
    cat > /usr/local/bin/update-gnome-extensions <<'EOSCRIPT'
#!/bin/bash

# GNOME Shell Version ermitteln
GNOME_VERSION=$(gnome-shell --version | cut -d ' ' -f 3 | cut -d '.' -f 1,2)
GNOME_MAJOR_VERSION=$(echo $GNOME_VERSION | cut -d '.' -f 1)
echo "Erkannte GNOME Shell Version: $GNOME_VERSION (Major: $GNOME_MAJOR_VERSION)"

# Extension-Daten definieren
DASH_TO_PANEL_UUID="dash-to-panel@jderose9.github.com"
USER_THEME_UUID="user-theme@gnome-shell-extensions.gcampax.github.com"
IMPATIENCE_UUID="impatience@gfxmonk.net"
BURN_MY_WINDOWS_UUID="burn-my-windows@schneegans.github.com"
SYSTEM_MONITOR_UUID="system-monitor@gnome-shell-extensions.gcampax.github.com"

# Version-Mapping für alle Extensions
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
    local uuid="$1"
    local gnome_version="$2"
    local extension_version
    
    if [[ "$uuid" == "$DASH_TO_PANEL_UUID" ]]; then
        if [[ -n "${DASH_TO_PANEL_VERSIONS[$gnome_version]}" ]]; then
            extension_version="${DASH_TO_PANEL_VERSIONS[$gnome_version]}"
        else
            extension_version="68"
            echo "Keine spezifische Version für GNOME $gnome_version gefunden, verwende Version $extension_version als Fallback"
        fi
        echo "https://extensions.gnome.org/extension-data/dash-to-paneljderose9.github.com.v${extension_version}.shell-extension.zip"
    
    elif [[ "$uuid" == "$USER_THEME_UUID" ]]; then
        if [[ -n "${USER_THEME_VERSIONS[$gnome_version]}" ]]; then
            extension_version="${USER_THEME_VERSIONS[$gnome_version]}"
        else
            extension_version="63"
            echo "Keine spezifische Version für GNOME $gnome_version gefunden, verwende Version $extension_version als Fallback"
        fi
        echo "https://extensions.gnome.org/extension-data/user-themegnome-shell-extensions.gcampax.github.com.v${extension_version}.shell-extension.zip"
    
    elif [[ "$uuid" == "$IMPATIENCE_UUID" ]]; then
        if [[ -n "${IMPATIENCE_VERSIONS[$gnome_version]}" ]]; then
            extension_version="${IMPATIENCE_VERSIONS[$gnome_version]}"
        else
            extension_version="28"
            echo "Keine spezifische Version für GNOME $gnome_version gefunden, verwende Version $extension_version als Fallback"
        fi
        echo "https://extensions.gnome.org/extension-data/impatiencegfxmonk.net.v${extension_version}.shell-extension.zip"
    
    elif [[ "$uuid" == "$BURN_MY_WINDOWS_UUID" ]]; then
        if [[ -n "${BURN_MY_WINDOWS_VERSIONS[$gnome_version]}" ]]; then
            extension_version="${BURN_MY_WINDOWS_VERSIONS[$gnome_version]}"
        else
            extension_version="46"
            echo "Keine spezifische Version für GNOME $gnome_version gefunden, verwende Version $extension_version als Fallback"
        fi
        echo "https://extensions.gnome.org/extension-data/burn-my-windowsschneegans.github.com.v${extension_version}.shell-extension.zip"
    
    elif [[ "$uuid" == "$SYSTEM_MONITOR_UUID" ]]; then
        if [[ -n "${SYSTEM_MONITOR_VERSIONS[$gnome_version]}" ]]; then
            extension_version="${SYSTEM_MONITOR_VERSIONS[$gnome_version]}"
            echo "https://extensions.gnome.org/extension-data/system-monitorgnome-shell-extensions.gcampax.github.com.v${extension_version}.shell-extension.zip"
        else
            # Da System Monitor nicht für alle Versionen verfügbar ist, geben wir hier eine Warnung aus
            echo "System Monitor ist nicht für GNOME $gnome_version verfügbar"
            return 1
        fi
    else
        echo "Unbekannte Extension UUID: $uuid"
        return 1
    fi
}

# Funktion zum Aktualisieren einer Extension
update_extension() {
    local uuid="$1"
    local tmp_dir=$(mktemp -d)
    local tmp_zip="$tmp_dir/extension.zip"
    
    echo "Prüfe Updates für $uuid (GNOME $GNOME_VERSION)..."
    
    # Generiere die URL basierend auf UUID und GNOME Version
    local download_url=$(get_extension_url "$uuid" "$GNOME_MAJOR_VERSION")
    
    if [ -z "$download_url" ]; then
        echo "Konnte keine Download-URL für $uuid generieren - diese Extension wird übersprungen"
        rm -rf "$tmp_dir"
        return 1
    fi
    
    # Prüfen, ob Aktualisierung notwendig ist
    local metadata_file="/usr/share/gnome-shell/extensions/${uuid}/metadata.json"
    local current_version="0"
    local extension_version
    
    if [ -f "$metadata_file" ]; then
        current_version=$(grep -o '"version": *[0-9]*' "$metadata_file" | grep -o '[0-9]*' || echo "0")
        
        # Extrahiere die Versionsnummer aus der URL
        extension_version=$(echo "$download_url" | grep -o 'v[0-9]*' | grep -o '[0-9]*')
        
        if [ "$current_version" = "$extension_version" ]; then
            echo "Extension $uuid ist bereits aktuell (Version $current_version)"
            rm -rf "$tmp_dir"
            return 0
        fi
    fi
    
    echo "Neue Version verfügbar: $extension_version (aktuell installiert: $current_version)"
    
    # Entferne vorhandene Extension vollständig
    if [ -d "/usr/share/gnome-shell/extensions/$uuid" ]; then
        echo "Entferne vorherige Version von $uuid"
        rm -rf "/usr/share/gnome-shell/extensions/$uuid"
        sleep 1  # Kurze Pause, um sicherzustellen, dass Dateien gelöscht werden
    fi
    
    # Download und Installation
    if wget -q -O "$tmp_zip" "$download_url"; then
        echo "Download erfolgreich"
        
        # Erstelle Zielverzeichnis
        mkdir -p "/usr/share/gnome-shell/extensions/$uuid"
        
        # Entpacke die Extension
        if unzip -q -o "$tmp_zip" -d "/usr/share/gnome-shell/extensions/$uuid"; then
            echo "Extension erfolgreich entpackt"
            
            # Überprüfe, ob extension.js vorhanden ist
            if [ -f "/usr/share/gnome-shell/extensions/$uuid/extension.js" ]; then
                echo "extension.js gefunden"
            else
                echo "WARNUNG: extension.js nicht gefunden!"
                ls -la "/usr/share/gnome-shell/extensions/$uuid/"
            fi
            
            # Setze Berechtigungen
            chmod -R 755 "/usr/share/gnome-shell/extensions/$uuid"
            
            # Passe metadata.json an, um die GNOME-Version explizit zu unterstützen
            if [ -f "/usr/share/gnome-shell/extensions/$uuid/metadata.json" ]; then
                echo "Passe metadata.json an, um GNOME $GNOME_VERSION zu unterstützen"
                
                # Sicherungskopie erstellen
                cp "/usr/share/gnome-shell/extensions/$uuid/metadata.json" "/usr/share/gnome-shell/extensions/$uuid/metadata.json.bak"
                
                # Füge die aktuelle GNOME-Version zur Liste der unterstützten Versionen hinzu
                if command -v jq &>/dev/null; then
                    jq --arg version "$GNOME_MAJOR_VERSION" --arg fullversion "$GNOME_VERSION" \
                       'if .["shell-version"] then .["shell-version"] += [$version, $fullversion] else .["shell-version"] = [$version, $fullversion] end' \
                       "/usr/share/gnome-shell/extensions/$uuid/metadata.json.bak" > "/usr/share/gnome-shell/extensions/$uuid/metadata.json"
                fi
                
                echo "metadata.json angepasst"
            fi
            
            # Kompiliere Schemas, falls vorhanden
            if [ -d "/usr/share/gnome-shell/extensions/$uuid/schemas" ]; then
                echo "Kompiliere GSettings Schemas"
                glib-compile-schemas "/usr/share/gnome-shell/extensions/$uuid/schemas"
            fi
            
            echo "Extension $uuid erfolgreich aktualisiert"
            return 0
        else
            echo "FEHLER: Konnte Extension nicht entpacken"
        fi
    else
        echo "FEHLER: Download fehlgeschlagen für URL: $download_url"
    fi
    
    rm -rf "$tmp_dir"
    return 1
}

# Aktualisiere die installierten Extensions
update_extension "$DASH_TO_PANEL_UUID"
update_extension "$USER_THEME_UUID"
update_extension "$IMPATIENCE_UUID"
update_extension "$BURN_MY_WINDOWS_UUID"
update_extension "$SYSTEM_MONITOR_UUID"

# Suche auch nach anderen installierten Extensions
echo "Suche nach anderen installierten GNOME Shell Erweiterungen..."
for ext_dir in /usr/share/gnome-shell/extensions/*; do
    if [ -d "$ext_dir" ]; then
        uuid=$(basename "$ext_dir")
        if [ "$uuid" != "$DASH_TO_PANEL_UUID" ] && [ "$uuid" != "$USER_THEME_UUID" ] && 
           [ "$uuid" != "$IMPATIENCE_UUID" ] && [ "$uuid" != "$BURN_MY_WINDOWS_UUID" ] && 
           [ "$uuid" != "$SYSTEM_MONITOR_UUID" ]; then
            echo "Gefunden: $uuid"
            # Hier könnten weitere Aktionen für andere Extensions ausgeführt werden
        fi
    fi
done

# GNOME Shell neustarten, wenn Änderungen vorgenommen wurden
if pgrep -x "gnome-shell" >/dev/null; then
    # Sanfter Neustart nur im X11-Modus möglich
    if [ "$XDG_SESSION_TYPE" = "x11" ]; then
        echo "Starte GNOME Shell neu..."
        sudo -u "${USERNAME}" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "${USERNAME}")/bus gnome-shell --replace &
    else
        echo "Bitte melde dich ab und wieder an, um die Änderungen zu übernehmen"
    fi
fi
EOSCRIPT

    chmod +x /usr/local/bin/update-gnome-extensions

    # systemd-Service erstellen
    cat > /etc/systemd/system/update-gnome-extensions.service <<'EOSERVICE'
[Unit]
Description=Update GNOME Shell Extensions
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/update-gnome-extensions
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOSERVICE

    # systemd-Timer erstellen (tägliche Prüfung)
    cat > /etc/systemd/system/update-gnome-extensions.timer <<'EOTIMER'
[Unit]
Description=Run GNOME Shell Extensions update daily

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOTIMER

    # Timer aktivieren
    systemctl enable update-gnome-extensions.timer    

    # Script erstellen für Umleitung des Sperr-Knopfes zum Benutzer-Wechsel
    echo "Erstelle ScreenLocker-Ersatz für Benutzer-Wechsel..."
    mkdir -p /usr/local/bin/
    cat > /usr/local/bin/gnome-session-handler.sh <<'EOSESSIONHANDLER'
#!/bin/bash

# Umleitung Bildschirmsperre -> Benutzerwechsel
# Verhindern, dass GNOME die Bildschirmsperre verwendet

# GNOME-Sitzung erkennen und DBus-Adresse ermitteln
for pid in $(pgrep -u "${USERNAME}" gnome-session); do
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "${USERNAME}")/bus"
    break
done

# DBus-Signal-Handler für Idle-Benachrichtigung
dbus-monitor --session "type='signal',interface='org.gnome.ScreenSaver'" | 
while read -r line; do
    if echo "$line" | grep -q "boolean true"; then
        # Bildschirmschoner aktiviert - stattdessen Benutzerwechsel auslösen
        sudo -u "${USERNAME}" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gdmflexiserver --startnew
    fi
done
EOSESSIONHANDLER

    chmod 755 /usr/local/bin/gnome-session-handler.sh

    # Autostart-Eintrag für alle Benutzer
    mkdir -p /etc/xdg/autostart/
    cat > /etc/xdg/autostart/gnome-session-handler.desktop <<EODESKTOP
[Desktop Entry]
Type=Application
Name=GNOME Session Handler
Comment=Handles GNOME session events
Exec=/usr/local/bin/gnome-session-handler.sh
Terminal=false
Hidden=false
X-GNOME-Autostart-Phase=Applications
NoDisplay=true
EODESKTOP

    chmod 644 /etc/xdg/autostart/gnome-session-handler.desktop

    # Zusätzlich direktes Setzen wichtiger Einstellungen per gsettings für den aktuellen Benutzer
    CURRENT_USER="${USERNAME}" || who | head -1 | awk '{print $1}')
    if [ -n "$CURRENT_USER" ]; then
        echo "Wende Einstellungen direkt für Benutzer $CURRENT_USER an..."
        USER_UID=$(id -u "$CURRENT_USER")
        
        # dconf/gsettings direkt für den Benutzer anwenden
        su - "$CURRENT_USER" -c "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$USER_UID/bus gsettings set org.gnome.gnome-session logout-prompt false"
        su - "$CURRENT_USER" -c "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$USER_UID/bus gsettings set org.gnome.SessionManager logout-prompt false"
        su - "$CURRENT_USER" -c "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$USER_UID/bus gsettings set org.gnome.desktop.wm.preferences focus-mode 'click'"
    fi

elif [ "$DESKTOP_ENV" = "kde" ]; then
    # KDE-spezifische Einstellungen
    echo "KDE-Einstellungen werden implementiert..."
    # Hier würden KDE-spezifische Einstellungen kommen

elif [ "$DESKTOP_ENV" = "xfce" ]; then
    # Xfce-spezifische Einstellungen
    echo "Xfce-Einstellungen werden implementiert..."
    # Hier würden Xfce-spezifische Einstellungen kommen
else
    echo "Keine bekannte Desktop-Umgebung gefunden."
fi

# Erstelle ein Benachrichtigungsfenster für den ersten Login
cat > /usr/local/bin/first-login-notification.sh <<'EOFIRST'
#!/bin/bash

# Versuchen, die korrekte Display-Umgebung zu ermitteln
if [ -z "$DISPLAY" ]; then
    # Finde den ersten aktiven X-Display
    for display in $(w -hs | grep -oP ':\d+' | sort | uniq); do
        export DISPLAY=$display
        break
    done

    # Wenn kein aktives Display gefunden wurde, versuche Standard-Display
    if [ -z "$DISPLAY" ]; then
        export DISPLAY=:0
    fi
fi

# Warten bis die Desktop-Umgebung vollständig geladen ist
sleep 3

# Nutzer-ID ermitteln (funktioniert auch bei root)
REAL_USER=$(who | grep "$DISPLAY" | head -n1 | awk '{print $1}')
USER_ID=$(id -u "$REAL_USER")

# Korrekte DBus-Adresse für den Benutzer setzen
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus"

# Prüfen, ob wir als root ausgeführt werden aber eigentlich ein Benutzer-Display ansprechen
if [ "$(id -u)" -eq 0 ] && [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
    # Führe das Skript als normaler Benutzer aus
    su - "$REAL_USER" -c "DISPLAY=$DISPLAY DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' GTK_THEME='Adwaita:dark' $0"
    exit $?
fi

# Hier läuft das Skript nun als normaler Benutzer
export GTK_THEME=Adwaita:dark

# Benutzer benachrichtigen mit YAD
yad --question \
    --title="Einrichtung" \
    --text="<b><big><span font_family='DejaVu Sans'>Systemanpassungen wurden durchgeführt!</span></big></b>\n\n\nEin Neustart ist nötig um alle Änderungen zu aktivieren.\n\nMöchtest Du das jetzt tun?\n\n" \
    --button="Später neu starten:1" \
    --button="Jetzt neu starten:0" \
    --center \
    --fixed \
    --width=500 \
    --borders=20 \
    --text-align=center \
    --buttons-layout=center \
    --skip-taskbar \
    --undecorated


if [ $? -eq 0 ]; then
    # Benutzer hat "Jetzt neu starten" gewählt
    # Entferne alle temporären Dateien
    rm -f ~/.config/autostart/first-login-notification.desktop
    
    # Zeige eine kurze Info und starte neu
    yad --info \
        --title="Neustart" \
        --text="\n\n<b><big><span font_family='DejaVu Sans'>Neustart!</span></big></b>\n\nDas System wird jetzt neu gestartet...\n\n" \
        --timeout=3 \
        --width=400 \
        --borders=20 \
        --text-align=center \
        --center \
        --fixed \
        --buttons-layout=hidden \
        --no-buttons \
        --skip-taskbar \
        --undecorated
    
    # Neustart durchführen
    systemctl reboot
else
    # Benutzer hat "Später neu starten" gewählt
    yad --info \
        --title="Information" \
        --text="<b><big><span font_family='DejaVu Sans'>Information!</span></big></b>\n\nBitte starte später manuell neu.\n\nDiese Benachrichtigung wird nicht erneut angezeigt.\n\n" \
        --width=400 \
        --borders=20 \
        --text-align=center \
        --center \
        --fixed \
        --button="OK:0" \
        --buttons-layout=center \
        --skip-taskbar \
        --undecorated
fi

# Entferne dieses Skript aus dem Autostart und sich selbst
rm -f ~/.config/autostart/first-login-notification.desktop
if [ "$0" != "/dev/stdin" ]; then
    rm -f "$0"
fi

exit 0
EOFIRST

# Mache das Skript ausführbar
chmod +x /usr/local/bin/first-login-notification.sh

# Erstelle einen Autostart-Eintrag für den Benutzer
mkdir -p /etc/skel/.config/autostart
cat > /etc/skel/.config/autostart/first-login-notification.desktop <<EOAUTO
[Desktop Entry]
Type=Application
Name=First Login Notification
Comment=Shows a notification after the first login
Exec=/usr/local/bin/first-login-notification.sh
Terminal=false
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOAUTO

# Kopiere den Autostart-Eintrag für bestehende Benutzer
for userdir in /home/*; do
    username=$(basename "$userdir")
    if [ -d "$userdir" ] && [ "$username" != "lost+found" ]; then
        mkdir -p "$userdir/.config/autostart"
        cp /etc/skel/.config/autostart/first-login-notification.desktop "$userdir/.config/autostart/"
        chown -R "$username:$username" "$userdir/.config"
    fi
done

# Aufräumen und Selbstzerstörung einrichten
echo "Einstellungen angewendet, entferne Autostart-Konfiguration."

# Entferne Autostart-Eintrag für dieses Skript
if [ -f /etc/xdg/autostart/post-install-settings.desktop ]; then
    rm -f /etc/xdg/autostart/post-install-settings.desktop
fi

# Selbstzerstörung für den nächsten Reboot
echo "#!/bin/bash
rm -f /usr/local/bin/post_install_settings.sh
rm -f \$0" > /usr/local/bin/cleanup_settings.sh
chmod 755 /usr/local/bin/cleanup_settings.sh

# Autostart für die Bereinigung
cat > /etc/xdg/autostart/cleanup-settings.desktop <<EOCLEANUP
[Desktop Entry]
Type=Application
Name=Cleanup Settings
Comment=Removes temporary settings files
Exec=/usr/local/bin/cleanup_settings.sh
Terminal=false
Hidden=false
X-GNOME-Autostart-Phase=Applications
EOCLEANUP

echo "Konfiguration abgeschlossen."

exit 0
EOPOSTSCRIPT