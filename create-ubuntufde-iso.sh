#!/bin/bash
# Skript zur Erstellung einer minimalen Ubuntu ISO mit Cubic

set -e

# Prüfen, ob als root ausgeführt
if [ "$(id -u)" -ne 0 ]; then
    echo "Dieses Skript muss als root ausgeführt werden."
    exit 1
fi

# Benötigte Pakete installieren
apt update
apt install -y cubic wget genisoimage isolinux xorriso

# Arbeitsverzeichnisse erstellen
WORK_DIR="/tmp/cubic_iso"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Ubuntu Server ISO verwenden (liegt bereits im Home-Verzeichnis)
ISO_NAME="/root/ubuntu-24.10-live-server-amd64.iso"
if [ ! -f "$ISO_NAME" ]; then
    echo "ISO nicht gefunden: $ISO_NAME"
    exit 1
fi

# Cubic starten (im CLI-Modus für Automatisierung)
echo "Starte Cubic im CLI-Modus..."
mkdir -p cubic_project
cubic-cli -c cubic_project -s "$ISO_NAME"

# In chroot-Umgebung arbeiten
cd cubic_project/custom-disk/
cat > customize.sh << 'EOF'
#!/bin/bash
set -e

# Minimale Pakete behalten, unnötige entfernen
echo "Entferne unnötige Pakete..."
apt update
apt-get remove -y \
    ubuntu-desktop \
    libreoffice* \
    thunderbird* \
    firefox* \
    aisleriot \
    gnome-mahjongg \
    gnome-mines \
    gnome-sudoku \
    rhythmbox* \
    totem* \
    transmission* \
    cheese \
    gnome-todo \
    shotwell \
    simple-scan \
    remmina

# Nur absolut notwendige Netzwerk-Tools installieren
apt-get install -y \
    net-tools \
    iproute2 \
    iputils-ping \
    wget \
    network-manager \
    dialog \
    whiptail

# Autostart-Skript erstellen
mkdir -p /usr/local/bin
cat > /usr/local/bin/autoinstall.sh << 'INNEREOF'
#!/bin/bash

# Funktion für Sprachauswahl
select_language() {
    whiptail --title "Sprachauswahl" --menu "Wähle deine bevorzugte Sprache:" 15 60 2 \
    "de_DE.UTF-8" "Deutsch" \
    "en_US.UTF-8" "Englisch" 2>/tmp/language_choice
    
    LANG=$(cat /tmp/language_choice)
    if [ -z "$LANG" ]; then
        LANG="de_DE.UTF-8"  # Standard: Deutsch
    fi
    
    echo "LANG=$LANG" > /etc/default/locale
    echo "Sprache gesetzt auf: $LANG"
}

# Funktion für Tastaturlayout-Auswahl
select_keyboard() {
    whiptail --title "Tastaturlayout" --menu "Wähle dein Tastaturlayout:" 15 60 4 \
    "de" "Deutsch (Deutschland)" \
    "de_CH" "Deutsch (Schweiz)" \
    "de_AT" "Deutsch (Österreich)" \
    "us" "Englisch (US)" 2>/tmp/keyboard_choice
    
    KEYBOARD=$(cat /tmp/keyboard_choice)
    if [ -z "$KEYBOARD" ]; then
        KEYBOARD="de"  # Standard: Deutsch (Deutschland)
    fi
    
    localectl set-keymap $KEYBOARD
    echo "Tastaturlayout gesetzt auf: $KEYBOARD"
}

