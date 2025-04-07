#!/bin/bash
# Standalone System-Einstellungen - Direktes Ausführen ohne Installationsumgebung

# Prüfen, ob das Skript mit Root-Rechten ausgeführt wird
if [ "$(id -u)" -ne 0 ]; then
    echo "Dieses Skript muss mit Root-Rechten ausgeführt werden."
    echo "Erneuter Start mit sudo..."
    sudo "$0"
    exit $?
fi

# Fortschritt protokollieren
log_progress() {
    echo "[FORTSCHRITT] $1"
}

log_info() {
    echo "[INFO] $1"
}

show_progress() {
    echo "Fortschritt: $1%"
}

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
    log_progress "Konfiguriere GNOME-Einstellungen..."
    
    # Directory für gsettings-override erstellen
    mkdir -p /usr/share/glib-2.0/schemas/
    
    # Erstelle Schema-Override-Datei für allgemeine GNOME-Einstellungen
    cat > /usr/share/glib-2.0/schemas/90_ubuntu-fde.gschema.override <<EOSETTINGS
# Ubuntu FDE Schema Override für GNOME

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
titlebar-font='Ubuntu Bold 11'

[org.gnome.desktop.interface]
color-scheme='prefer-dark'
gtk-theme='Adwaita-dark'
accent-color='brown'
cursor-theme='Adwaita'
clock-show-seconds=true
clock-show-weekday=true
cursor-blink=true
cursor-size=24
document-font-name='Ubuntu 11'
enable-animations=true
font-antialiasing='rgba'
font-hinting='slight'
font-name='Ubuntu 11'
monospace-font-name='Ubuntu Mono 13'
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
favorite-apps=['org.gnome.Nautilus.desktop', 'thorium-browser.desktop', 'gnome-control-center.desktop', 'org.gnome.Terminal.desktop']
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
# Ubuntu FDE Schema Override für GDM

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
font-name='Ubuntu 11'
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
    log_progress "Kompiliere glib-Schemas..."
    glib-compile-schemas /usr/share/glib-2.0/schemas/

    # Script erstellen für Umleitung des Sperr-Knopfes zum Benutzer-Wechsel
    log_progress "Erstelle ScreenLocker-Ersatz für Benutzer-Wechsel..."
    mkdir -p /usr/local/bin/
    cat > /usr/local/bin/gnome-session-handler.sh <<'EOSESSIONHANDLER'
#!/bin/bash

# Umleitung Bildschirmsperre -> Benutzerwechsel
# Verhindern, dass GNOME die Bildschirmsperre verwendet

# GNOME-Sitzung erkennen und DBus-Adresse ermitteln
for pid in $(pgrep -u $(logname) gnome-session); do
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u $(logname))/bus"
    break
done

# DBus-Signal-Handler für Idle-Benachrichtigung
dbus-monitor --session "type='signal',interface='org.gnome.ScreenSaver'" | 
while read -r line; do
    if echo "$line" | grep -q "boolean true"; then
        # Bildschirmschoner aktiviert - stattdessen Benutzerwechsel auslösen
        sudo -u $(logname) DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gdmflexiserver --startnew
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

    # GDM automatische Anmeldung konfigurieren
    log_progress "Konfiguriere GDM für automatische Anmeldung..."
    if [ -f /etc/gdm3/custom.conf ]; then
        # Username für automatische Anmeldung ermitteln (erster Benutzer im /home)
        AUTO_USER=$(ls /home/ | grep -v lost+found | head -1)
        
        # Sicherstellen, dass die Abschnitte existieren
        grep -q '^\[daemon\]' /etc/gdm3/custom.conf || echo -e "\n[daemon]" >> /etc/gdm3/custom.conf
        
        # Kommentierte Zeilen entfernen und neue Konfiguration setzen
        sed -i '/^#\?AutomaticLoginEnable/d' /etc/gdm3/custom.conf
        sed -i '/^#\?AutomaticLogin/d' /etc/gdm3/custom.conf
        sed -i '/^#\?WaylandEnable/d' /etc/gdm3/custom.conf
        
        # Einstellungen zur [daemon] Sektion hinzufügen
        sed -i '/^\[daemon\]/a AutomaticLoginEnable=true' /etc/gdm3/custom.conf
        sed -i "/^\[daemon\]/a AutomaticLogin=$AUTO_USER" /etc/gdm3/custom.conf
        sed -i '/^\[daemon\]/a WaylandEnable=true' /etc/gdm3/custom.conf
    else
        # Falls die Datei nicht existiert, komplett neu erstellen
        mkdir -p /etc/gdm3
        AUTO_USER=$(ls /home/ | grep -v lost+found | head -1)
        cat > /etc/gdm3/custom.conf <<EOF
# GDM configuration storage
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=${AUTO_USER}
WaylandEnable=true

[security]
DisallowTCP=true
AllowRoot=false

[xdmcp]
Enable=false

[chooser]
Hosts=
EOF
    fi

    # Zusätzlich direktes Setzen wichtiger Einstellungen per gsettings für den aktuellen Benutzer
    CURRENT_USER=$(logname || who | head -1 | awk '{print $1}')
    if [ -n "$CURRENT_USER" ]; then
        log_progress "Wende Einstellungen direkt für Benutzer $CURRENT_USER an..."
        USER_UID=$(id -u "$CURRENT_USER")
        
        # dconf/gsettings direkt für den Benutzer anwenden
        su - "$CURRENT_USER" -c "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$USER_UID/bus gsettings set org.gnome.gnome-session logout-prompt false"
        su - "$CURRENT_USER" -c "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$USER_UID/bus gsettings set org.gnome.SessionManager logout-prompt false"
        su - "$CURRENT_USER" -c "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$USER_UID/bus gsettings set org.gnome.desktop.wm.preferences focus-mode 'click'"
    fi

elif [ "$DESKTOP_ENV" = "kde" ]; then
    # KDE-spezifische Einstellungen
    log_progress "KDE-Einstellungen werden implementiert..."
    # Hier würden KDE-spezifische Einstellungen kommen

elif [ "$DESKTOP_ENV" = "xfce" ]; then
    # Xfce-spezifische Einstellungen
    log_progress "Xfce-Einstellungen werden implementiert..."
    # Hier würden Xfce-spezifische Einstellungen kommen
else
    log_info "Keine bekannte Desktop-Umgebung gefunden."
fi

log_info "Systemeinstellungen erfolgreich angewendet."
show_progress 100

# Frage nach Systemneustart mit nur einem Tastendruck
echo -e "\nMöchtest du das System jetzt neu starten, um alle Änderungen zu aktivieren? (j/n)"
read -n 1 -r restart_system
echo # Neue Zeile für bessere Lesbarkeit

if [[ "$restart_system" =~ ^[Jj]$ ]]; then
    log "Systemneustart wird durchgeführt..."
    echo "Das System wird jetzt neu gestartet..."
    sleep 2
    reboot
else
    echo "Bitte starte das System später neu, um alle Änderungen vollständig zu aktivieren."
fi