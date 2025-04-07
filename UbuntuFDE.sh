#!/bin/bash
# Ubuntu Full Disk Encryption - Automatisches Installationsskript
# Dieses Skript automatisiert die Installation von Ubuntu mit vollständiger Festplattenverschlüsselung
# Version: ${SCRIPT_VERSION}
# Datum: $(date +%Y-%m-%d)
# Autor: Smali Tobules


###################
# Konfiguration   #
SCRIPT_VERSION="0.0.1"
DEFAULT_HOSTNAME="ubuntu-fde"
DEFAULT_USERNAME="user"
DEFAULT_ROOT_SIZE="20"
DEFAULT_DATA_SIZE="0"
DEFAULT_SSH_PORT="22"
CONFIG_FILE="ubuntu-fde.conf"
LOG_FILE="ubuntu-fde.log"
LUKS_BOOT_NAME="BOOT"
LUKS_ROOT_NAME="ROOT"
# Konfiguration   #
###################


###################
# DESIGN UND LOG  #
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logdatei einrichten im aktuellen Verzeichnis
LOG_FILE="$(pwd)/UbuntuFDE_$(date +%Y%m%d_%H%M%S).log"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

# Alle Ausgaben in die Logdatei umleiten und gleichzeitig im Terminal anzeigen
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Installation startet am $(date) ===" | tee -a "$LOG_FILE"
echo "=== Alle Ausgaben werden in $LOG_FILE protokolliert ===" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Hilfsfunktionen für Logging
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARNUNG]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[FEHLER]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

log_progress() {
    echo -e "${BLUE}[FORTSCHRITT]${NC} $1" | tee -a "$LOG_FILE"
}

# Fortschrittsbalken
show_progress() {
    local percent=$1
    local width=100
    local num_bars=$((percent * width / 100))
    local progress="["
    
    for ((i=0; i<num_bars; i++)); do
        progress+="█"
    done
    
    for ((i=num_bars; i<width; i++)); do
        progress+=" "
    done
    
    progress+="] ${percent}%"
    
    echo -ne "\r${BLUE}${progress}${NC}"
}
# DESIGN UND LOG  #
###################


# Bestätigung vom Benutzer einholen
confirm() {
    echo -e "${YELLOW}[WARNUNG]${NC} $1"
    read -p "Bist du sicher? (j/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Jj]$ ]]; then
        return 0  # Erfolg zurückgeben (true in Bash)
    else
        return 1  # Fehler zurückgeben (false in Bash)
    fi
}

# Wrapper-Funktion für Paketinstallationen
pkg_install() {
    if command -v nala &> /dev/null; then
        nala install -y "$@"
    else
        apt-get install -y "$@"
    fi
}

pkg_update() {
    if command -v nala &> /dev/null; then
        nala update
    else
        apt-get update
    fi
}

pkg_upgrade() {
    if command -v nala &> /dev/null; then
        nala upgrade -y
    else
        apt-get dist-upgrade -y
    fi
}

pkg_clean() {
    if command -v nala &> /dev/null; then
        nala clean
    else
        apt-get clean
    fi
}

pkg_autoremove() {
    if command -v nala &> /dev/null; then
        nala autoremove -y
    else
        apt-get autoremove -y
    fi
}

###################
#   Systemcheck   #
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "Dieses Skript muss als Root ausgeführt werden."
    fi
}

check_dependencies() {
    log_info "Prüfe Abhängigkeiten..."
    
    local deps=("sgdisk" "cryptsetup" "debootstrap" "lvm2" "curl" "wget" "nala")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_info "Aktualisiere Paketquellen..."
        pkg_update
        log_info "Installiere fehlende Abhängigkeiten: ${missing_deps[*]}..."
        pkg_install "${missing_deps[@]}"
    fi
}

check_system() {
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        log_info "Erkanntes System: $PRETTY_NAME"
    else
        log_warn "Konnte Betriebssystem nicht erkennen"
    fi
}
#   Systemcheck   #
###################


