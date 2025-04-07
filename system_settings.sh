#!/bin/bash
# GNOME-Einstellungen Standalone-Skript

# Benutzername festlegen - ersetze mit deinem Benutzernamen
USERNAME="admin"

# Erstelle einen systemd-Dienst, der auf GNOME-Sitzungsereignisse reagiert
echo "Erstelle alternativen Screen-Idle-Handler mit systemd..."

# Erstelle einen systemd-Dienst für Benutzer
mkdir -p /etc/systemd/user/
cat > /etc/systemd/user/gnome-idle-handler.service <<EOF
[Unit]
Description=GNOME Idle Handler Service
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gnome-idle-handler.sh
Restart=on-failure

[Install]
WantedBy=gnome-session.target
EOF

# Erstelle das Skript
mkdir -p /usr/local/bin/
cat > /usr/local/bin/gnome-idle-handler.sh <<'EOF'
#!/bin/bash

# Funktion zum Abfangen von SIGTERM
cleanup() {
    exit 0
}

# Signal-Handler
trap cleanup SIGTERM SIGINT

# Timeout überwachen - nutzt GNOME-Ereignisse
monitor_timeout() {
    # Registriere für Änderungen der Power-Einstellungen
    gsettings monitor org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout | while read -r change; do
        setup_idle_timer
    done &
    
    # Initiale Einrichtung
    setup_idle_timer
    
    # Warte auf Beendigung
    wait
}

# Timer basierend auf Timeout einrichten
setup_idle_timer() {
    # Aktuelle Timeout-Einstellung abrufen
    timeout=$(gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout)
    timeout=$(echo $timeout | sed 's/uint32 //')
    
    # Wenn ein timeout aktiv ist, registriere beim Session-Manager
    if [ "$timeout" -gt 0 ]; then
        # Berechne Leerlaufzeit (in Sekunden) - ziehe 5 Sekunden ab, um vor dem Standard-Timeout zu handeln
        idle_seconds=$((timeout - 5))
        if [ "$idle_seconds" -lt 5 ]; then
            idle_seconds=5
        fi
        
        # Registriere unseren benutzerdefinierten Idle-Handler
        dbus-send --session --dest=org.gnome.SessionManager \
                  --type=method_call \
                  /org/gnome/SessionManager \
                  org.gnome.SessionManager.RegisterClient \
                  string:"idle-handler" \
                  string:""
        
        # Jetzt einfach warten, bis die Systemereignisse uns signalisieren
        sleep infinity &
        wait $!
    else
        # Kein Timeout - nichts zu tun
        sleep infinity &
        wait $!
    fi
}

# DBus-Signal-Handler für Idle-Benachrichtigung
dbus-monitor --session "type='signal',interface='org.gnome.ScreenSaver'" | while read -r line; do
    if echo "$line" | grep -q "boolean true"; then
        # Screen Saver aktiviert - wir wollen stattdessen den Benutzerwechsel
        # Bildschirmschoner beenden und Benutzerwechsel starten
        gdmflexiserver --startnew || gnome-session-quit --logout
    fi
done &

# Starte die Überwachung
monitor_timeout
EOF

chmod +x /usr/local/bin/gnome-idle-handler.sh

# Aktiviere den Dienst für alle Benutzer
systemctl --global enable gnome-idle-handler.service

echo "Konfiguriere Gnome-Standardeinstellungen systemweit..."

# Verzeichnisstruktur erstellen
mkdir -p /etc/dconf/profile
mkdir -p /etc/dconf/db/local.d
mkdir -p /etc/dconf/db/gdm.d

# Profile-Datei erstellen (user)
cat > /etc/dconf/profile/user <<EOF
user-db:user
system-db:local
EOF

# GDM-Profil erstellen
cat > /etc/dconf/profile/gdm <<EOF
user-db:user
system-db:gdm
file-db:/usr/share/gdm/greeter-dconf-defaults
EOF

# Systemweite Einstellungen erstellen
cat > /etc/dconf/db/local.d/00-system-settings <<EOF
# Fensterknöpfe (Minimieren, Maximieren, Schließen) anzeigen
[org/gnome/desktop/wm/preferences]
button-layout='appmenu:minimize,maximize,close'
focus-mode='sloppy'
auto-raise=true
auto-raise-delay=500

