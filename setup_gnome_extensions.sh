#!/bin/bash

# Prüfe, ob das Skript mit Root-Rechten ausgeführt wird
if [ "$(id -u)" -ne 0 ]; then
    echo "Dieses Skript muss mit Root-Rechten ausgeführt werden (sudo)."
    exit 1
fi

# Logdatei definieren
LOGFILE="/var/log/gnome-extensions-setup.log"
rm -f "$LOGFILE"  # Log-Datei zurücksetzen

# Logging-Funktion
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOGFILE"
}

# GNOME Shell Version ermitteln
GNOME_VERSION=$(gnome-shell --version | cut -d ' ' -f 3 | cut -d '.' -f 1,2)
GNOME_MAJOR_VERSION=$(echo $GNOME_VERSION | cut -d '.' -f 1)
log "Erkannte GNOME Shell Version: $GNOME_VERSION (Major: $GNOME_MAJOR_VERSION)"

# Abhängigkeiten installieren
log "Installiere Abhängigkeiten..."
apt-get update && apt-get install -y curl jq unzip wget gir1.2-gtop-2.0 libgtop-2.0-11

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
            log "Keine spezifische Version für GNOME $gnome_version gefunden, verwende Version $extension_version als Fallback"
        fi
        echo "https://extensions.gnome.org/extension-data/dash-to-paneljderose9.github.com.v${extension_version}.shell-extension.zip"
    
    elif [[ "$uuid" == "$USER_THEME_UUID" ]]; then
        if [[ -n "${USER_THEME_VERSIONS[$gnome_version]}" ]]; then
            extension_version="${USER_THEME_VERSIONS[$gnome_version]}"
        else
            extension_version="63"
            log "Keine spezifische Version für GNOME $gnome_version gefunden, verwende Version $extension_version als Fallback"
        fi
        echo "https://extensions.gnome.org/extension-data/user-themegnome-shell-extensions.gcampax.github.com.v${extension_version}.shell-extension.zip"
    
    elif [[ "$uuid" == "$IMPATIENCE_UUID" ]]; then
        if [[ -n "${IMPATIENCE_VERSIONS[$gnome_version]}" ]]; then
            extension_version="${IMPATIENCE_VERSIONS[$gnome_version]}"
        else
            extension_version="28"
            log "Keine spezifische Version für GNOME $gnome_version gefunden, verwende Version $extension_version als Fallback"
        fi
        echo "https://extensions.gnome.org/extension-data/impatiencegfxmonk.net.v${extension_version}.shell-extension.zip"
    
    elif [[ "$uuid" == "$BURN_MY_WINDOWS_UUID" ]]; then
        if [[ -n "${BURN_MY_WINDOWS_VERSIONS[$gnome_version]}" ]]; then
            extension_version="${BURN_MY_WINDOWS_VERSIONS[$gnome_version]}"
        else
            extension_version="46"
            log "Keine spezifische Version für GNOME $gnome_version gefunden, verwende Version $extension_version als Fallback"
        fi
        echo "https://extensions.gnome.org/extension-data/burn-my-windowsschneegans.github.com.v${extension_version}.shell-extension.zip"
    
    elif [[ "$uuid" == "$SYSTEM_MONITOR_UUID" ]]; then
        if [[ -n "${SYSTEM_MONITOR_VERSIONS[$gnome_version]}" ]]; then
            extension_version="${SYSTEM_MONITOR_VERSIONS[$gnome_version]}"
            echo "https://extensions.gnome.org/extension-data/system-monitorgnome-shell-extensions.gcampax.github.com.v${extension_version}.shell-extension.zip"
        else
            # Da System Monitor nicht für alle Versionen verfügbar ist, geben wir hier eine Warnung aus
            log "System Monitor ist nicht für GNOME $gnome_version verfügbar"
            return 1
        fi
    else
        log "Unbekannte Extension UUID: $uuid"
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
        log "Konnte keine Download-URL für $uuid generieren - diese Extension wird übersprungen"
        rm -rf "$tmp_dir"
        return 1
    fi
    
    log "Installiere Extension: $uuid"
    log "Download URL: $download_url"
    
    # Entferne vorhandene Extension vollständig
    if [ -d "/usr/share/gnome-shell/extensions/$uuid" ]; then
        log "Entferne vorherige Version von $uuid"
        rm -rf "/usr/share/gnome-shell/extensions/$uuid"
        sleep 1  # Kurze Pause, um sicherzustellen, dass Dateien gelöscht werden
    fi
    
    # Download und Installation
    if wget -q -O "$tmp_zip" "$download_url"; then
        log "Download erfolgreich"
        
        # Erstelle Zielverzeichnis
        mkdir -p "/usr/share/gnome-shell/extensions/$uuid"
        
        # Entpacke die Extension
        if unzip -q -o "$tmp_zip" -d "/usr/share/gnome-shell/extensions/$uuid"; then
            log "Extension erfolgreich entpackt"
            
            # Überprüfe, ob extension.js vorhanden ist
            if [ -f "/usr/share/gnome-shell/extensions/$uuid/extension.js" ]; then
                log "extension.js gefunden"
            else
                log "WARNUNG: extension.js nicht gefunden! Liste der Dateien:"
                find "/usr/share/gnome-shell/extensions/$uuid" -type f | head -n 10 >> "$LOGFILE"
            fi
            
            # Setze Berechtigungen
            chmod -R 755 "/usr/share/gnome-shell/extensions/$uuid"
            
            # Passe metadata.json an, um die GNOME-Version explizit zu unterstützen
            if [ -f "/usr/share/gnome-shell/extensions/$uuid/metadata.json" ]; then
                log "Passe metadata.json an, um GNOME $GNOME_VERSION zu unterstützen"
                
                # Sicherungskopie erstellen
                cp "/usr/share/gnome-shell/extensions/$uuid/metadata.json" "/usr/share/gnome-shell/extensions/$uuid/metadata.json.bak"
                
                # Füge die aktuelle GNOME-Version zur Liste der unterstützten Versionen hinzu
                jq --arg version "$GNOME_MAJOR_VERSION" --arg fullversion "$GNOME_VERSION" \
                   'if .["shell-version"] then .["shell-version"] += [$version, $fullversion] else .["shell-version"] = [$version, $fullversion] end' \
                   "/usr/share/gnome-shell/extensions/$uuid/metadata.json.bak" > "/usr/share/gnome-shell/extensions/$uuid/metadata.json"
                
                log "metadata.json angepasst: Version $GNOME_VERSION hinzugefügt"
                grep -A5 "shell-version" "/usr/share/gnome-shell/extensions/$uuid/metadata.json" >> "$LOGFILE"
            else
                log "WARNUNG: metadata.json nicht gefunden"
            fi
            
            # Kompiliere Schemas, falls vorhanden
            if [ -d "/usr/share/gnome-shell/extensions/$uuid/schemas" ]; then
                log "Kompiliere GSettings Schemas"
                glib-compile-schemas "/usr/share/gnome-shell/extensions/$uuid/schemas"
            fi
            
            log "Extension $uuid erfolgreich installiert"
            return 0
        else
            log "FEHLER: Konnte Extension nicht entpacken"
        fi
    else
        log "FEHLER: Download fehlgeschlagen für URL: $download_url"
    fi
    
    rm -rf "$tmp_dir"
    return 1
}