find_fastest_mirrors() {
    log_info "Suche nach schnellsten Paketquellen..."
    
    # Sicherstellen, dass nala installiert ist
    if ! command -v nala &> /dev/null; then
        log_warn "Nala nicht gefunden, überspringe Mirror-Optimierung."
        MIRRORS_OPTIMIZED="false"
        return
    fi
    
    # Ländererkennung basierend auf IP-Adresse
    log_info "Ermittle Land basierend auf IP-Adresse..."
    COUNTRY_CODE=$(curl -s https://ipapi.co/country_code)
    
    if [ -z "$COUNTRY_CODE" ]; then
        # Fallback wenn API nicht funktioniert
        log_warn "Ländererkennung fehlgeschlagen, versuche alternative API..."
        COUNTRY_CODE=$(curl -s https://ipinfo.io/country)
    fi
    
    if [ -z "$COUNTRY_CODE" ]; then
        # Letzter Fallback
        log_warn "Ländererkennung fehlgeschlagen, verwende 'all'."
        COUNTRY_CODE="all"
    else
        log_info "Erkanntes Land: $COUNTRY_CODE"
    fi
    
    # Führe nala fetch mit dem erkannten Land aus
    nala fetch --auto --fetches 3 --country "$COUNTRY_CODE"
    
    # Prüfe, ob die Optimierung erfolgreich war
    if [ -f /etc/apt/sources.list.d/nala-sources.list ]; then
        log_info "Mirror-Optimierung erfolgreich."
        MIRRORS_OPTIMIZED="true"
    else
        log_warn "Keine optimierten Mirrors gefunden."
        MIRRORS_OPTIMIZED="false"
    fi
    
    # Exportiere die Variablen
    export COUNTRY_CODE
    export MIRRORS_OPTIMIZED
}

copy_nala_config() {
    if [ "${MIRRORS_OPTIMIZED}" = "true" ] && [ -f /etc/apt/sources.list.d/nala-sources.list ]; then
        log_info "Kopiere optimierte nala-Konfiguration in die chroot-Umgebung..."
        mkdir -p /mnt/ubuntu/etc/apt/sources.list.d/
        cp /etc/apt/sources.list.d/nala-sources.list /mnt/ubuntu/etc/apt/sources.list.d/
        
        if [ -f /etc/nala/nala.list ]; then
            mkdir -p /mnt/ubuntu/etc/nala/
            cp /etc/nala/nala.list /mnt/ubuntu/etc/nala/
        fi
    fi
}

setup_ssh_access() {
    # Lösche bestehende .bash_profile
    rm -f /root/.bash_profile
    
    # Einfaches 6-stelliges Passwort
    SSH_PASSWORD=$(tr -dc '0-9' < /dev/urandom | head -c 6)
    
    # Root-Passwort setzen
    echo "root:${SSH_PASSWORD}" | chpasswd
    
    # SSH-Server einrichten
    pkg_install openssh-server
    
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
    systemctl restart ssh

    # Speichere bisherige Einstellungen für SSH-Start
    echo "INSTALL_MODE=2" > /tmp/install_config
    echo "SAVE_CONFIG=${SAVE_CONFIG}" >> /tmp/install_config
    echo "CONFIG_OPTION=${CONFIG_OPTION}" >> /tmp/install_config
    echo "SKIP_INITIAL_QUESTIONS=true" >> /tmp/install_config
    
    # Skript kopieren
    SCRIPT_PATH=$(readlink -f "$0")
    cp "$SCRIPT_PATH" /root/install_script.sh
    chmod +x /root/install_script.sh
    
    # SSH-Login mit automatischer Verbindung zur Installation
    cat > /root/.bash_profile <<EOF
if [ -n "\$SSH_CONNECTION" ]; then
    if [ -f "/root/install_script.sh" ]; then
        echo "Verbinde mit der Installation..."
        /root/install_script.sh ssh_connect
    else
        echo "FEHLER: Installationsskript nicht gefunden!"
        echo "Pfad: /root/install_script.sh"
        ls -la /root/
    fi
fi
EOF
    
    # SSH-Zugangsdaten anzeigen
    echo -e "\n${CYAN}===== SSH-ZUGANG AKTIV =====${NC}"
    echo -e "SSH-Server wurde aktiviert. Verbinde dich mit:"
    echo -e "${YELLOW}IP-Adressen:${NC}"
    ip -4 addr show scope global | grep inet | awk '{print "  " $2}' | cut -d/ -f1
    echo -e "${YELLOW}Benutzername:${NC} root"
    echo -e "${YELLOW}Passwort:${NC} ${SSH_PASSWORD}"
    echo -e "${CYAN}============================${NC}"
    echo
    
    # Marker für laufende Installation
    touch /tmp/installation_running
    
    # Blockiere die lokale Installation
    echo -e "\n${CYAN}Die Installation wird jetzt über SSH fortgesetzt.${NC}"
    echo -e "Dieser lokale Prozess wird blockiert, bis die Installation abgeschlossen ist."
    echo -e "(Drücke CTRL+C um abzubrechen)"
    echo
    
    # Erstelle einen einzigartigen Namen für unseren Semaphor
    SEM_NAME="/tmp/install_done_$(date +%s)"
    touch /tmp/sem_name
    echo "$SEM_NAME" > /tmp/sem_name
    
    # Warten bis die Installation beendet ist
    while true; do
        if [ -f "$SEM_NAME" ]; then
            echo "Installation abgeschlossen."
            rm -f "$SEM_NAME"
            break
        fi
        sleep 5
    done
    
    # Beenden nach Abschluss
    exit 0
}


# Netzwerk konfigurieren
#check_network_connectivity() {
#    log_info "Prüfe Netzwerkverbindung..."
#    
#    # Erst prüfen, ob wir bereits eine Verbindung haben
#    if ping -c 1 -W 2 archive.ubuntu.com &> /dev/null; then
#        log_info "Bestehende Netzwerkverbindung erkannt. Fahre fort..."
#        NETWORK_CONFIG="dhcp"  # Annahme: Wenn es funktioniert, ist es wahrscheinlich DHCP
#        return 0
#        
#        # Wenn Netplan-Konfiguration existiert, behalten
#        if [ -d /etc/netplan ] && [ "$(find /etc/netplan -name "*.yaml" | wc -l)" -gt 0 ]; then
#            log_info "Bestehende Netplan-Konfiguration gefunden, wird beibehalten."
#        fi
#    fi
#    
##    # Netplan-Konfigurationen entfernen, falls vorhanden
##    if [ -d /etc/netplan ]; then
##        log_info "Lösche bestehende Netplan-Konfigurationen..."
##        rm -f /etc/netplan/*.yaml
##    fi
#    
#    # Versuche DHCP
#    log_info "Versuche Netzwerkverbindung über DHCP herzustellen..."
#    if command -v dhclient &> /dev/null; then
#        dhclient -v || true
#    elif command -v dhcpclient &> /dev/null; then
#        dhcpclient -v || true
#    fi
#    
#    # Prüfe erneut nach Verbindung
#    if ping -c 1 -W 2 archive.ubuntu.com &> /dev/null; then
#        log_info "Netzwerkverbindung über DHCP hergestellt."
#        NETWORK_CONFIG="dhcp"
#        return 0
#    else
#        log_warn "Keine Netzwerkverbindung über DHCP gefunden."
#        
#         # Netzwerkoptionen anbieten
#         while true; do
#             echo -e "\n${CYAN}Netzwerkkonfiguration:${NC}"
#             echo "1) Erneut mit DHCP versuchen"
#             echo "2) Statische IP-Adresse konfigurieren"
#             echo "3) Ohne Netzwerk fortfahren (nicht empfohlen)"
#             read -p "Wähle eine Option [2]: " NETWORK_CHOICE
#             NETWORK_CHOICE=${NETWORK_CHOICE:-2}
#             
#             if [ "$NETWORK_CHOICE" = "1" ]; then
#                 log_info "Versuche DHCP erneut..."
#                 if command -v dhclient &> /dev/null; then
#                     dhclient -v || true
#                 elif command -v dhcpclient &> /dev/null; then
#                     dhcpclient -v || true
#                 fi
#                 
#                 if ping -c 1 -W 2 archive.ubuntu.com &> /dev/null; then
#                     log_info "Netzwerkverbindung OK."
#                     NETWORK_CONFIG="dhcp"
#                     return 0
#                 else
#                     log_warn "DHCP fehlgeschlagen."
#                     # Erneut zur Auswahl zurückkehren
#                 fi
#             elif [ "$NETWORK_CHOICE" = "2" ]; then
#                 if configure_static_ip; then
#                     return 0
#                 fi
#                 # Bei Fehlschlag zur Auswahl zurückkehren
#             else
#                 log_warn "Installation ohne Netzwerk wird fortgesetzt. Einige Funktionen werden nicht verfügbar sein."
#                 NETWORK_CONFIG="none"
#                 return 1
#             fi
#         done
#    fi
#}
#
#configure_static_ip() {
#    # Netzwerkinterface ermitteln
#    echo -e "\n${CYAN}Verfügbare Netzwerkinterfaces:${NC}"
#    ip -o link show | grep -v "lo" | awk -F': ' '{print $2}'
#    
#    read -p "Netzwerkinterface (z.B. eth0, enp0s3): " NET_INTERFACE
#    read -p "IP-Adresse (z.B. 192.168.1.100): " NET_IP
#    read -p "Netzmaske (z.B. 24 für /24): " NET_MASK
#    read -p "Gateway (z.B. 192.168.1.1): " NET_GATEWAY
#    read -p "DNS-Server (z.B. 8.8.8.8): " NET_DNS
#    
#    log_info "Konfiguriere statische IP-Adresse..."
#    ip addr add ${NET_IP}/${NET_MASK} dev ${NET_INTERFACE} || true
#    ip link set ${NET_INTERFACE} up || true
#    ip route add default via ${NET_GATEWAY} || true
#    echo "nameserver ${NET_DNS}" > /etc/resolv.conf
#    
#    if ping -c 1 -W 2 archive.ubuntu.com &> /dev/null; then
#        log_info "Netzwerkverbindung OK."
#        NETWORK_CONFIG="static"
#        STATIC_IP_CONFIG="interface=${NET_INTERFACE},address=${NET_IP}/${NET_MASK},gateway=${NET_GATEWAY},dns=${NET_DNS}"
#        return 0
#    else
#        log_warn "Netzwerkverbindung konnte nicht hergestellt werden. Überprüfe deine Einstellungen."
#        return 1
#    fi
#}


###################
#  Konfiguration  #
load_config() {
    local config_path=$1
    
    if [ -f "$config_path" ]; then
        log_info "Lade Konfiguration aus $config_path..."
        source "$config_path"
        return 0
    else
        return 1
    fi
}

save_config() {
    local config_path=$1
    
    log_info "Speichere Konfiguration in $config_path..."
    cat > "$config_path" << EOF
# UbuntuFDE Konfiguration
# Erstellt am $(date)
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
DEV="$DEV"
ROOT_SIZE="$ROOT_SIZE"
DATA_SIZE="$DATA_SIZE"
SWAP_SIZE="$SWAP_SIZE"
LUKS_PASSWORD="$LUKS_PASSWORD"
USER_PASSWORD="$USER_PASSWORD"
INSTALL_MODE="$INSTALL_MODE"
KERNEL_TYPE="$KERNEL_TYPE"
ENABLE_SECURE_BOOT="$ENABLE_SECURE_BOOT"
ADDITIONAL_PACKAGES="$ADDITIONAL_PACKAGES"
UBUNTU_CODENAME="$UBUNTU_CODENAME"
UPDATE_OPTION="$UPDATE_OPTION"
INSTALL_DESKTOP="$INSTALL_DESKTOP"
DESKTOP_ENV="$DESKTOP_ENV"
DESKTOP_SCOPE="$DESKTOP_SCOPE"
LOCALE="$LOCALE"
KEYBOARD_LAYOUT="$KEYBOARD_LAYOUT"
TIMEZONE="$TIMEZONE"
NETWORK_CONFIG="$NETWORK_CONFIG"
STATIC_IP_CONFIG="$STATIC_IP_CONFIG"
EOF
    chmod 600 "$config_path"
    log_info "Konfiguration gespeichert."
}

calculate_available_space() {
    local dev=$1
    local efi_size=256    # In Megabyte
    local boot_size=1024  # In Megabyte
    local grub_size=2     # In Megabyte
    local total_size_mb
    
    # Konvertiere Gesamtgröße in MB
    if [[ "$(lsblk -d -n -o SIZE "$dev" | tr -d ' ')" =~ ([0-9.]+)([GT]) ]]; then
        if [ "${BASH_REMATCH[2]}" = "T" ]; then
            total_size_mb=$(echo "${BASH_REMATCH[1]} * 1024 * 1024" | bc | cut -d. -f1)
        else  # G
            total_size_mb=$(echo "${BASH_REMATCH[1]} * 1024" | bc | cut -d. -f1)
        fi
    else
        # Fallback - nehme an, es ist in MB
        total_size_mb=$(lsblk -d -n -o SIZE "$dev" --bytes | awk '{print $1 / 1024 / 1024}' | cut -d. -f1)
    fi
    
    # Berechne verfügbaren Speicher (nach Abzug von EFI, boot, grub)
    local reserved_mb=$((efi_size + boot_size + grub_size))
    local available_mb=$((total_size_mb - reserved_mb))
    local available_gb=$((available_mb / 1024))
    
    echo "$available_gb"
}

gather_disk_input() {
    # Feststellungen verfügbarer Laufwerke
    available_devices=()
    echo -e "\n${CYAN}Verfügbare Laufwerke:${NC}"
    echo -e "${YELLOW}NR   GERÄT                GRÖSSE      MODELL${NC}"
    echo -e "-------------------------------------------------------"
    i=0
    while read device size model; do
        # Überspringe Überschriften oder leere Zeilen
        if [[ "$device" == "NAME" || -z "$device" ]]; then
            continue
        fi
        available_devices+=("$device")
        ((i++))
        printf "%-4s %-20s %-12s %s\n" "[$i]" "$device" "$size" "$model"
    done < <(lsblk -d -p -o NAME,SIZE,MODEL | grep -v loop)
    echo -e "-------------------------------------------------------"

    # Wenn keine Geräte gefunden wurden
    if [ ${#available_devices[@]} -eq 0 ]; then
        log_error "Keine Laufwerke gefunden!"
    fi

    # Standardwert ist das erste Gerät
    DEFAULT_DEV="1"
    DEFAULT_DEV_PATH="${available_devices[0]}"

    # Laufwerksauswahl
    read -p "Wähle ein Laufwerk (Nummer oder vollständiger Pfad) [1]: " DEVICE_CHOICE
    DEVICE_CHOICE=${DEVICE_CHOICE:-1}

    # Verarbeite die Auswahl
    if [[ "$DEVICE_CHOICE" =~ ^[0-9]+$ ]] && [ "$DEVICE_CHOICE" -ge 1 ] && [ "$DEVICE_CHOICE" -le "${#available_devices[@]}" ]; then
        # Nutzer hat Nummer ausgewählt
        DEV="${available_devices[$((DEVICE_CHOICE-1))]}"
    else
        # Nutzer hat möglicherweise einen Pfad eingegeben
        if [ -b "$DEVICE_CHOICE" ]; then
            DEV="$DEVICE_CHOICE"
        else
            # Ungültige Eingabe - verwende erstes Gerät als Fallback
            DEV="${available_devices[0]}"
            log_info "Ungültige Eingabe. Verwende Standardgerät: $DEV"
        fi
    fi

    # Berechne verfügbaren Speicherplatz
    AVAILABLE_GB=$(calculate_available_space "$DEV")

    # Zeige Gesamtspeicher und verfügbaren Speicher
    TOTAL_SIZE=$(lsblk -d -n -o SIZE "$DEV" | tr -d ' ')
    echo -e "\n${CYAN}Laufwerk: $DEV${NC}"
    echo -e "Gesamtspeicher: $TOTAL_SIZE"
    
    # Zeige Systempartitionen mit ihren Größen
    echo -e "\n${CYAN}Übersicht der Systempartitionen:${NC}"
    echo -e "${YELLOW}PARTITION    GRÖSSE    ZWECK${NC}"
    echo -e "-------------------------------------------------------------------------------"
    echo -e "EFI-SP       256 MB    EFI-System-Partition für den Bootloader"
    echo -e "GRUB         2 MB      GRUB Bios-Boot-Partition"
    echo -e "boot         1024 MB   Boot-Partition (enthält Kernel, initramfs)"
    echo -e "--------------------------------------------------------------------------------"
    echo -e "GESAMT       1282 MB   Reserviert für Systempartitionen"
    echo -e "\nVerfügbarer Speicher für LVM (nach Abzug der Systempartitionen): ${AVAILABLE_GB} GB"

    # LVM-Größenkonfiguration - erst Swap, dann Root, dann Data
    echo -e "\n${CYAN}LVM-Konfiguration:${NC}"

    # Swap-Konfiguration
    RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    RAM_MB=$((RAM_KB / 1024))
    RAM_GB=$((RAM_MB / 1024))
    DEFAULT_SWAP=$((RAM_GB * 2))
    
    read -p "Größe für swap-LV (GB) [$DEFAULT_SWAP]: " SWAP_SIZE
    SWAP_SIZE=${SWAP_SIZE:-$DEFAULT_SWAP}

    # Berechne verbleibenden Speicher nach Swap
    REMAINING_GB=$((AVAILABLE_GB - SWAP_SIZE))
    echo -e "Verbleibender Speicher: ${REMAINING_GB} GB"

    # Root-Konfiguration
    read -p "Größe für root-LV (GB) [$DEFAULT_ROOT_SIZE]: " ROOT_SIZE
    ROOT_SIZE=${ROOT_SIZE:-$DEFAULT_ROOT_SIZE}

    # Berechne verbleibenden Speicher nach Root
    REMAINING_GB=$((REMAINING_GB - ROOT_SIZE))
    echo -e "Verbleibender Speicher: ${REMAINING_GB} GB"

    # Data-Konfiguration
    echo -e "Größe für data-LV (GB) [Restlicher Speicher (${REMAINING_GB} GB)]: "
    read DATA_SIZE_INPUT

    if [ -z "$DATA_SIZE_INPUT" ] || [ "$DATA_SIZE_INPUT" = "0" ]; then
        DATA_SIZE="0"  # 0 bedeutet restlicher Platz
        echo -e "data-LV verwendet den restlichen Speicher: ${REMAINING_GB} GB"
    else
        DATA_SIZE=$DATA_SIZE_INPUT
        REMAINING_GB=$((REMAINING_GB - DATA_SIZE))
        echo -e "Verbleibender ungenutzter Speicher: ${REMAINING_GB} GB"
    fi
}

gather_user_input() {
    echo -e "${CYAN}===== INSTALLATIONSKONFIGURATION =====${NC}"
    
    # Wenn von SSH fortgesetzt, überspringe die ersten Fragen
    if [ "${SKIP_INITIAL_QUESTIONS}" = "true" ]; then
        log_info "Setze mit Desktop-Installation fort..."
    else
        # Frage nach Konfigurationsdatei oder Speicherung
        echo -e "\n${CYAN}Konfigurationsverwaltung:${NC}"
        echo "1) Neue Konfiguration erstellen"
        echo "2) Bestehende Konfigurationsdatei laden"
        read -p "Wähle eine Option [1]: " CONFIG_OPTION
        CONFIG_OPTION=${CONFIG_OPTION:-1}
        
        if [ "$CONFIG_OPTION" = "2" ]; then
            read -p "Pfad zur Konfigurationsdatei: " config_path
            if load_config "$config_path"; then
                log_info "Konfiguration erfolgreich geladen."
                
                # Frage, ob am Ende trotzdem gespeichert werden soll
                read -p "Möchtest du die Konfiguration nach möglichen Änderungen erneut speichern? (j/n) [j]: " -r
                SAVE_CONFIG=${REPLY:-j}
                
                # Wenn Remote-Installation in der Konfiguration ist, direkt SSH einrichten
                if [ "${INSTALL_MODE:-1}" = "2" ]; then
                    setup_ssh_access
                fi
                
                return
            else
                log_warn "Konfigurationsdatei nicht gefunden. Fahre mit manueller Konfiguration fort."
            fi
        fi
        
        # Frage, ob die Konfiguration gespeichert werden soll
        read -p "Möchtest du die Konfiguration für spätere Verwendung speichern? (j/n) [n]: " -r
        SAVE_CONFIG=${REPLY:-n}
        
        # Installationsmodus
        echo -e "\n${CYAN}Installationsmodus:${NC}"
        echo "1) Lokale Installation (Kein SSH-Zugriff verfügbar)"
        echo "2) Remote-Installation (SSH-Server wird eingerichtet)"
        read -p "Wähle den Installationsmodus [1]: " INSTALL_MODE_CHOICE
        INSTALL_MODE=${INSTALL_MODE_CHOICE:-1}
        
        # Wenn Remote-Installation gewählt wurde, direkt SSH einrichten
        if [ "$INSTALL_MODE" = "2" ]; then
            setup_ssh_access
        fi
    fi

    # Desktop-Installation
    echo -e "\n${CYAN}Desktop-Installation:${NC}"
    echo "1) Ja, Desktop-Umgebung installieren"
    echo "2) Nein, nur Server-Installation"
    read -p "Desktop installieren? [1]: " DESKTOP_CHOICE
    INSTALL_DESKTOP=$([[ ${DESKTOP_CHOICE:-1} == "1" ]] && echo "1" || echo "0")
    
    # Desktopumgebung auswählen wenn Desktop gewünscht
    if [ "$INSTALL_DESKTOP" = "1" ]; then
        echo -e "\n${CYAN}Desktop-Umgebung:${NC}"
        echo "1) GNOME (Standard Ubuntu Desktop)"
        echo "2) KDE Plasma (Umfangreicher Desktop, Ähnlich wie Windows)"
        echo "3) Xfce (Leichter Desktop, Optimal für ältere Systeme)"
        read -p "Wähle eine Desktop-Umgebung [1]: " DE_CHOICE
        DESKTOP_ENV=${DE_CHOICE:-1}
        
        echo -e "\n${CYAN}Umfang der Desktop-Installation:${NC}"
        echo "1) Minimal (nur Basisfunktionalität)"
        echo "2) Standard (empfohlen, alle wichtigen Anwendungen)"
        read -p "Wähle den Installationsumfang [1]: " DE_SCOPE
        DESKTOP_SCOPE=${DE_SCOPE:-1}
    fi
    
    # Systemparameter
    RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    RAM_MB=$((RAM_KB / 1024))
    RAM_GB=$((RAM_MB / 1024))
    DEFAULT_SWAP=$((RAM_GB * 2))

    # Benutzeroberflächen-Sprache
    echo -e "\n${CYAN}Sprache der Benutzeroberfläche:${NC}"
    echo "1) Deutsch"
    echo "2) English"
    echo "3) Français"
    echo "4) Italiano" 
    echo "5) Русский"
    echo "6) Español"
    echo "7) Andere/Other"
    read -p "Wähle die Sprache für die Benutzeroberfläche [1]: " UI_LANG_CHOICE

    case ${UI_LANG_CHOICE:-1} in
        1) UI_LANGUAGE="de_DE" ;;
        2) UI_LANGUAGE="en_US" ;;
        3) UI_LANGUAGE="fr_FR" ;;
        4) UI_LANGUAGE="it_IT" ;;
        5) UI_LANGUAGE="ru_RU" ;;
        6) UI_LANGUAGE="es_ES" ;;
        7) read -p "Gib den Sprachcode ein (z.B. nl_NL): " UI_LANGUAGE ;;
        *) UI_LANGUAGE="de_DE" ;;
    esac
    
    # Zeitzone
    echo -e "\n${CYAN}Zeitzone:${NC}"
    echo "1) Europe/Berlin"
    echo "2) Europe/Moscow"
    echo "3) America/New_York"
    echo "4) America/Los_Angeles"
    echo "5) Asia/Tokyo"
    echo "6) Australia/Sydney"
    echo "7) Africa/Johannesburg"
    echo "8) Benutzerdefiniert"
    read -p "Wähle eine Zeitzone [1]: " TIMEZONE_CHOICE

    case ${TIMEZONE_CHOICE:-1} in
        1) TIMEZONE="Europe/Berlin" ;;
        2) TIMEZONE="Europe/Moscow" ;;
        3) TIMEZONE="America/New_York" ;;
        4) TIMEZONE="America/Los_Angeles" ;;
        5) TIMEZONE="Asia/Tokyo" ;;
        6) TIMEZONE="Australia/Sydney" ;;
        7) TIMEZONE="Africa/Johannesburg" ;;
        8) read -p "Gib deine Zeitzone ein (z.B. Asia/Singapore): " TIMEZONE ;;
        *) TIMEZONE="Europe/Berlin" ;;
    esac

    # Sprache und Tastatur
    echo -e "\n${CYAN}Sprache und Tastatur:${NC}"
    echo "1) Deutsch (Deutschland) - de_DE.UTF-8"
    echo "2) Deutsch (Schweiz) - de_CH.UTF-8"
    echo "3) Englisch (USA) - en_US.UTF-8"
    echo "4) Französisch - fr_FR.UTF-8"
    echo "5) Italienisch - it_IT.UTF-8"
    echo "6) Benutzerdefiniert"
    read -p "Wähle eine Option [1]: " LOCALE_CHOICE

    case ${LOCALE_CHOICE:-1} in
        1) LOCALE="de_DE.UTF-8"; KEYBOARD_LAYOUT="de" ;;
        2) LOCALE="de_CH.UTF-8"; KEYBOARD_LAYOUT="ch" ;;
        3) LOCALE="en_US.UTF-8"; KEYBOARD_LAYOUT="us" ;;
        4) LOCALE="fr_FR.UTF-8"; KEYBOARD_LAYOUT="fr" ;;
        5) LOCALE="it_IT.UTF-8"; KEYBOARD_LAYOUT="it" ;;
        6) 
            read -p "Gib deine Locale ein (z.B. es_ES.UTF-8): " LOCALE
            read -p "Gib dein Tastaturlayout ein (z.B. es): " KEYBOARD_LAYOUT
            ;;
        *) LOCALE="de_DE.UTF-8"; KEYBOARD_LAYOUT="de" ;;
    esac
    
    # Hostname und Benutzername
    echo -e "\n${CYAN}Systemkonfiguration:${NC}"
    read -p "Hostname [$DEFAULT_HOSTNAME]: " HOSTNAME
    HOSTNAME=${HOSTNAME:-$DEFAULT_HOSTNAME}

    read -p "Benutzername [$DEFAULT_USERNAME]: " USERNAME
    USERNAME=${USERNAME:-$DEFAULT_USERNAME}

    # Benutzerpasswort mit Validierung
    while true; do
        read -s -p "Benutzerpasswort: " USER_PASSWORD
        echo
        
        # Prüfe ob Passwort leer ist
        if [ -z "$USER_PASSWORD" ]; then
            echo -e "${YELLOW}[WARNUNG]${NC} Das Passwort darf nicht leer sein. Bitte erneut versuchen."
            continue
        fi
        
        read -s -p "Benutzerpasswort (Bestätigung): " USER_PASSWORD_CONFIRM
        echo
        
        # Prüfe ob Passwörter übereinstimmen
        if [ "$USER_PASSWORD" != "$USER_PASSWORD_CONFIRM" ]; then
            echo -e "${YELLOW}[WARNUNG]${NC} Passwörter stimmen nicht überein. Bitte erneut versuchen."
            continue
        fi
        
        break
    done

    # LUKS-Passwort mit Validierung
    while true; do
        read -s -p "LUKS-Verschlüsselungs-Passwort: " LUKS_PASSWORD
        echo
        
        # Prüfe ob Passwort leer ist
        if [ -z "$LUKS_PASSWORD" ]; then
            echo -e "${YELLOW}[WARNUNG]${NC} Das LUKS-Passwort darf nicht leer sein. Bitte erneut versuchen."
            continue
        fi
        
        read -s -p "LUKS-Verschlüsselungs-Passwort (Bestätigung): " LUKS_PASSWORD_CONFIRM
        echo
        
        # Prüfe ob Passwörter übereinstimmen
        if [ "$LUKS_PASSWORD" != "$LUKS_PASSWORD_CONFIRM" ]; then
            echo -e "${YELLOW}[WARNUNG]${NC} LUKS-Passwörter stimmen nicht überein. Bitte erneut versuchen."
            continue
        fi
        
        break
    done
    
    # Kernel-Auswahl
    echo -e "\n${CYAN}Kernel-Auswahl:${NC}"
    echo "1) Standard-Kernel (Ubuntu Stock)"
    echo "2) Liquorix-Kernel (Optimiert für Desktop-Nutzung / Nicht kompatibel mit VM's)"
    echo "3) Low-Latency-Kernel (Optimiert für Echtzeitanwendungen)"
    read -p "Wähle den Kernel-Typ [1]: " KERNEL_CHOICE
    case ${KERNEL_CHOICE:-1} in
        1) KERNEL_TYPE="standard" ;;
        2) KERNEL_TYPE="liquorix" ;;
        3) KERNEL_TYPE="lowlatency" ;;
        *) KERNEL_TYPE="standard" ;;
    esac
    
    # Secure Boot
    echo -e "\n${CYAN}Secure Boot:${NC}"
    read -p "Secure Boot aktivieren? (j/n) [n]: " -r
    ENABLE_SECURE_BOOT=${REPLY:-n}
    
    # Installationsoptionen für Ubuntu
    echo -e "\n${CYAN}Ubuntu-Installation:${NC}"
    echo "1) Standard-Installation (neueste stabile Version)"
    echo "2) Spezifische Ubuntu-Version installieren"
    echo "3) Netzwerkinstallation (minimal)"
    read -p "Wähle eine Option [1]: " UBUNTU_INSTALL_OPTION
    UBUNTU_INSTALL_OPTION=${UBUNTU_INSTALL_OPTION:-1}
    
    # Ubuntu-Version ermitteln
    if [ "$UBUNTU_INSTALL_OPTION" = "1" ]; then
        # Automatisch neueste Version ermitteln
        UBUNTU_VERSION=$(curl -s https://changelogs.ubuntu.com/meta-release | grep "^Dist: " | tail -1 | cut -d' ' -f2)
        UBUNTU_CODENAME=$(curl -s https://changelogs.ubuntu.com/meta-release | grep "^Codename: " | tail -1 | cut -d' ' -f2)
        
        # Falls automatische Erkennung fehlschlägt
        if [ -z "$UBUNTU_VERSION" ]; then
            UBUNTU_CODENAME="oracular"  # Ubuntu 24.10 (Oracular Oriole)
        fi
    elif [ "$UBUNTU_INSTALL_OPTION" = "2" ]; then
        echo -e "\nVerfügbare Ubuntu-Versionen:"
        echo "1) 24.10 (Oracular Oriole) - aktuell"
        echo "2) 24.04 LTS (Noble Numbat) - langzeitunterstützt"
        echo "3) 23.10 (Mantic Minotaur)"
        echo "4) 22.04 LTS (Jammy Jellyfish) - langzeitunterstützt"
        read -p "Wähle eine Version [1]: " UBUNTU_VERSION_OPTION
        
        case ${UBUNTU_VERSION_OPTION:-1} in
            1) UBUNTU_CODENAME="oracular" ;;
            2) UBUNTU_CODENAME="noble" ;;
            3) UBUNTU_CODENAME="mantic" ;;
            4) UBUNTU_CODENAME="jammy" ;;
            *) UBUNTU_CODENAME="oracular" ;;
        esac
    else
        # Minimale Installation
        UBUNTU_CODENAME="oracular"
    fi
    
    # Aktualisierungseinstellungen
    echo -e "\n${CYAN}Aktualisierungseinstellungen:${NC}"
    echo "1) Alle Updates automatisch installieren"
    echo "2) Nur Sicherheitsupdates automatisch installieren"
    echo "3) Keine automatischen Updates"
    read -p "Wähle eine Option [1]: " UPDATE_OPTION
    UPDATE_OPTION=${UPDATE_OPTION:-1}
    
    # Zusätzliche Pakete
    echo -e "\n${CYAN}Zusätzliche Pakete:${NC}"
    read -p "Möchtest du zusätzliche Pakete installieren? (j/n) [n]: " -r
    if [[ ${REPLY:-n} =~ ^[Jj]$ ]]; then
        read -p "Gib zusätzliche Pakete an (durch Leerzeichen getrennt): " ADDITIONAL_PACKAGES
    fi
}
#  Konfiguration  #
###################