# Funktion für intelligente Netzwerkkonfiguration
setup_network() {
    # Netzwerkadapter identifizieren
    INTERFACES=$(ip -o link show | grep -v "lo" | awk -F': ' '{print $2}')
    
    # Versuche DHCP
    echo "Versuche DHCP-Konfiguration..."
    for IFACE in $INTERFACES; do
        echo "Konfiguriere $IFACE mit DHCP..."
        dhclient -v $IFACE
        
        # Prüfe, ob eine IP zugewiesen wurde
        if ip addr show $IFACE | grep -q "inet "; then
            echo "DHCP erfolgreich für $IFACE"
            
            # Prüfe Internetverbindung
            if ping -c 1 indianfire.ch >/dev/null 2>&1; then
                echo "Internetverbindung hergestellt!"
                return 0
            fi
        fi
    done
    
    echo "DHCP fehlgeschlagen. Versuche intelligente statische Konfiguration..."
    
    # Intelligenter Algorithmus für statische IP-Zuweisung
    for IFACE in $INTERFACES; do
        # Netzwerkklassen prüfen und versuchen
        for CLASS in "192.168.1" "192.168.0" "10.0.0" "172.16.0"; do
            for HOST in {2..20}; do
                IP="${CLASS}.${HOST}"
                GATEWAY="${CLASS}.1"
                
                echo "Versuche $IP auf $IFACE mit Gateway $GATEWAY..."
                ip addr flush dev $IFACE
                ip addr add ${IP}/24 dev $IFACE
                ip route add default via $GATEWAY dev $IFACE
                
                # Kurz warten und prüfen
                sleep 2
                if ping -c 1 indianfire.ch >/dev/null 2>&1; then
                    echo "Verbindung erfolgreich mit IP: $IP, Gateway: $GATEWAY"
                    return 0
                fi
            done
        done
    done
    
    # Manuelle Konfiguration als letzten Ausweg
    echo "Automatische Konfiguration fehlgeschlagen. Manuelle Eingabe erforderlich..."
    
    # Erstelle Liste der verfügbaren Interfaces für Whiptail
    IFACE_OPTIONS=""
    for IF in $INTERFACES; do
        IFACE_OPTIONS="$IFACE_OPTIONS $IF $IF"
    done
    
    # Interface-Auswahl
    whiptail --title "Netzwerkkonfiguration" --menu "Wähle ein Netzwerk-Interface:" 15 60 4 $IFACE_OPTIONS 2>/tmp/iface_choice
    SELECTED_IFACE=$(cat /tmp/iface_choice)
    
    # IP-Konfiguration
    IP=$(whiptail --title "IP-Adresse" --inputbox "Gib die IP-Adresse ein:" 10 60 "192.168.1.100" 3>&1 1>&2 2>&3)
    NETMASK=$(whiptail --title "Netzmaske" --inputbox "Gib die Netzmaske ein:" 10 60 "255.255.255.0" 3>&1 1>&2 2>&3)
    GATEWAY=$(whiptail --title "Gateway" --inputbox "Gib das Gateway ein:" 10 60 "192.168.1.1" 3>&1 1>&2 2>&3)
    DNS=$(whiptail --title "DNS-Server" --inputbox "Gib den DNS-Server ein:" 10 60 "8.8.8.8" 3>&1 1>&2 2>&3)
    
    # Konfiguration anwenden
    ip addr flush dev $SELECTED_IFACE
    ip addr add ${IP}/${NETMASK} dev $SELECTED_IFACE
    ip route add default via $GATEWAY dev $SELECTED_IFACE
    echo "nameserver $DNS" > /etc/resolv.conf
    
    echo "Manuelle Konfiguration angewendet."
    
    # Prüfe Verbindung
    if ping -c 1 indianfire.ch >/dev/null 2>&1; then
        echo "Internetverbindung hergestellt!"
        return 0
    else
        echo "Internetverbindung konnte nicht hergestellt werden."
        return 1
    fi
}

# Installationsskript herunterladen und ausführen
download_and_run_installer() {
    echo "Lade Installationsskript herunter..."
    mkdir -p /tmp/installer
    cd /tmp/installer
    
    if wget -q --show-progress "https://indianfire.ch/fde"; then
        echo "Installationsskript erfolgreich heruntergeladen."
        chmod +x fde
        echo "Starte Installationsskript..."
        ./fde
    else
        echo "Fehler beim Herunterladen des Installationsskripts."
        return 1
    fi
}

# Hauptfunktion
main() {
    clear
    echo "Willkommen zum automatischen Installationssystem"
    echo "------------------------------------------------"
    
    # Sprache und Tastatur konfigurieren
    select_language
    select_keyboard
    
    # Netzwerk einrichten
    setup_network
    
    # Installationsskript ausführen
    download_and_run_installer
    
    # Bildschirm für Benutzer-Feedback
    if [ $? -eq 0 ]; then
        whiptail --title "Installation abgeschlossen" --msgbox "Die Installation wurde erfolgreich abgeschlossen." 10 60
    else
        whiptail --title "Installationsfehler" --msgbox "Bei der Installation ist ein Fehler aufgetreten." 10 60
    fi
}

# Starte Hauptprogramm
main
INNEREOF

chmod +x /usr/local/bin/autoinstall.sh

# Systemd-Service für Autostart erstellen
cat > /etc/systemd/system/autoinstall.service << 'INNEREOF'
[Unit]
Description=Automatisches Installationsskript
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/autoinstall.sh
StandardInput=tty
StandardOutput=tty
StandardError=tty
TTYPath=/dev/tty1

[Install]
WantedBy=multi-user.target
INNEREOF

# Service aktivieren
systemctl enable autoinstall.service

# GRUB-Konfiguration für schnellen Start
sed -i 's/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' /etc/default/grub
update-grub

# System bereinigen
apt-get autoremove -y
apt-get clean

# Locale-Daten für Deutsch und Englisch generieren
locale-gen de_DE.UTF-8 de_CH.UTF-8 de_AT.UTF-8 en_US.UTF-8

echo "Anpassung abgeschlossen."
EOF

chmod +x customize.sh
cd ..
cubic-cli -a custom-disk/customize.sh

# ISO generieren
echo "Generiere angepasste ISO-Datei..."
cubic-cli -g "ubuntufde.iso"

echo "ISO-Erstellung abgeschlossen. Die Datei ubuntufde.iso befindet sich im Verzeichnis $WORK_DIR/cubic_project/"