# Extensions installieren
log "Installiere Dash to Panel..."
install_extension "$DASH_TO_PANEL_UUID"

log "Installiere User Theme..."
install_extension "$USER_THEME_UUID"

log "Installiere Impatience..."
install_extension "$IMPATIENCE_UUID"

log "Installiere Burn My Windows..."
install_extension "$BURN_MY_WINDOWS_UUID"

log "Installiere System Monitor..."
install_extension "$SYSTEM_MONITOR_UUID"

# Extensions aktivieren (für alle Benutzer)
log "Aktiviere Extensions für alle Benutzer..."
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
echo "user-db:user
system-db:local" > /etc/dconf/profile/user

# Stelle sicher, dass die Einstellungen für den aktuellen Benutzer sofort wirksam werden
CURRENT_USER=$(logname)
sudo -u $CURRENT_USER dbus-launch --exit-with-session gsettings set org.gnome.shell.extensions.impatience speed-factor 0.3
sudo -u $CURRENT_USER dbus-launch --exit-with-session gsettings set org.gnome.shell.extensions.burn-my-windows close-effect 'pixelwipe'
sudo -u $CURRENT_USER dbus-launch --exit-with-session gsettings set org.gnome.shell.extensions.burn-my-windows open-effect 'pixelwipe'
sudo -u $CURRENT_USER dbus-launch --exit-with-session gsettings set org.gnome.shell.extensions.burn-my-windows animation-time 300
sudo -u $CURRENT_USER dbus-launch --exit-with-session gsettings set org.gnome.shell.extensions.burn-my-windows pixelwipe-pixel-size 7

# Dconf-Datenbank aktualisieren
dconf update

# Auto-Update für GNOME Shell Erweiterungen einrichten
log "Richte automatische Updates für GNOME Shell Erweiterungen ein..."

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
        sudo -u $(logname) DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u $(logname))/bus gnome-shell --replace &
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