###################
# Partitionierung #
prepare_disk() {
    log_progress "Beginne mit der Partitionierung..."
    show_progress 10

    # Bestätigung nur einholen, wenn sie nicht bereits erfolgt ist
    if [ "${DISK_CONFIRMED:-false}" != "true" ]; then
        if ! confirm "ALLE DATEN AUF $DEV WERDEN GELÖSCHT!"; then
            log_warn "Partitionierung abgebrochen. Beginne erneut mit der Auswahl der Festplatte..."
            unset DEV SWAP_SIZE ROOT_SIZE DATA_SIZE
            gather_disk_input
            prepare_disk
            return
        fi
    else
        log_info "Festplattenauswahl bestätigt, führe Partitionierung durch..."
    fi 
    
    # Grundlegende Variablen einrichten
    DM="${DEV##*/}"
    if [[ "$DEV" =~ "nvme" ]]; then
        DEVP="${DEV}p"
        DM="${DM}p"
    else
        DEVP="${DEV}"
    fi
    
    # Export für spätere Verwendung
    export DEV DEVP DM
    
    # Partitionierung
    log_info "Partitioniere $DEV..."
    sgdisk --zap-all "$DEV"
    sgdisk --new=1:0:+1024M "$DEV"   # boot 
    sgdisk --new=2:0:+2M "$DEV"      # GRUB
    sgdisk --new=3:0:+256M "$DEV"    # EFI-SP
    sgdisk --new=5:0:0 "$DEV"        # rootfs
    sgdisk --typecode=1:8301 --typecode=2:ef02 --typecode=3:ef00 --typecode=5:8301 "$DEV"
    sgdisk --change-name=1:/boot --change-name=2:GRUB --change-name=3:EFI-SP --change-name=5:rootfs "$DEV"
    sgdisk --hybrid 1:2:3 "$DEV"
    sgdisk --print "$DEV"
    
    log_info "Partitionierung abgeschlossen"
    show_progress 20
}

