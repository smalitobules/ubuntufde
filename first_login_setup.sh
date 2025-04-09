#!/bin/bash
# First-Login-Setup für benutzerspezifische Einstellungen

# Protokollierung aktivieren
LOG_FILE="$HOME/.first-login-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "===== First-Login-Setup gestartet: $(date) ====="

# Hilfsfunktion für Progress
show_progress() {
    local percent=$1
    # Wird vom YAD Dialog ausgewertet
    echo $percent
}

# Sperrt alle Eingaben und zeigt einen Fortschrittsbalken
# Verwende YAD Dialog im Vollbildmodus
TITLE="System-Einrichtung"
MESSAGE="<big><b>System wird eingerichtet...</b></big>\n\nBitte warten Sie, bis dieser Vorgang abgeschlossen ist."
WIDTH=400
HEIGHT=200

# Starte YAD im Hintergrund und speichere die PID
(
    # Blockieren aller Eingaben (Vollbild mit wmctrl)
    (
        sleep 0.5  # Kurze Verzögerung, damit YAD starten kann
        # Vollbild aktivieren für das YAD-Fenster
        WID=$(xdotool search --name "$TITLE" | head -1)
        if [ -n "$WID" ]; then
            # Fenster im Vordergrund halten und maximieren
            wmctrl -i -r $WID -b add,fullscreen
            # Fenster im Fokus halten
            while pgrep -f "yad.*$TITLE" >/dev/null; do
                wmctrl -i -a $WID
                sleep 0.5
            done
        fi
    ) &
    
    # Fortschrittsbalken Konfiguration
    # Wird vom YAD Dialog alle 0.5 Sekunden ausgewertet
    show_progress 0

    sleep 1
    show_progress 5
    
    # Warten bis DBus vollständig initialisiert ist
    echo "Warte auf DBus-Initialisierung..."
    for i in {1..30}; do
        if dbus-send --session --dest=org.freedesktop.DBus --type=method_call --print-reply /org/freedesktop/DBus org.freedesktop.DBus.GetId >/dev/null 2>&1; then
            echo "DBus ist bereit nach $i Sekunden"
            break
        fi
        sleep 1
        if [ $i -eq 30 ]; then
            echo "DBus konnte nicht initialisiert werden, fahre trotzdem fort..."
        fi
    done
    
    show_progress 10
    
    # Warten auf GNOME-Shell
    echo "Warte auf GNOME-Shell..."
    for i in {1..30}; do
        if pgrep -x "gnome-shell" >/dev/null; then
            echo "GNOME-Shell läuft nach $i Sekunden"
            break
        fi
        sleep 1
        if [ $i -eq 30 ]; then
            echo "GNOME-Shell wurde nicht erkannt, fahre trotzdem fort..."
        fi
    done
    
    show_progress 15
    
    # Systemvariablen ermitteln
    DESKTOP_ENV=""
    KEYBOARD_LAYOUT="de"  # Standardwert, wird später überschrieben
    
    # Desktop-Umgebung erkennen
    if [ -f /usr/bin/gnome-shell ]; then
        DESKTOP_ENV="gnome"
        GNOME_VERSION=$(gnome-shell --version 2>/dev/null | cut -d ' ' -f 3 | cut -d '.' -f 1,2 || echo "")
        GNOME_MAJOR_VERSION=$(echo $GNOME_VERSION | cut -d '.' -f 1)
        echo "Erkannte GNOME Shell Version: $GNOME_VERSION (Major: $GNOME_MAJOR_VERSION)"
    elif [ -f /usr/bin/plasmashell ]; then
        DESKTOP_ENV="kde"
    elif [ -f /usr/bin/xfce4-session ]; then
        DESKTOP_ENV="xfce"
    else
        DESKTOP_ENV="unknown"
    fi
    echo "Desktop-Umgebung lokal erkannt: $DESKTOP_ENV"
    
    # Tastaturlayout aus System-Einstellungen ermitteln
    if [ -f /etc/default/keyboard ]; then
        source /etc/default/keyboard
        KEYBOARD_LAYOUT="$XKBLAYOUT"
        echo "Tastaturlayout aus System-Einstellungen: $KEYBOARD_LAYOUT"
    fi
    
    show_progress 20
    
    # Alle notwendigen gsettings anwenden
    echo "Wende benutzerspezifische Einstellungen an..."
    
    if [ "$DESKTOP_ENV" = "gnome" ]; then
        # Tastaturlayout
        gsettings set org.gnome.desktop.input-sources sources "[('xkb', '$KEYBOARD_LAYOUT')]"
        show_progress 25
        
        # GNOME-Erweiterungen aktivieren
        extensions=(
            'dash-to-panel@jderose9.github.com' 
            'user-theme@gnome-shell-extensions.gcampax.github.com'
            'impatience@gfxmonk.net'
            'burn-my-windows@schneegans.github.com'
            'system-monitor@gnome-shell-extensions.gcampax.github.com'
        )
        
        # Aktuell aktivierte Erweiterungen ermitteln
        current_exts=$(gsettings get org.gnome.shell enabled-extensions)
        
        # Neue Liste vorbereiten
        new_exts=$(echo $current_exts | sed 's/]$//')
        if [[ "$new_exts" == "[]" || "$new_exts" == "@as []" ]]; then
            new_exts="["
        else
            new_exts="$new_exts, "
        fi
        
        # Überprüfen und Erweiterungen hinzufügen
        echo "Aktiviere GNOME-Erweiterungen..."
        for ext in "${extensions[@]}"; do
            if [ -d "/usr/share/gnome-shell/extensions/$ext" ]; then
                if ! echo "$current_exts" | grep -q "$ext"; then
                    echo "Aktiviere $ext"
                    new_exts="$new_exts'$ext', "
                else
                    echo "$ext ist bereits aktiviert"
                fi
            else
                echo "Erweiterung $ext nicht gefunden, wird übersprungen"
            fi
        done
        new_exts="${new_exts%, }]"
        
        # Erweiterungen aktivieren
        gsettings set org.gnome.shell enabled-extensions "$new_exts"
        show_progress 35
        
        # Erweiterungseinstellungen konfigurieren
        echo "Konfiguriere Erweiterungen..."
        
        # Impatience (schnellere Animationen)
        if gsettings list-schemas | grep -q "org.gnome.shell.extensions.impatience"; then
            gsettings set org.gnome.shell.extensions.impatience speed-factor 0.3
        fi
        
        # Burn My Windows
        if gsettings list-schemas | grep -q "org.gnome.shell.extensions.burn-my-windows"; then
            gsettings set org.gnome.shell.extensions.burn-my-windows close-effect 'pixelwipe'
            gsettings set org.gnome.shell.extensions.burn-my-windows open-effect 'pixelwipe'
            gsettings set org.gnome.shell.extensions.burn-my-windows animation-time 300
            gsettings set org.gnome.shell.extensions.burn-my-windows pixelwipe-pixel-size 7
        fi
        
        show_progress 40
        
        # Dash to Panel
        if gsettings list-schemas | grep -q "org.gnome.shell.extensions.dash-to-panel"; then
            gsettings set org.gnome.shell.extensions.dash-to-panel panel-size 48
            gsettings set org.gnome.shell.extensions.dash-to-panel animate-show-apps true
            gsettings set org.gnome.shell.extensions.dash-to-panel appicon-margin 4
            gsettings set org.gnome.shell.extensions.dash-to-panel appicon-padding 4
            gsettings set org.gnome.shell.extensions.dash-to-panel dot-position 'BOTTOM'
            gsettings set org.gnome.shell.extensions.dash-to-panel dot-style-focused 'DOTS'
            gsettings set org.gnome.shell.extensions.dash-to-panel dot-style-unfocused 'DOTS'
            gsettings set org.gnome.shell.extensions.dash-to-panel focus-highlight true
            gsettings set org.gnome.shell.extensions.dash-to-panel isolate-workspaces true
        fi
        
        show_progress 45
        
        # Weitere GNOME-spezifische Einstellungen
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
        gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
        gsettings set org.gnome.desktop.session idle-delay 0
        gsettings set org.gnome.desktop.screensaver lock-enabled false
        gsettings set org.gnome.desktop.privacy show-full-name-in-top-bar false
        gsettings set org.gnome.desktop.interface clock-show-seconds true
        gsettings set org.gnome.desktop.interface clock-show-weekday true
        
        # Media Keys und Shortcuts
        gsettings set org.gnome.settings-daemon.plugins.media-keys home "['<Super>e']"
        
        show_progress 55
        
        # Nautilus-Einstellungen
        if command -v nautilus &>/dev/null; then
            gsettings set org.gnome.nautilus.preferences default-folder-viewer 'list-view'
            gsettings set org.gnome.nautilus.preferences default-sort-order 'type'
            gsettings set org.gnome.nautilus.preferences show-create-link true
            gsettings set org.gnome.nautilus.preferences show-delete-permanently true
            gsettings set org.gnome.nautilus.list-view default-zoom-level 'small'
            gsettings set org.gnome.nautilus.list-view use-tree-view false
        fi
        
        show_progress 65
        
        # Übersicht der aktivierten Erweiterungen ausgeben
        echo "Aktivierte GNOME-Erweiterungen:"
        gsettings get org.gnome.shell enabled-extensions
        
    elif [ "$DESKTOP_ENV" = "kde" ]; then
        # KDE-spezifische Einstellungen
        echo "KDE-spezifische Einstellungen werden angewendet..."
        # Hier kdeneon-Konfigurationen hinzufügen
        
    elif [ "$DESKTOP_ENV" = "xfce" ]; then
        # Xfce-spezifische Einstellungen
        echo "Xfce-spezifische Einstellungen werden angewendet..."
        # Hier xfce-Konfigurationen hinzufügen
    fi
    
    # Desktop-unabhängige Einstellungen
    show_progress 75

    # Validierung der Benutzereinstellungen
    validate_user_settings() {
        local errors=0
        local warnings=0
        local user_log_file="$HOME/.first-login-validation.log"
        
        echo "===== Validierung der Benutzereinstellungen =====" > "$user_log_file"
        echo "Gestartet am: $(date)" >> "$user_log_file"
        
        # 1. Prüfen, ob DBus korrekt funktioniert
        echo "Prüfe DBus-Funktionalität..." >> "$user_log_file"
        if ! dbus-send --session --dest=org.freedesktop.DBus --type=method_call --print-reply /org/freedesktop/DBus org.freedesktop.DBus.GetId > /dev/null 2>&1; then
            echo "FEHLER: DBus funktioniert nicht korrekt!" >> "$user_log_file"
            ((errors++))
        else
            echo "OK: DBus funktioniert." >> "$user_log_file"
        fi
        
        if [ "$DESKTOP_ENV" = "gnome" ]; then
            # 2. Prüfen, ob GNOME-Erweiterungen aktiviert wurden
            echo "Prüfe aktivierte GNOME-Erweiterungen..." >> "$user_log_file"
            enabled_extensions=$(gsettings get org.gnome.shell enabled-extensions)
            required_extensions=("dash-to-panel@jderose9.github.com" "user-theme@gnome-shell-extensions.gcampax.github.com")
            
            for ext in "${required_extensions[@]}"; do
                if ! echo "$enabled_extensions" | grep -q "$ext"; then
                    echo "WARNUNG: Erweiterung $ext ist nicht aktiviert!" >> "$user_log_file"
                    ((warnings++))
                else
                    echo "OK: Erweiterung $ext ist aktiviert." >> "$user_log_file"
                fi
            done
            
            # 3. Prüfen, ob die Tastatureinstellungen korrekt sind
            echo "Prüfe Tastaturlayout..." >> "$user_log_file"
            current_layout=$(gsettings get org.gnome.desktop.input-sources sources)
            expected_layout="[('xkb', '${KEYBOARD_LAYOUT}')]"
            
            if [ "$current_layout" != "$expected_layout" ]; then
                echo "WARNUNG: Falsches Tastaturlayout. Ist: $current_layout, Erwartet: $expected_layout" >> "$user_log_file"
                ((warnings++))
            else
                echo "OK: Tastaturlayout korrekt eingestellt." >> "$user_log_file"
            fi
            
            # 4. Prüfen, ob das Farbschema korrekt gesetzt wurde
            echo "Prüfe Farbschema..." >> "$user_log_file"
            current_scheme=$(gsettings get org.gnome.desktop.interface color-scheme)
            expected_scheme="'prefer-dark'"
            
            if [ "$current_scheme" != "$expected_scheme" ]; then
                echo "WARNUNG: Falsches Farbschema. Ist: $current_scheme, Erwartet: $expected_scheme" >> "$user_log_file"
                ((warnings++))
            else
                echo "OK: Farbschema korrekt eingestellt." >> "$user_log_file"
            fi
        fi
        
        # 5. Prüfen, ob die Desktop-Umgebung läuft
        echo "Prüfe Desktop-Umgebungs-Status..." >> "$user_log_file"
        if [ "$DESKTOP_ENV" = "gnome" ] && ! pgrep -x "gnome-shell" > /dev/null; then
            echo "FEHLER: GNOME-Shell scheint nicht zu laufen!" >> "$user_log_file"
            ((errors++))
        elif [ "$DESKTOP_ENV" = "kde" ] && ! pgrep -x "plasmashell" > /dev/null; then
            echo "FEHLER: KDE Plasma Shell scheint nicht zu laufen!" >> "$user_log_file"
            ((errors++))
        elif [ "$DESKTOP_ENV" = "xfce" ] && ! pgrep -x "xfwm4" > /dev/null; then
            echo "FEHLER: Xfce Window Manager scheint nicht zu laufen!" >> "$user_log_file"
            ((errors++))
        else
            echo "OK: Desktop-Umgebung läuft." >> "$user_log_file"
        fi
        
        # Ausgabe des Ergebnisses
        echo "===== Validierungszusammenfassung =====" >> "$user_log_file"
        if [ $errors -eq 0 ]; then
            if [ $warnings -eq 0 ]; then
                echo "ERFOLG: Alle Benutzereinstellungen wurden korrekt implementiert." >> "$user_log_file"
                echo "Benutzer-Setup erfolgreich abgeschlossen. Alle Prüfungen bestanden."
                return 0
            else
                echo "TEILWEISER ERFOLG: Benutzereinstellungen wurden mit $warnings Warnungen implementiert." >> "$user_log_file"
                echo "Benutzer-Setup mit $warnings Warnungen abgeschlossen."
                return 1
            fi
        else
            echo "FEHLER: $errors kritische Probleme bei der Benutzerkonfiguration gefunden." >> "$user_log_file"
            echo "WARNUNG: Benutzer-Setup nicht vollständig abgeschlossen. $errors Probleme und $warnings Warnungen gefunden."
            echo "Prüfen Sie die Logdatei für Details: $user_log_file"
            return 2
        fi
    }
    
    # GNOME-Shell neustarten, um Änderungen zu übernehmen
    echo "Überprüfe, ob GNOME-Shell-Neustart erforderlich ist..."
    NEEDS_RESTART=true
    SESSION_TYPE=$(echo $XDG_SESSION_TYPE)
    
    if [ "$DESKTOP_ENV" = "gnome" ]; then
        if [ "$SESSION_TYPE" = "x11" ]; then
            echo "X11-Sitzung erkannt, führe sanften GNOME-Shell-Neustart durch..."
            # Versuche einen sanften Neustart, falls in X11
            dbus-send --session --type=method_call --dest=org.gnome.Shell /org/gnome/Shell org.gnome.Shell.Eval string:'global.reexec_self()' &>/dev/null || true
            show_progress 85
            sleep 2
            NEEDS_RESTART=false
        elif [ "$SESSION_TYPE" = "wayland" ]; then
            echo "Wayland-Sitzung erkannt, kann GNOME-Shell nicht sanft neustarten."
            NEEDS_RESTART=true
        fi
    fi
    
    # Validiere die Benutzereinstellungen
    show_progress 95
    validate_result=$(validate_user_settings)
    validation_exit_code=$?
    
    # Bereite Zusammenfassung vor
    show_progress 100
    sleep 1
    echo "$validation_result"
    
    # Beenden des YAD-Dialogs
    ) | yad --progress \
        --title="$TITLE" \
        --text="$MESSAGE" \
        --width=$WIDTH \
        --height=$HEIGHT \
        --center \
        --auto-close \
        --auto-kill \
        --no-buttons \
        --undecorated \
        --fixed \
        --on-top \
        --skip-taskbar \
        --borders=20

