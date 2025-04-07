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
    #systemctl reboot
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