setup_encryption() {
    log_progress "Richte Verschlüsselung ein..."
    
    log_info "Erstelle LUKS-Verschlüsselung für Boot-Partition..."
    # LUKS1 für /boot mit dem eingegebenen Passwort
    echo -n "$LUKS_PASSWORD" | cryptsetup luksFormat --type=luks1 --batch-mode "${DEVP}1" -
    
    log_info "Erstelle LUKS-Verschlüsselung für Root-Partition..."
    # LUKS2 für das Root-System
    echo -n "$LUKS_PASSWORD" | cryptsetup luksFormat --batch-mode "${DEVP}5" -
    
    # Öffne die verschlüsselten Geräte
    log_info "Öffne die verschlüsselten Partitionen..."
    echo -n "$LUKS_PASSWORD" | cryptsetup open "${DEVP}1" "${LUKS_BOOT_NAME}" -
    echo -n "$LUKS_PASSWORD" | cryptsetup open "${DEVP}5" "${LUKS_ROOT_NAME}" -
    
    # Dateisysteme erstellen
    log_info "Formatiere Dateisysteme..."
    mkfs.ext4 -L boot /dev/mapper/${LUKS_BOOT_NAME}
    mkfs.vfat -F 16 -n EFI-SP "${DEVP}3"
    
    show_progress 30
}

setup_lvm() {
    log_progress "Richte LVM ein..."
    
    log_info "Erstelle LVM-Struktur..."
    export VGNAME="vg"
    
    pvcreate /dev/mapper/${LUKS_ROOT_NAME}
    vgcreate "${VGNAME}" /dev/mapper/${LUKS_ROOT_NAME}
    
    # Erstelle LVs mit den angegebenen Größen
    lvcreate -L ${SWAP_SIZE}G -n swap "${VGNAME}"  # "swap" statt "swap_1"
    lvcreate -L ${ROOT_SIZE}G -n root "${VGNAME}"
    
    # Wenn DATA_SIZE 0 ist, verwende den restlichen Platz
    if [ "$DATA_SIZE" = "0" ]; then
        lvcreate -l 100%FREE -n data "${VGNAME}"
    else
        lvcreate -L ${DATA_SIZE}G -n data "${VGNAME}"
    fi
    
    log_info "Formatiere LVM-Volumes..."
    mkfs.ext4 -L root /dev/mapper/${VGNAME}-root
    mkfs.ext4 -L data /dev/mapper/${VGNAME}-data
    mkswap -L swap /dev/mapper/${VGNAME}-swap
    
    show_progress 40
}
# Partitionierung #
###################


###################
#   Basissystem   #
mount_filesystems() {
    log_progress "Hänge Dateisysteme ein..."
    
    # Einhängepunkte erstellen
    mkdir -p /mnt/ubuntu
    mount /dev/mapper/${VGNAME}-root /mnt/ubuntu
    mkdir -p /mnt/ubuntu/boot
    mount /dev/mapper/${LUKS_BOOT_NAME} /mnt/ubuntu/boot
    mkdir -p /mnt/ubuntu/boot/efi
    mount ${DEVP}3 /mnt/ubuntu/boot/efi
    mkdir -p /mnt/ubuntu/media/data
    mount /dev/mapper/${VGNAME}-data /mnt/ubuntu/media/data
    # Temporärer Einhängepunkt für Entwicklungsumgebung
    mkdir -p /media/data
    mount /dev/sdb1 /media/data
    
    show_progress 45
}