# Nach dem YAD-Dialog: Zeige eine Zusammenfassung und validiere das Setup
if [ "$validation_exit_code" -eq 0 ]; then
    # Erfolgsmeldung
    yad --info \
        --title="Setup abgeschlossen" \
        --text="<b><big>System-Setup erfolgreich!</big></b>\n\nAlle Einstellungen wurden korrekt angewendet." \
        --button="OK":0 \
        --center --width=400 \
        --borders=20 \
        --text-align=center \
        --fixed \
        --on-top
        
    # Entferne dieses Skript aus dem Autostart
    rm -f "$HOME/.config/autostart/first-login-setup.desktop"
    
    # Selbstzerstörung mit Verzögerung einleiten
    (sleep 3 && sudo rm -f "$0") &
elif [ "$validation_exit_code" -eq 1 ]; then
    # Teilweise erfolgreich mit Warnungen
    yad --warning \
        --title="Setup mit Warnungen abgeschlossen" \
        --text="<b><big>System-Setup teilweise abgeschlossen!</big></b>\n\nEinige Einstellungen konnten nicht vollständig angewendet werden.\nDas System ist aber funktionsfähig.\n\nSiehe: $HOME/.first-login-validation.log" \
        --button="OK":0 \
        --center --width=450 \
        --borders=20 \
        --text-align=center \
        --fixed \
        --on-top
        
    # Entferne dieses Skript aus dem Autostart
    rm -f "$HOME/.config/autostart/first-login-setup.desktop"
    
    # Selbstzerstörung mit Verzögerung einleiten
    (sleep 3 && sudo rm -f "$0") &
else
    # Fehlgeschlagen
    yad --error \
        --title="Setup unvollständig" \
        --text="<b><big>System-Setup unvollständig!</big></b>\n\nKritische Einstellungen konnten nicht angewendet werden.\n\nBitte prüfen Sie die Logdatei: $HOME/.first-login-validation.log\n\nDas Setup wird beim nächsten Login erneut versucht." \
        --button="OK":0 \
        --center --width=450 \
        --borders=20 \
        --text-align=center \
        --fixed \
        --on-top
    
    # Skript bleibt für einen weiteren Versuch erhalten
    echo "Setup unvollständig. Das Skript bleibt für einen weiteren Versuch erhalten."
fi

# Beenden mit entsprechendem Exitcode
exit $validation_exit_code
EOLOGINSETUP