# Dunkles Theme aktivieren
[org/gnome/desktop/interface]
color-scheme='prefer-dark'
gtk-theme='Adwaita-dark'

# Bildschirm nie ausschalten
[org/gnome/settings-daemon/plugins/power]
power-button-action='interactive'
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
sleep-inactive-ac-timeout=0
sleep-inactive-battery-timeout=0
idle-dim=false

# Bildschirm-Ausschaltverhalten konfigurieren
[org/gnome/desktop/session]
idle-delay=uint32 0

# Desktop-Hintergrund
[org/gnome/desktop/background]
picture-uri='file:///usr/share/backgrounds/OrioleMascot_by_Vladimir_Moskalenko_dark.png'
picture-uri-dark='file:///usr/share/backgrounds/OrioleMascot_by_Vladimir_Moskalenko_dark.png'

# Tastenkombination Nautilus öffnen
[org/gnome/settings-daemon/plugins/media-keys]
home=['<Super>e']
screensaver=['']

# Tastenkombination für Benutzerwechsel
[org/gnome/shell/keybindings]
switch-user=['<Super>l']

# Standardaktion bei Bildschirmsperre umstellen
[org/gnome/desktop/screensaver]
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

# Benutzerwechsel erlauben, aber Bildschirmsperre vermeiden
[org/gnome/desktop/lockdown]
disable-user-switching=false
disable-lock-screen=true
disable-log-out=false
user-administration-disabled=true
disable-printing=false
disable-print-setup=false

# Privacy-Einstellungen
[org/gnome/desktop/privacy]
show-full-name-in-top-bar=false

# Nautilus-Einstellungen
[org/gnome/nautilus/preferences]
default-folder-viewer='list-view'
search-filter-time-type='last_modified'
show-create-link=true
show-delete-permanently=true

# Terminal-Einstellungen
[org/gnome/terminal/legacy]
theme-variant='dark'
EOF

# GDM-Einstellungen (Login-Bildschirm)
cat > /etc/dconf/db/gdm.d/01-gdm-settings <<EOF
[org/gnome/login-screen]
disable-user-list=true
banner-message-enable=false
banner-message-text='Zugriff nur für autorisierte Benutzer'
logo=''

[org/gnome/desktop/interface]
color-scheme='prefer-dark'
gtk-theme='Adwaita-dark'

[org/gnome/desktop/background]
picture-uri=''
primary-color='#000000'
secondary-color='#000000'
color-shading-type='solid'
picture-options='none'
EOF

# Automatische Anmeldung für den erstellten Benutzer konfigurieren
mkdir -p /etc/gdm3/
cat > /etc/gdm3/custom.conf <<EOF
# GDM configuration storage
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=${USERNAME}
WaylandEnable=true

[security]
DisallowTCP=true
AllowRoot=false

[xdmcp]
Enable=false

[chooser]
Hosts=
EOF

# Datenbankaktualisierung erzwingen
dconf update

# Individuelle Benutzereinstellungen (für den ersten Login)
mkdir -p /home/${USERNAME}/.config/dconf/

# Sicherstellen, dass die Benutzereinstellungen als Vorlage richtig gesetzt werden
cat > /home/${USERNAME}/.config/dconf/user <<EOF
# Dies ist eine Vorlage für die Benutzereinstellungen
# Die tatsächlichen Einstellungen werden bei der ersten Anmeldung erstellt
EOF

# gsettings-Befehle für den neu erstellten Benutzer direkt anwenden
sudo -u ${USERNAME} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u ${USERNAME})/bus gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
sudo -u ${USERNAME} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u ${USERNAME})/bus gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
sudo -u ${USERNAME} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u ${USERNAME})/bus gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'

# Einstellungen sofort aktivieren
echo "Reload dconf Einstellungen..."
dconf update

# GNOME Shell Extensions Registry Settings
mkdir -p /home/${USERNAME}/.local/share/gnome-shell/extensions/
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.local/

# Benutzer zur Gruppe plugdev hinzufügen (falls noch nicht geschehen)
usermod -a -G plugdev ${USERNAME}

# Systemd-Service zum Laden der dconf-Einstellungen nach dem Start erstellen
cat > /etc/systemd/system/dconf-update.service <<EOF
[Unit]
Description=Update dconf databases at startup
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/dconf update
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Service aktivieren
systemctl enable dconf-update.service

echo "GNOME-Einstellungen wurden erfolgreich konfiguriert."