install_base_system() {
    log_progress "Installiere Basissystem..."

    # GPG-Schlüssel für lokalen Mirror importieren
    log_info "Importiere GPG-Schlüssel für lokalen Mirror..."
    mkdir -p /mnt/ubuntu/etc/apt/trusted.gpg.d/
    curl -fsSL http://192.168.56.120/repo-key.gpg | gpg --dearmor -o /mnt/ubuntu/etc/apt/trusted.gpg.d/local-mirror.gpg
    
    # Zu inkludierende Pakete definieren
    INCLUDED_PACKAGES=(
        curl gnupg ca-certificates sudo locales cryptsetup lvm2 nano wget
        apt-transport-https console-setup bash-completion systemd-resolved
        initramfs-tools cryptsetup-initramfs grub-efi-amd64 grub-efi-amd64-signed
        efibootmgr nala openssh-server smbclient cifs-utils util-linux net-tools
        ufw network-manager btop
    )

    # Optional auszuschließende Pakete definieren
    EXCLUDED_PACKAGES=(
        snapd cloud-init ubuntu-docs*
    )

    # Pakete zu kommagetrennter Liste zusammenfügen
    INCLUDED_PACKAGELIST=$(IFS=,; echo "${INCLUDED_PACKAGES[*]}")

    # Auszuschließende Pakete zu kommagetrennter Liste zusammenfügen
    EXCLUDED_PACKAGELIST=$(IFS=,; echo "${EXCLUDED_PACKAGES[*]}")

    log_info "Installiere das Ubuntu Basissystem..."

    # Installation mit debootstrap durchführen
    if [ "$UBUNTU_INSTALL_OPTION" = "3" ]; then
        debootstrap \
            --include="$INCLUDED_PACKAGELIST" \
            --exclude="$EXCLUDED_PACKAGELIST" \
            --variant=minbase \
            --components=main,restricted,universe,multiverse \
            --arch=amd64 \
            oracular \
            /mnt/ubuntu \
            http://192.168.56.120/ubuntu
    else
        debootstrap \
            --include="$INCLUDED_PACKAGELIST" \
            --exclude="$EXCLUDED_PACKAGELIST" \
            --components=main,restricted,universe,multiverse \
            --arch=amd64 \
            oracular \
            /mnt/ubuntu \
            http://192.168.56.120/ubuntu
    fi
    
    if [ $? -ne 0 ]; then
        log_error "debootstrap fehlgeschlagen für Ubuntu. Installation wird abgebrochen."
    fi
    
    log_info "Basissystem erfolgreich installiert."
    
    # Basisverzeichnisse für chroot
    for dir in /dev /dev/pts /proc /sys /run; do
        mkdir -p "/mnt/ubuntu$dir"
        mount -B $dir /mnt/ubuntu$dir
    done
    
    show_progress 55
}

download_thorium() {
    if [ "$INSTALL_DESKTOP" = "1" ]; then
        log_info "Downloade Thorium Browser für chroot-Installation..."
        
        # CPU-Erweiterungen prüfen
        if grep -q " avx2 " /proc/cpuinfo; then
            CPU_EXT="AVX2"
        elif grep -q " avx " /proc/cpuinfo; then
            CPU_EXT="AVX"
        elif grep -q " sse4_1 " /proc/cpuinfo; then
            CPU_EXT="SSE4"
        else
            CPU_EXT="SSE3"
        fi
        log_info "CPU-Erweiterung erkannt: ${CPU_EXT}"
        
        # Thorium-Version und direkter Download
        THORIUM_VERSION="130.0.6723.174"
        THORIUM_URL="https://github.com/Alex313031/thorium/releases/download/M${THORIUM_VERSION}/thorium-browser_${THORIUM_VERSION}_${CPU_EXT}.deb"
        log_info "Download-URL: ${THORIUM_URL}"
        
        # Download direkt ins chroot-Verzeichnis
        if wget -q --show-progress --progress=bar:force:noscroll --tries=3 --timeout=10 -O /mnt/ubuntu/tmp/thorium.deb "${THORIUM_URL}"; then
            log_info "Download erfolgreich - Thorium wird später in chroot installiert"
            chmod 644 /mnt/ubuntu/tmp/thorium.deb
        else
            log_error "Download fehlgeschlagen!"
        fi
    fi
}

prepare_chroot() {
    log_progress "Bereite chroot-Umgebung vor..."
    
# Aktuelle UUIDs für die Konfigurationsdateien ermitteln
LUKS_BOOT_UUID=$(blkid -s UUID -o value ${DEVP}1)
LUKS_ROOT_UUID=$(blkid -s UUID -o value ${DEVP}5)
EFI_UUID=$(blkid -s UUID -o value ${DEVP}3)

# Erst LUKS-Container öffnen
echo -n "$LUKS_PASSWORD" | cryptsetup open "${DEVP}1" LUKS_BOOT -
echo -n "$LUKS_PASSWORD" | cryptsetup open "${DEVP}5" "${DM}5_crypt" -

# Dann die UUIDs der entschlüsselten Geräte ermitteln
BOOT_UUID=$(blkid -s UUID -o value /dev/mapper/${LUKS_BOOT_NAME})
ROOT_UUID=$(blkid -s UUID -o value /dev/mapper/${VGNAME}-root)
DATA_UUID=$(blkid -s UUID -o value /dev/mapper/${VGNAME}-data)
SWAP_UUID=$(blkid -s UUID -o value /dev/mapper/${VGNAME}-swap)

# fstab mit den RICHTIGEN UUIDs erstellen
cat > /mnt/ubuntu/etc/fstab <<EOF
# /etc/fstab
# <file system>                           <mount point>   <type>   <options>       <dump>  <pass>
# Root-Partition
UUID=${ROOT_UUID} /               ext4    defaults        0       1

# Boot-Partition
UUID=${BOOT_UUID} /boot           ext4    defaults        0       2

# EFI-Partition
UUID=${EFI_UUID}                            /boot/efi        vfat    umask=0077      0       1

# Daten-Partition
UUID=${DATA_UUID} /media/data     ext4    defaults        0       2

# Swap-Partition
UUID=${SWAP_UUID} none            swap    sw              0       0
EOF
#   Basissystem   #
###################


# System-Setup in chroot
log_progress "Konfiguriere System in chroot-Umgebung..."
cat > /mnt/ubuntu/setup.sh <<MAINEOF
#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

# SSH-Server deaktivieren
systemctl disable ssh

# Firewall einrichten
ufw default deny incoming
ufw default allow outgoing
ufw enable

# Zeitzone setzen
if [ -n "${TIMEZONE}" ]; then
    ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
else
    ln -sf /usr/share/zoneinfo/Europe/Zurich /etc/localtime
fi

# Wrapper-Funktionen für Paketoperationen
pkg_install() {
    if command -v nala &> /dev/null; then
        nala install -y "\$@"
    else
        apt-get install -y "\$@"
    fi
}

pkg_update() {
    if command -v nala &> /dev/null; then
        nala update
    else
        apt-get update
    fi
}

pkg_upgrade() {
    if command -v nala &> /dev/null; then
        nala upgrade -y
    else
        apt-get dist-upgrade -y
    fi
}

pkg_clean() {
    if command -v nala &> /dev/null; then
        nala clean
    else
        apt-get clean
    fi
}

pkg_autoremove() {
    if command -v nala &> /dev/null; then
        nala autoremove -y
    else
        apt-get autoremove -y
    fi
}

# Nala-Mirror-Optimierung für das finale System
if command -v nala &> /dev/null; then
    echo "Konfiguriere nala im neuen System..."
    
    # Falls wir bereits optimierte Mirrors haben, nutze diese
    if [ -f /etc/apt/sources.list.d/nala-sources.list ]; then
        echo "Übernehme optimierte Mirror-Konfiguration, überspringe erneute Suche..."
    else
        # Ermittle Land basierend auf IP-Adresse
        echo "Keine optimierte Mirror-Konfiguration gefunden, starte Suche..."
        COUNTRY_CODE=\$(curl -s https://ipapi.co/country_code)
        
        if [ -z "\$COUNTRY_CODE" ]; then
            # Fallback
            COUNTRY_CODE=\$(curl -s https://ipinfo.io/country)
        fi
        
        if [ -z "\$COUNTRY_CODE" ]; then
            # Letzter Fallback
            COUNTRY_CODE="${COUNTRY_CODE:-all}"
        else
            echo "Erkanntes Land: \$COUNTRY_CODE"
        fi
        
        echo "Suche nach schnellsten Mirrors für das neue System..."
        nala fetch --auto --fetches 3 --country "\$COUNTRY_CODE"
    fi
fi

# GPG-Schlüssel für lokales Repository importieren
if [ ! -f "/etc/apt/trusted.gpg.d/local-mirror.gpg" ]; then
    curl -fsSL http://192.168.56.120/repo-key.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/local-mirror.gpg
fi

# Paketquellen und Repositories einrichten

    mkdir -p /etc/apt/keyrings

    # Ubuntu Paketquellen
    cat > /etc/apt/sources.list <<-SOURCES
#deb http://192.168.56.120/ubuntu/ oracular main restricted universe multiverse
#deb http://192.168.56.120/ubuntu/ oracular-updates main restricted universe multiverse
#deb http://192.168.56.120/ubuntu/ oracular-security main restricted universe multiverse
#deb http://192.168.56.120/ubuntu/ oracular-backports main restricted universe multiverse

deb https://archive.ubuntu.com/ubuntu/ oracular main restricted universe multiverse
deb https://archive.ubuntu.com/ubuntu/ oracular-updates main restricted  universe multiverse
deb https://archive.ubuntu.com/ubuntu/ oracular-security main restricted universe multiverse
deb https://archive.ubuntu.com/ubuntu/ oracular-backports main restricted universe multiverse
SOURCES

    # Liquorix-Kernel Repository
    if [ "${KERNEL_TYPE}" = "liquorix" ]; then
        echo "Füge Liquorix-Kernel-Repository hinzu..."
        echo "deb http://liquorix.net/debian stable main" > /etc/apt/sources.list.d/liquorix.list
        curl -s 'https://liquorix.net/linux-liquorix-keyring.gpg' | gpg --dearmor -o /etc/apt/keyrings/liquorix-keyring.gpg
        echo "deb [signed-by=/etc/apt/keyrings/liquorix-keyring.gpg] https://liquorix.net/debian stable main" | tee /etc/apt/sources.list.d/liquorix.list
    fi

    ## Mozilla Team GPG-Schlüssel importieren
    #curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x0ab215679c571d1c8325275b9bdb3d89ce49ec21" | gpg --dearmor -o /etc/apt/keyrings/mozillateam-ubuntu-ppa.gpg

    ## Mozilla Team Repository einrichten
    #echo "deb [signed-by=/etc/apt/keyrings/mozillateam-ubuntu-ppa.gpg] http://ppa.launchpadcontent.net/mozillateam/ppa/ubuntu ${UBUNTU_CODENAME} main" | tee /etc/apt/sources.list.d/mozillateam-ubuntu-ppa.list

    ## Paket-Präferenzen für Mozilla Programme setzen
    #cat > /etc/apt/preferences.d/mozillateam <<EOF
#Package: firefox*
#Pin: release o=LP-PPA-mozillateam
#Pin-Priority: 1001

#Package: firefox*
#Pin: release o=Ubuntu
#Pin-Priority: -1

#Package: thunderbird*
#Pin: release o=LP-PPA-mozillateam
#Pin-Priority: 1001

#Package: thunderbird*
#Pin: release o=Ubuntu
#Pin-Priority: -1
#EOF


    # Hier Platz für zukünftige Paketquellen
    # BEISPIEL: Multimedia-Codecs
    # if [ "${INSTALL_MULTIMEDIA}" = "1" ]; then
    #     echo "Füge Multimedia-Repository hinzu..."
    #     echo "deb http://example.org/multimedia stable main" > /etc/apt/sources.list.d/multimedia.list
    # fi



# Automatische Updates konfigurieren
cat > /etc/apt/apt.conf.d/20auto-upgrades <<AUTOUPDATE
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "${UPDATE_OPTION}";
AUTOUPDATE

## Systemaktualisierung durchführen
echo "Aktualisiere Paketquellen und System..."
pkg_update
pkg_upgrade

# Notwendige Pakete installieren 
echo "Installiere Basis-Pakete..."
KERNEL_PACKAGES=""
if [ "${KERNEL_TYPE}" = "standard" ]; then
    KERNEL_PACKAGES="linux-image-generic linux-headers-generic"
elif [ "${KERNEL_TYPE}" = "lowlatency" ]; then
    KERNEL_PACKAGES="linux-image-lowlatency linux-headers-lowlatency"
elif [ "${KERNEL_TYPE}" = "liquorix" ]; then
    KERNEL_PACKAGES="linux-image-liquorix-amd64 linux-headers-liquorix-amd64"    
fi

# Grundlegende Programme und Kernel installieren
pkg_install --no-install-recommends \
    \${KERNEL_PACKAGES} \
    shim-signed \
    zram-tools \
    coreutils \
    timeshift \
    bleachbit \
    stacer \
    fastfetch \
    gparted \
    vlc \
    deluge \
    ufw \
    jq


# Thorium Browser installieren
if [ "${INSTALL_DESKTOP}" = "1" ] && [ -f /tmp/thorium.deb ]; then
    echo "Thorium-Browser-Paket gefunden, installiere..."
    
    # Installation ohne Download oder CPU-Erkennung
    if dpkg -i /tmp/thorium.deb || pkg_install -f; then
        echo "Thorium wurde erfolgreich installiert."
    else
        echo "Thorium-Installation fehlgeschlagen, fahre mit restlicher Installation fort."
    fi
    
    # Aufräumen
    rm -f /tmp/thorium.deb
fi

# Spracheinstellungen
locale-gen ${LOCALE} en_US.UTF-8
update-locale LANG=${LOCALE} LC_CTYPE=${LOCALE}

# Tastaturlayout
if [ -n "${KEYBOARD_LAYOUT}" ]; then
    echo "Setting keyboard layout to ${KEYBOARD_LAYOUT}"
    cat > /etc/default/keyboard <<KEYBOARD
XKBMODEL="pc105"
XKBLAYOUT="${KEYBOARD_LAYOUT}"
XKBVARIANT=""
XKBOPTIONS=""
KEYBOARD
    setupcon
fi

# Hostname setzen
echo "${HOSTNAME}" > /etc/hostname
echo "127.0.1.1 ${HOSTNAME}" >> /etc/hosts

# Netzwerk konfigurieren (systemd-networkd)
mkdir -p /etc/systemd/network

if [ "${NETWORK_CONFIG}" = "static" ]; then
    # Statische IP-Konfiguration anwenden
    echo "Konfiguriere statische IP-Adresse für systemd-networkd..."
    
    # STATIC_IP_CONFIG parsen (Format: interface=eth0,address=192.168.1.100/24,gateway=192.168.1.1,dns=8.8.8.8)
    NET_INTERFACE=\$(echo "${STATIC_IP_CONFIG}" | sed -n 's/.*interface=\([^,]*\).*/\1/p')
    NET_IP=\$(echo "${STATIC_IP_CONFIG}" | sed -n 's/.*address=\([^,]*\).*/\1/p')
    NET_GATEWAY=\$(echo "${STATIC_IP_CONFIG}" | sed -n 's/.*gateway=\([^,]*\).*/\1/p')
    NET_DNS=\$(echo "${STATIC_IP_CONFIG}" | sed -n 's/.*dns=\([^,]*\).*/\1/p')
    
    # Statisches Netzwerk konfigurieren
    cat > /etc/systemd/network/99-static.network <<EON
[Match]
Name=\${NET_INTERFACE}

[Network]
Address=\${NET_IP}
Gateway=\${NET_GATEWAY}
DNS=\${NET_DNS}
EON
else
    # DHCP-Konfiguration
    cat > /etc/systemd/network/99-dhcp.network <<EON
[Match]
Name=en*

[Network]
DHCP=yes
EON
fi

systemctl enable systemd-networkd
systemctl enable systemd-resolved


##################
#   CRYPTSETUP   #
# Schlüsseldatei und Konfigurations-hook einrichten
mkdir -p /etc/luks
dd if=/dev/urandom of=/etc/luks/boot_os.keyfile bs=4096 count=1
chmod -R u=rx,go-rwx /etc/luks
chmod u=r,go-rwx /etc/luks/boot_os.keyfile

# Schlüsseldatei zu LUKS-Volumes hinzufügen
echo -n "${LUKS_PASSWORD}" | cryptsetup luksAddKey ${DEVP}1 /etc/luks/boot_os.keyfile -
echo -n "${LUKS_PASSWORD}" | cryptsetup luksAddKey ${DEVP}5 /etc/luks/boot_os.keyfile -

# Cryptsetup-Konfigurations-Hook erstellen
echo "KEYFILE_PATTERN=/etc/luks/*.keyfile" >> /etc/cryptsetup-initramfs/conf-hook
echo "CRYPTSETUP=y" >> /etc/cryptsetup-initramfs/conf-hook
mkdir -p /etc/initramfs-tools/hooks/
echo "UMASK=0077" >> /etc/initramfs-tools/initramfs.conf

# Das Laden der Verschlüsselungsmodule einrichten
cat >> /etc/initramfs-tools/modules << EOT
aes
xts
sha256
dm_crypt
EOT

# Crypttab mit initramfs flag für boot einrichten
echo "${LUKS_BOOT_NAME} UUID=\$(blkid -s UUID -o value ${DEVP}1) /etc/luks/boot_os.keyfile luks,discard,initramfs" > /etc/crypttab
echo "${LUKS_ROOT_NAME} UUID=\$(blkid -s UUID -o value ${DEVP}5) /etc/luks/boot_os.keyfile luks,discard,initramfs" >> /etc/crypttab

# Crypttab Datei-Rechte setzen
chmod 600 /etc/crypttab

# Initramfs-Hook für persistentes Boot-Mapping erstellen
mkdir -p /etc/initramfs-tools/hooks/
cat > /etc/initramfs-tools/hooks/persist-boot << 'EOF'
#!/bin/sh
set -e

PREREQ="cryptroot"
prereqs() {
    echo "$PREREQ"
}

case "$1" in
    prereqs)
        prereqs
        exit 0
        ;;
esac

. /usr/share/initramfs-tools/hook-functions

# Kopiere benötigte Tools ins initramfs
copy_exec /sbin/dmsetup

# Stelle sicher, dass das Zielverzeichnis existiert
mkdir -p $DESTDIR/usr/share/initramfs-tools/scripts/local-top

# Skript zum Persistieren des Mappings
cat > "$DESTDIR/usr/share/initramfs-tools/scripts/local-top/persist_boot" << 'EOL'
#!/bin/sh

PREREQ="cryptroot"
prereqs() {
    echo "$PREREQ"
}

case "$1" in
    prereqs)
        prereqs
        exit 0
        ;;
esac

# Erstelle persistentes Mapping für boot und root
for vol in BOOT ROOT; do
  if [ -e "/dev/mapper/$vol" ]; then
    dmsetup table /dev/mapper/$vol > /tmp/${vol,,}_table
    dmsetup remove /dev/mapper/$vol
    dmsetup create $vol --table "$(cat /tmp/${vol,,}_table)"
    # Flag setzen für systemd
    mkdir -p /run/systemd
    touch /run/systemd/cryptsetup-$vol.service.active
  fi
done
EOL

chmod +x "$DESTDIR/usr/share/initramfs-tools/scripts/local-top/persist_boot"
EOF

# Hook ausführbar machen
chmod +x /etc/initramfs-tools/hooks/persist-boot
#   CRYPTSETUP   #
##################


##################
#   BOOTLOADER   #
# GRUB Verzeichnisse vorbereiten
mkdir -p /etc/default/
mkdir -p /etc/default/grub.d/

# GRUB-Konfiguration erstellen
cat > /etc/default/grub <<GRUBCFG
# Autogenerierte GRUB-Konfiguration
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=1
GRUB_DISTRIBUTOR="$(. /etc/os-release && echo "$NAME")"
GRUB_CMDLINE_LINUX_DEFAULT="nomodeset"
GRUB_CMDLINE_LINUX=""
GRUB_ENABLE_CRYPTODISK=y
GRUB_GFXMODE=1280x1024
GRUBCFG

#
# GRUB_CMDLINE_LINUX_DEFAULT="quiet splash nomodeset loglevel=3 rd.systemd.show_status=auto rd.udev.log_level=3"
#

# GRUB Konfigurationsdatei-Rechte setzen
chmod 644 /etc/default/grub

# GRUB Hauptkonfiguration aktualisieren
sed -i 's/GRUB_ENABLE_CRYPTODISK=.*/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub

# Initramfs aktualisieren und GRUB installieren
update-initramfs -u -k all
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck
update-grub
#   BOOTLOADER   #
##################


# Zram für Swap konfigurieren
cat > /etc/default/zramswap <<EOZ
# Konfiguration für zramswap
PERCENT=200
ALLOCATION=lz4
EOZ

# Benutzer anlegen
useradd -m -s /bin/bash -G sudo ${USERNAME}
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd

# Desktop-Umgebung installieren
echo "INSTALL_DESKTOP=${INSTALL_DESKTOP}, DESKTOP_ENV=${DESKTOP_ENV}, DESKTOP_SCOPE=${DESKTOP_SCOPE}" >> /var/log/install.log
if [ "${INSTALL_DESKTOP}" = "1" ]; then
    case "${DESKTOP_ENV}" in
        # GNOME Desktop
        1)
            echo "Installiere GNOME-Desktop-Umgebung..."
            if [ "${DESKTOP_SCOPE}" = "1" ]; then
                # Standard-Installation
                pkg_install --no-install-recommends \
                    gnome-session \
                    gnome-shell \
                    gdm3 \
                    libpam-gnome-keyring \
                    gsettings-desktop-schemas \
                    gnome-disk-utility \
                    gnome-text-editor \
                    gnome-terminal \
                    gnome-tweaks \
                    gnome-shell-extensions \
                    gnome-shell-extension-manager \
                    gnome-system-monitor \
                    chrome-gnome-shell \
                    gufw \
                    dconf-editor \
                    dconf-cli \
                    nautilus \
                    nautilus-hide \
                    ubuntu-gnome-wallpapers \
                    yad \
                    virtualbox-guest-additions-iso \
                    virtualbox-guest-utils \
                    virtualbox-guest-x11
                echo "DEBUG: Desktop-Installation abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            else
                # Minimale Installation
                pkg_install --no-install-recommends \
                    gnome-session \
                    gnome-shell \
                    gdm3 \
                    libpam-gnome-keyring \
                    gsettings-desktop-schemas \
                    gnome-disk-utility \
                    gnome-text-editor \
                    gnome-terminal \
                    gnome-tweaks \
                    gnome-shell-extensions \
                    gnome-shell-extension-manager \
                    gnome-system-monitor \
                    chrome-gnome-shell \
                    gufw \
                    dconf-editor \
                    dconf-cli \
                    nautilus \
                    nautilus-hide \
                    ubuntu-gnome-wallpapers \
                    yad \
                    virtualbox-guest-additions-iso \
                    virtualbox-guest-utils \
                    virtualbox-guest-x11
                echo "DEBUG: Desktop-Installation abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            fi
            ;;
            
        # KDE Plasma Desktop (momentan nur Platzhalter)
        2)
            echo "KDE Plasma wird derzeit noch nicht unterstützt. Installiere GNOME stattdessen..."
            if [ "${DESKTOP_SCOPE}" = "1" ]; then
                pkg_install --no-install-recommends \
                    virtualbox-guest-additions-iso \
                    virtualbox-guest-utils \
                    virtualbox-guest-x11
                echo "DEBUG: Desktop-Installation abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            else
                pkg_install --no-install-recommends \
                    virtualbox-guest-additions-iso \
                    virtualbox-guest-utils \
                    virtualbox-guest-x11                
                echo "DEBUG: Desktop-Installation abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            fi
            ;;
            
        # Xfce Desktop (momentan nur Platzhalter)
        3)
            echo "Xfce wird derzeit noch nicht unterstützt. Installiere GNOME stattdessen..."
            if [ "${DESKTOP_SCOPE}" = "1" ]; then
                pkg_install --no-install-recommends \
                    virtualbox-guest-additions-iso \
                    virtualbox-guest-utils \
                    virtualbox-guest-x11
                echo "DEBUG: Desktop-Installation abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            else
                pkg_install --no-install-recommends \
                    virtualbox-guest-additions-iso \
                    virtualbox-guest-utils \
                    virtualbox-guest-x11
                echo "DEBUG: Desktop-Installation abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            fi
            ;;
            
        # Fallback
        *)
            echo "Unbekannte Desktop-Umgebung. Installiere GNOME..."
            # Fallback-Paketliste (GNOME)
            pkg_install --no-install-recommends \
                    gnome-session \
                    gnome-shell \
                    gdm3 \
                    libpam-gnome-keyring \
                    gsettings-desktop-schemas \
                    gnome-disk-utility \
                    gnome-text-editor \
                    gnome-terminal \
                    gnome-tweaks \
                    gnome-shell-extensions \
                    gnome-shell-extension-manager \
                    gnome-system-monitor \
                    chrome-gnome-shell \
                    gufw \
                    dconf-editor \
                    dconf-cli \
                    nautilus \
                    nautilus-hide \
                    ubuntu-gnome-wallpapers \
                    yad \
                    virtualbox-guest-additions-iso \
                    virtualbox-guest-utils \
                    virtualbox-guest-x11
            echo "DEBUG: Desktop-Installation abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            ;;
    esac
fi

# Desktop-Sprachpakete installieren
if [ "${INSTALL_DESKTOP}" = "1" ]; then
    echo "Installiere Sprachpakete für ${UI_LANGUAGE}..."
    
    # Gemeinsame Sprachpakete für alle Desktop-Umgebungen
    pkg_install language-pack-${UI_LANGUAGE%_*} language-selector-common
    
    # Desktop-spezifische Sprachpakete
    case "${DESKTOP_ENV}" in
        # GNOME Desktop
        1)
            pkg_install language-pack-gnome-${UI_LANGUAGE%_*} language-selector-gnome
            ;;
        # KDE Plasma Desktop
        2)
            pkg_install language-pack-kde-${UI_LANGUAGE%_*} kde-l10n-${UI_LANGUAGE%_*} || true
            ;;
        # Xfce Desktop
        3)
            pkg_install language-pack-${UI_LANGUAGE%_*}-base xfce4-session-l10n || true
            ;;
    esac
    
    # Default-Sprache für das System setzen
    cat > /etc/default/locale <<LOCALE
LANG=${LOCALE}
LC_MESSAGES=${UI_LANGUAGE}.UTF-8
LOCALE

    # AccountsService-Konfiguration für GDM/Anmeldebildschirm
    if [ -d "/var/lib/AccountsService/users" ]; then
        mkdir -p /var/lib/AccountsService/users/
        for user in /home/*; do
            username=$(basename "$user")
            if [ -d "$user" ] && [ "$username" != "lost+found" ]; then
                echo "[User]" > "/var/lib/AccountsService/users/$username"
                echo "Language=${UI_LANGUAGE}.UTF-8" >> "/var/lib/AccountsService/users/$username"
                echo "XSession=ubuntu" >> "/var/lib/AccountsService/users/$username"
            fi
        done
    fi
fi


#########################
#   SYSTEMANPASSUNGEN   #

# Deaktiviere unnötige systemd-Dienste
systemctl disable --now \
    gnome-remote-desktop.service \
    gnome-remote-desktop-configuration.service \
    apport.service \
    apport-autoreport.service \
    avahi-daemon.service \
    bluetooth.service \
    cups.service \
    ModemManager.service \
    upower.service \
    rsyslog.service

# Optional: Zusätzliche Bereinigung für Desktop-Systeme
if [ "${INSTALL_DESKTOP}" = "1" ]; then
    systemctl disable --now \
        whoopsie.service \
        kerneloops.service \
        NetworkManager-wait-online.service
fi
#   SYSTEMANPASSUNGEN   #
#########################


# Aufräumen
echo "Bereinige temporäre Dateien..."
pkg_clean
pkg_autoremove
rm -f /setup.sh
MAINEOF

# Setze Variablen für das Chroot-Skript
sed -i "s/\${HOSTNAME}/$HOSTNAME/g" /mnt/ubuntu/setup.sh
sed -i "s/\${USERNAME}/$USERNAME/g" /mnt/ubuntu/setup.sh
sed -i "s/\${USER_PASSWORD}/$USER_PASSWORD/g" /mnt/ubuntu/setup.sh
sed -i "s/\${LUKS_PASSWORD}/$LUKS_PASSWORD/g" /mnt/ubuntu/setup.sh
sed -i "s|\${DEVP}|$DEVP|g" /mnt/ubuntu/setup.sh
sed -i "s|\${DM}|$DM|g" /mnt/ubuntu/setup.sh
sed -i "s/\${KERNEL_TYPE}/$KERNEL_TYPE/g" /mnt/ubuntu/setup.sh
sed -i "s/\${INSTALL_MODE}/$INSTALL_MODE/g" /mnt/ubuntu/setup.sh
sed -i "s/\${ADDITIONAL_PACKAGES}/$ADDITIONAL_PACKAGES/g" /mnt/ubuntu/setup.sh
sed -i "s/\${UBUNTU_CODENAME}/$UBUNTU_CODENAME/g" /mnt/ubuntu/setup.sh
sed -i "s/\${UPDATE_OPTION}/$UPDATE_OPTION/g" /mnt/ubuntu/setup.sh
sed -i "s/\${INSTALL_DESKTOP}/$INSTALL_DESKTOP/g" /mnt/ubuntu/setup.sh
sed -i "s/\${DESKTOP_ENV}/$DESKTOP_ENV/g" /mnt/ubuntu/setup.sh
sed -i "s/\${DESKTOP_SCOPE}/$DESKTOP_SCOPE/g" /mnt/ubuntu/setup.sh
sed -i "s/\${UI_LANGUAGE}/$UI_LANGUAGE/g" /mnt/ubuntu/setup.sh
sed -i "s/\${LOCALE}/$LOCALE/g" /mnt/ubuntu/setup.sh
sed -i "s/\${KEYBOARD_LAYOUT}/$KEYBOARD_LAYOUT/g" /mnt/ubuntu/setup.sh
sed -i "s/\${TIMEZONE}/$TIMEZONE/g" /mnt/ubuntu/setup.sh
sed -i "s/\${NETWORK_CONFIG}/$NETWORK_CONFIG/g" /mnt/ubuntu/setup.sh
sed -i "s|\${STATIC_IP_CONFIG}|$STATIC_IP_CONFIG|g" /mnt/ubuntu/setup.sh
sed -i "s/\${LUKS_BOOT_NAME}/$LUKS_BOOT_NAME/g" /mnt/ubuntu/setup.sh
sed -i "s/\${LUKS_ROOT_NAME}/$LUKS_ROOT_NAME/g" /mnt/ubuntu/setup.sh

# Ausführbar machen
chmod +x /mnt/ubuntu/setup.sh

show_progress 70
}

execute_chroot() {
log_progress "Führe Installation in chroot-Umgebung durch..."

# chroot ausführen
log_info "Ausführen von setup.sh in chroot..."
chroot /mnt/ubuntu /setup.sh

log_info "Installation in chroot abgeschlossen."
show_progress 80
}


#########################
#  SYSTEMEINSTELLUNGEN  #
# Automatische Benutzeranmeldung konfigurieren
log_info "Konfiguriere GDM für automatische Anmeldung direkt in der Installation..."
mkdir -p /mnt/ubuntu/etc/gdm3
cat > /mnt/ubuntu/etc/gdm3/custom.conf <<EOF
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

# AccountsService konfigurieren
mkdir -p /mnt/ubuntu/var/lib/AccountsService/users
cat > /mnt/ubuntu/var/lib/AccountsService/users/${USERNAME} <<EOF
[User]
Language=${LOCALE}
XSession=ubuntu
SystemAccount=false
AutomaticLogin=true
EOF

setup_system_settings() {
    log_progress "Erstelle Systemeinstellungen-Skript..."
    
    # Skript erstellen, das beim ersten Start mit root-Rechten ausgeführt wird
    cat > /mnt/ubuntu/usr/local/bin/post_install_settings.sh <<'EOF'
#!/bin/bash
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
    echo "Kompiliere glib-Schemas..."
    glib-compile-schemas /usr/share/glib-2.0/schemas/

# Installiere GNOME Shell Erweiterungen
    echo "Installiere GNOME Shell Erweiterungen..."
    
    # GNOME Shell Version ermitteln
    GNOME_VERSION=$(gnome-shell --version | cut -d ' ' -f 3 | cut -d '.' -f 1,2)
    GNOME_MAJOR_VERSION=$(echo $GNOME_VERSION | cut -d '.' -f 1)
    echo "Erkannte GNOME Shell Version: $GNOME_VERSION (Major: $GNOME_MAJOR_VERSION)"
    
    # Abhängigkeiten installieren
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
    CURRENT_USER=$(logname)
    CURRENT_USER_UID=$(id -u "$CURRENT_USER" 2>/dev/null || echo "1000")
    DBUS_SESSION="unix:path=/run/user/$CURRENT_USER_UID/bus"
    
    # Versuche, die Einstellungen anzuwenden
    sudo -u $CURRENT_USER DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION" gsettings set org.gnome.shell.extensions.impatience speed-factor 0.3 2>/dev/null || true
    sudo -u $CURRENT_USER DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION" gsettings set org.gnome.shell.extensions.burn-my-windows close-effect 'pixelwipe' 2>/dev/null || true
    sudo -u $CURRENT_USER DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION" gsettings set org.gnome.shell.extensions.burn-my-windows open-effect 'pixelwipe' 2>/dev/null || true
    sudo -u $CURRENT_USER DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION" gsettings set org.gnome.shell.extensions.burn-my-windows animation-time 300 2>/dev/null || true
    sudo -u $CURRENT_USER DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION" gsettings set org.gnome.shell.extensions.burn-my-windows pixelwipe-pixel-size 7 2>/dev/null || true

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

    # Script erstellen für Umleitung des Sperr-Knopfes zum Benutzer-Wechsel
    echo "Erstelle ScreenLocker-Ersatz für Benutzer-Wechsel..."
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

    # Zusätzlich direktes Setzen wichtiger Einstellungen per gsettings für den aktuellen Benutzer
    CURRENT_USER=$(logname || who | head -1 | awk '{print $1}')
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

# Zeige ein Benachrichtigungsfenster
zenity --question \
  --title="System-Einrichtung abgeschlossen" \
  --text="Die System-Einrichtung wurde abgeschlossen.\nEin Neustart wird empfohlen, um alle Änderungen vollständig zu aktivieren.\n\nMöchtest du jetzt neu starten?" \
  --width=400 \
  --icon-name=system-software-update
  
if [ $? -eq 0 ]; then
  # Benutzer hat "Ja" gewählt
  zenity --info --title="Neustart" --text="Das System wird jetzt neu gestartet..." --timeout=3
  # Entferne dieses Skript aus dem Autostart
  rm -f ~/.config/autostart/first-login-notification.desktop
  # Neustart
  reboot
else
  # Benutzer hat "Nein" gewählt
  zenity --info --title="Information" --text="Bitte starte das System später manuell neu."
  # Entferne dieses Skript aus dem Autostart
  rm -f ~/.config/autostart/first-login-notification.desktop
fi
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
# Frage nach einem Systemneustart
echo
echo -e "\nMöchtest du das System jetzt neu starten, um alle Änderungen zu aktivieren? (j/n)"
read -n 1 -r restart_system
echo

if [[ "$restart_system" =~ ^[Jj]$ ]]; then
    echo "Systemneustart wird durchgeführt..."
    echo "Das System wird jetzt neu gestartet..."
    sleep 2
    reboot
else
    echo "Bitte starte das System neu, um alle Änderungen vollständig zu aktivieren."
fi
exit 0
EOF

    # Skript ausführbar machen
    chmod 755 /mnt/ubuntu/usr/local/bin/post_install_settings.sh
    
    # Systemd-Service erstellen, der das Skript beim ersten Start mit Root-Rechten ausführt
    mkdir -p /mnt/ubuntu/etc/systemd/system/
    cat > /mnt/ubuntu/etc/systemd/system/post-install-settings.service <<EOF
[Unit]
Description=Post-Installation Settings
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/post_install_settings.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    # Service aktivieren
    mkdir -p /mnt/ubuntu/etc/systemd/system/multi-user.target.wants/
    ln -sf /etc/systemd/system/post-install-settings.service /mnt/ubuntu/etc/systemd/system/multi-user.target.wants/post-install-settings.service
    
    log_info "Systemeinstellungen-Skript erfolgreich erstellt."
    show_progress 90
}
#  SYSTEMEINSTELLUNGEN  #
#########################


###################
#    ABSCHLUSS    #
finalize_installation() {
    log_progress "Schließe Installation ab..."
    
    # Speichere Konfiguration, wenn gewünscht
    if [[ $SAVE_CONFIG =~ ^[Jj]$ ]]; then
        read -p "Pfad zum Speichern der Konfiguration [$CONFIG_FILE]: " config_save_path
        save_config "${config_save_path:-$CONFIG_FILE}"
    fi
    
    # Aufräumen
    log_info "Bereinige und beende Installation..."
    umount -R /mnt/ubuntu
    
    log_info "Installation abgeschlossen!"
    log_info "System kann jetzt neu gestartet werden."
    log_info "Hostname: $HOSTNAME"
    log_info "Benutzer: $USERNAME"
    
    show_progress 100
    echo
    
    # Bash-Profile entfernen (Aufräumen)
    rm -f /root/.bash_profile
    log_info "Temporäre SSH-Konfiguration entfernt."

    # Neustart-Abfrage
    read -p "Jetzt neustarten? (j/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Jj]$ ]]; then
        log_info "System wird neu gestartet..."
        reboot
    fi

    # Signal für lokalen Prozess, dass wir fertig sind
    for sem in /tmp/install_done_*; do
        touch "$sem" 2>/dev/null || true
    done
}
#    ABSCHLUSS    #
###################


###################
#  HAUPTFUNKTION  #
main() {
    # Prüfe auf SSH-Verbindung
    if [ "$1" = "ssh_connect" ]; then
        clear
        echo -e "${CYAN}============================================================${NC}"
        echo -e "${CYAN}   UbuntuFDE - Automatisches Installationsskript            ${NC}"
        echo -e "${CYAN}   Version: ${SCRIPT_VERSION}                               ${NC}"
        echo -e "${CYAN}============================================================${NC}"
        echo -e "${GREEN}[INFO]${NC} Fortführung der Installation via SSH."
        
        # Lade gespeicherte Einstellungen
        if [ -f /tmp/install_config ]; then
            source /tmp/install_config
        fi
    else
        # Normale Initialisierung
        clear
        echo -e "${CYAN}============================================================${NC}"
        echo -e "${CYAN}   UbuntuFDE - Automatisches Installationsskript            ${NC}"
        echo -e "${CYAN}   Version: ${SCRIPT_VERSION}                               ${NC}"
        echo -e "${CYAN}============================================================${NC}"
        echo
        
        # Logdatei initialisieren
        echo "UbuntuFDE Installation - $(date)" > "$LOG_FILE"

        # Falls Installer noch läuft, versuche diesen zu beenden
        if pgrep subiquity > /dev/null; then
            log_info "Beende laufenden Ubuntu-Installer..."
            pkill -9 subiquity || true
        fi    
        
        # Systemcheck
        check_root
        check_system
        check_dependencies
        find_fastest_mirrors
    fi
    
    # Installation
    echo
    echo -e "${CYAN}Starte Installationsprozess...${NC}"
    echo
    
    # Benutzereingaben sammeln
    gather_user_input
    gather_disk_input

    # Warnung vor der Partitionierung
    if ! confirm "${YELLOW}ALLE DATEN AUF $DEV WERDEN GELÖSCHT!${NC}"; then
        log_warn "Partitionierung abgebrochen. Beginne erneut mit der Auswahl der Festplatte..."
        unset DEV SWAP_SIZE ROOT_SIZE DATA_SIZE
        gather_disk_input
        # Erneute Bestätigung, bis der Benutzer ja sagt
        while ! confirm "${YELLOW}ALLE DATEN AUF $DEV WERDEN GELÖSCHT!${NC}; do
            log_warn "Partitionierung abgebrochen. Beginne erneut mit der Auswahl der Festplatte..."
            unset DEV SWAP_SIZE ROOT_SIZE DATA_SIZE
            gather_disk_input
        done
    fi

    echo -e "\n${GREEN}[INFO]${NC} Partitionierung bestätigt. Die Festplatte wird nach Abschluss aller Konfigurationsfragen partitioniert."
    DISK_CONFIRMED=true
    export DISK_CONFIRMED
    
    # Installation durchführen
    prepare_disk
    setup_encryption
    setup_lvm
    mount_filesystems
    install_base_system
    copy_nala_config
    download_thorium
    prepare_chroot
    execute_chroot
    setup_system_settings
    finalize_installation
}
#  HAUPTFUNKTION  #
###################


# Skript starten
main "$@"
