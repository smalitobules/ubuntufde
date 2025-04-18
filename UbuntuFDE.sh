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

# Wrapper-Funktion für Paketoperationen
pkg_install() {
    if command -v nala &> /dev/null; then
        apt install -y "$@"
    else
        apt-get install -y "$@"
    fi
}

pkg_update() {
    if command -v nala &> /dev/null; then
        apt update
    else
        apt-get update
    fi
}

pkg_upgrade() {
    if command -v nala &> /dev/null; then
        apt upgrade -y
    else
        apt-get dist-upgrade --ignore-hold -y
    fi
}

pkg_clean() {
    if command -v nala &> /dev/null; then
        apt clean
    else
        apt-get clean
    fi
}

pkg_autoremove() {
    if command -v nala &> /dev/null; then
        apt autoremove -y
    else
        apt-get autoremove -y
    fi
}

###################
#   Systemcheck   #
# Überprüfe die Ausführung mit erhöhten Rechten
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${YELLOW}[HINWEIS]${NC} Dieses Skript benötigt Administrative-Rechte. Starte neu mit erhöhten Rechten..."
        exec sudo "$0" "$@"  # Starte das Skript neu mit erhöhten Rechten...
    fi
}

# Programm-Abhängigkeiten prüfen und installieren
check_dependencies() {
    log_info "Richte Paketquellen für lokalen Spiegelserver ein..."

    # Bereinige bestehende Paketquellen-Dateien
    for file in /etc/apt/*.list; do
        if [ -f "$file" ]; then
            rm -f "$file"
        fi
    done

    for file in /etc/apt/sources.list.d/*.list; do
        if [ -f "$file" ]; then
            rm -f "$file"
        fi
    done

    for file in /etc/apt/*.save /etc/apt/*/*.save; do
        if [ -f "$file" ]; then
            rm -f "$file"
        fi
    done

    # Lösche den Paket-Cache
    pkg_clean

    # Richte lokalen Spiegelserver ein
    mkdir -p /etc/apt/sources.list.d
    cat > /etc/apt/sources.list.d/sources.list <<-EOSOURCES
deb http://192.168.56.120/ubuntu/ plucky main restricted universe multiverse
deb http://192.168.56.120/ubuntu/ plucky-updates main restricted universe multiverse
deb http://192.168.56.120/ubuntu/ plucky-security main restricted universe multiverse
deb http://192.168.56.120/ubuntu/ plucky-backports main restricted universe multiverse
EOSOURCES

        # Importiere GPG-Schlüssel vom Spiegelserver
        log_info "Importiere GPG-Schlüssel für lokalen Mirror..."
        mkdir -p /etc/apt/trusted.gpg.d/
        curl -fsSL http://192.168.56.120/repo-key.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/local-mirror.gpg

        # Lokalen Spiegelserver als bevorzugt festlegen
        cat > /etc/apt/preferences.d/local-mirror <<EOL
Package: *
Pin: origin 192.168.56.120
Pin-Priority: 1001
EOL

    MIRRORS_OPTIMIZED="true"
    export MIRRORS_OPTIMIZED
    
    log_info "Lokalen Spiegelserver ist eingerichtet."

    # Konfiguriere dpkg-Optimierungen
    mkdir -p /etc/dpkg/dpkg.cfg.d/
    echo "force-unsafe-io" > /etc/dpkg/dpkg.cfg.d/unsafe-io
    mkdir -p /etc/apt/apt.conf.d/
    echo "Dpkg::Parallelize=true;" > /etc/apt/apt.conf.d/70parallelize

    log_info "Prüfe auf Programm-Abhängigkeiten..."
    
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
        log_warn "Konnte Betriebssystem nicht erkennen."
    fi
}
#   Systemcheck   #
###################


find_fastest_mirrors() {
    log_info "Suche nach den schnellsten Paketquellen..."
    
    # Sicherstellen, dass nala installiert ist
    if ! command -v nala &> /dev/null; then
        log_error "${RED}Fehler: Nala wurde nicht gefunden!${NC} Die Installation kann nicht fortgesetzt werden. Bitte starte die Installation erneut."
        echo -e "${RED}Fehler: Nala wurde nicht gefunden!${NC} Die Installation kann nicht fortgesetzt werden. Bitte starte die Installation erneut."
        exit 1
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
    
    # Variable für maximale Anzahl von Versuchen
    MAX_ATTEMPTS=3
    ATTEMPTS=0
    
    # Schleife für nala fetch mit mehreren Versuchen
    while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
        # Erhöhe Versuchszähler
        ((ATTEMPTS++))
        
        log_info "Versuche $ATTEMPTS/$MAX_ATTEMPTS: Suche nach den schnellsten Spiegelservern..."
        
        # Führe nala fetch mit dem erkannten Land aus
        if nala fetch --auto --fetches 3 --country "$COUNTRY_CODE"; then
            # Erfolg: Schleife verlassen
            break
        fi
        
        # Kurze Pause zwischen Versuchen
        sleep 6
        
        # Wenn letzter Versuch gescheitert
        if [ $ATTEMPTS -eq $MAX_ATTEMPTS ]; then
            log_error "${RED}Konnte nach $MAX_ATTEMPTS Versuchen keine Spiegelserver finden!${NC} Bitte überprüfe Deine Netzwerkverbindung und starte das Installationsskript erneut."
            exit 1
        fi
    done
    
    # Prüfe, ob die Optimierung erfolgreich war
    if [ -f /etc/apt/sources.list.d/nala-sources.list ]; then
        log_info "Spiegelserver-Optimierung erfolgreich."
        MIRRORS_OPTIMIZED="true"
    else
        log_error "Keine optimierten Spiegelserver gefunden. Bitte überprüfe deine Netzwerkverbindung und starte das Installationsskript erneut."
        exit 1
    fi
    
    # Exportiere die Variablen
    export COUNTRY_CODE
    export MIRRORS_OPTIMIZED
}

copy_sources_config() {
  if [ "${MIRRORS_OPTIMIZED}" = "true" ]; then
    # Bereite das Zielverzeichnis vor
    mkdir -p /mnt/ubuntu/etc/apt/sources.list.d/
    
    # Entferne etwaig vorhandene Paketquellen-Dateien
    rm -f /mnt/ubuntu/etc/apt/sources.list
    rm -f /mnt/ubuntu/etc/apt/sources.list.d/*.list
    
    # Kopiere Paketquellen-Datei aus dem Installationsystem in chroot-Umgebung
    cp -f /etc/apt/sources.list.d/sources.list /mnt/ubuntu/etc/apt/sources.list.d/
  fi
}

setup_ssh_access() {
    # Lösche bestehendes Bash-Profil
    rm -f /root/.bash_profile
    
    # Generiere 6-stellige PIN für SSH-Passwort
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

    # Sprache der Tastatur
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
            UBUNTU_CODENAME="plucky"  # Ubuntu 25.04 (Plucky Puffin)
        fi
elif [ "$UBUNTU_INSTALL_OPTION" = "2" ]; then
        echo -e "\nVerfügbare Ubuntu-Versionen:"
        echo "1) 25.04 (Plucky Puffin) - aktuell"
        echo "2) 24.10 (Oracular Oriole)"
        echo "3) 24.04 LTS (Noble Numbat) - langzeitunterstützt"
        echo "4) 22.04 LTS (Jammy Jellyfish) - langzeitunterstützt"
        read -p "Wähle eine Version [1]: " UBUNTU_VERSION_OPTION
        
        case ${UBUNTU_VERSION_OPTION:-1} in
            1) UBUNTU_CODENAME="plucky" ;;
            2) UBUNTU_CODENAME="oracular" ;;
            3) UBUNTU_CODENAME="noble" ;;
            4) UBUNTU_CODENAME="jammy" ;;
            *) UBUNTU_CODENAME="plucky" ;;
        esac
    else
        # Minimale Installation
        UBUNTU_CODENAME="plucky"
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
        if ! confirm "${YELLOW}ALLE DATEN AUF${NC} $DEV ${YELLOW}WERDEN${NC} ${RED}GELÖSCHT!${NC}"; then
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
#   BASISSYSTEM   #
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
}

install_base_system() {
    log_progress "Installiere Basissystem..."

    # GPG-Schlüssel für lokalen Mirror importieren
    log_info "Importiere GPG-Schlüssel für lokalen Mirror..."
    mkdir -p /mnt/ubuntu/etc/apt/trusted.gpg.d/
    curl -fsSL http://192.168.56.120/repo-key.gpg | gpg --dearmor -o /mnt/ubuntu/etc/apt/trusted.gpg.d/local-mirror.gpg
    
    # Zu inkludierende Pakete definieren
    INCLUDED_PACKAGES=(
        7zip apt-transport-https bash-completion btop ca-certificates
        cifs-utils console-setup coreutils cryptsetup cryptsetup-initramfs
        curl efibootmgr fastfetch gnupg grub-efi-amd64 grub-efi-amd64-signed
        initramfs-tools jq locales lvm2 mesa-utils nala nano net-tools
        network-manager openssh-server shim-signed smbclient sudo
        systemd-resolved timeshift ufw unrar-free unzip util-linux
        vulkan-tools wget zram-tools zstd
    )

    # Optional auszuschließende Pakete definieren
    EXCLUDED_PACKAGES=(
        snapd cloud-init ubuntu-pro-client ubuntu-docs*
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
            plucky \
            /mnt/ubuntu \
            http://192.168.56.120/ubuntu
    else
        debootstrap \
            --include="$INCLUDED_PACKAGELIST" \
            --exclude="$EXCLUDED_PACKAGELIST" \
            --components=main,restricted,universe,multiverse \
            --arch=amd64 \
            plucky \
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

# Konfiguriere dpkg-Optimierungen in der chroot-Umgebung
mkdir -p /mnt/ubuntu/etc/dpkg/dpkg.cfg.d/
echo "force-unsafe-io" > /mnt/ubuntu/etc/dpkg/dpkg.cfg.d/unsafe-io
mkdir -p /mnt/ubuntu/etc/apt/apt.conf.d/
echo "Dpkg::Parallelize=true;" > /mnt/ubuntu/etc/apt/apt.conf.d/70parallelize
#   BASISSYSTEM   #
###################


# System-Setup in chroot
log_progress "Konfiguriere System in chroot-Umgebung..."
cat > /mnt/ubuntu/setup.sh <<EOSETUP
#!/bin/bash
set -e

## Unterdrücke die Zwischenaufrufe von Kernel-Aktualisierungen
#dpkg-divert --add --rename --divert /usr/sbin/update-initramfs.real /usr/sbin/update-initramfs
#
## Erstelle einen temporären Ersatz
#cat > /usr/sbin/update-initramfs << 'EOF'
##!/bin/sh
## Temporär deaktiviertes update-initramfs während der Installation
#echo "update-initramfs wurde temporär deaktiviert"
#exit 0
#EOF
#chmod +x /usr/sbin/update-initramfs

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

# Wrapper-Funktion für Paketoperationen
pkg_install() {
    if command -v nala &> /dev/null; then
        apt install -y "\$@"
    else
        apt-get install -y "\$@"
    fi
}

pkg_update() {
    if command -v nala &> /dev/null; then
        apt update
    else
        apt-get update
    fi
}

pkg_upgrade() {
    if command -v nala &> /dev/null; then
        apt upgrade -y
    else
        apt-get dist-upgrade -y
    fi
}

pkg_clean() {
    if command -v nala &> /dev/null; then
        apt clean
    else
        apt-get clean
    fi
}

pkg_autoremove() {
    if command -v nala &> /dev/null; then
        apt autoremove -y
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
        nala fetch --ubuntu plucky --auto --fetches 3 --country "\$COUNTRY_CODE"
    fi
fi

# GPG-Schlüssel für lokales Repository importieren
if [ ! -f "/etc/apt/trusted.gpg.d/local-mirror.gpg" ]; then
    curl -fsSL http://192.168.56.120/repo-key.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/local-mirror.gpg
fi

# Repositories für Anwendugen einrichten

    mkdir -p /etc/apt/keyrings

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

# Grundlegende Programme für Desktopfreie-Umgebung installieren
if [ "${INSTALL_DESKTOP}" != "1" ]; then
    pkg_install --no-install-recommends \
        \${KERNEL_PACKAGES}
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
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
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

## Entferne die Unterdrückung der Zwischenaufrufe von Kernel-Aktualisierungen
#rm -f /usr/sbin/update-initramfs
#dpkg-divert --remove --rename /usr/sbin/update-initramfs

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


#########################
#  DESKTOPINSTALLATION  #
# Desktop-Umgebung mit Sprachpaketen installieren
echo "INSTALL_DESKTOP=${INSTALL_DESKTOP}, DESKTOP_ENV=${DESKTOP_ENV}, DESKTOP_SCOPE=${DESKTOP_SCOPE}" >> /var/log/install.log
if [ "${INSTALL_DESKTOP}" = "1" ]; then
    # Basis-Sprachpakete für alle Desktop-Umgebungen
    BASE_LANGUAGE_PACKAGES="language-pack-${UI_LANGUAGE%_*} language-selector-common"
    
    case "${DESKTOP_ENV}" in
        # GNOME Desktop
        1)
            echo "Installiere GNOME Desktop mit Sprachpaketen für ${UI_LANGUAGE}..."
            # GNOME-spezifische Sprachpakete
            GNOME_LANGUAGE_PACKAGES="language-pack-gnome-${UI_LANGUAGE%_*} language-selector-gnome"
            
            if [ "${DESKTOP_SCOPE}" = "1" ]; then
                # Standard-Installation mit Sprachpaketen
                pkg_install --no-install-recommends \
                    \${KERNEL_PACKAGES} \
                    \${BASE_LANGUAGE_PACKAGES} \
                    \${GNOME_LANGUAGE_PACKAGES} \
                    xserver-xorg \
                    xorg \
                    x11-common \
                    x11-xserver-utils \
                    xdotool \
                    dbus-x11 \
                    gnome-session \
                    gnome-shell \
                    gdm3 \
                    libpam-gnome-keyring \
                    gsettings-desktop-schemas \
                    gparted \
                    gnome-disk-utility \
                    gnome-text-editor \
                    gnome-terminal \
                    gnome-tweaks \
                    gnome-shell-extensions \
                    gnome-shell-extension-manager \
                    gnome-system-monitor \
                    chrome-gnome-shell \
                    gufw \
                    gir1.2-gtop-2.0 \
                    libgtop-2.0-11 \
                    dconf-editor \
                    dconf-cli \
                    nautilus \
                    nautilus-hide \
                    nautilus-admin \
                    ubuntu-gnome-wallpapers \
                    yad \
                    bleachbit \
                    stacer \
                    vlc \
                    deluge \
                    virtualbox-guest-additions-iso \
                    virtualbox-guest-utils \
                    virtualbox-guest-x11
                echo "DEBUG: Desktop-Installation mit Sprachpaketen abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            else
                # Minimale Installation mit Sprachpaketen
                pkg_install --no-install-recommends \
                    \${KERNEL_PACKAGES} \
                    \${BASE_LANGUAGE_PACKAGES} \
                    \${GNOME_LANGUAGE_PACKAGES} \
                    xserver-xorg \
                    xorg \
                    x11-common \
                    x11-xserver-utils \
                    xdotool \
                    dbus-x11 \
                    gnome-session \
                    gnome-shell \
                    gdm3 \
                    libpam-gnome-keyring \
                    gsettings-desktop-schemas \
                    gparted \
                    gnome-disk-utility \
                    gnome-text-editor \
                    gnome-terminal \
                    gnome-tweaks \
                    gnome-shell-extensions \
                    gnome-shell-extension-manager \
                    gnome-system-monitor \
                    chrome-gnome-shell \
                    gufw \
                    gir1.2-gtop-2.0 \
                    libgtop-2.0-11 \
                    dconf-editor \
                    dconf-cli \
                    nautilus \
                    nautilus-hide \
                    nautilus-admin \
                    ubuntu-gnome-wallpapers \
                    yad \
                    bleachbit \
                    stacer \
                    vlc \
                    deluge \
                    virtualbox-guest-additions-iso \
                    virtualbox-guest-utils \
                    virtualbox-guest-x11
                echo "DEBUG: Desktop-Installation mit Sprachpaketen abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            fi
            ;;
            
        # KDE Plasma Desktop
        2)
            echo "KDE Plasma wird derzeit noch nicht unterstützt. Installiere GNOME stattdessen..."
            # KDE-spezifische Sprachpakete
            KDE_LANGUAGE_PACKAGES="language-pack-kde-${UI_LANGUAGE%_*}"
            
            # Füge kde-l10n nur hinzu wenn verfügbar (ist in neueren Versionen nicht mehr vorhanden)
            if apt-cache show kde-l10n-${UI_LANGUAGE%_*} >/dev/null 2>&1; then
                KDE_LANGUAGE_PACKAGES+=" kde-l10n-${UI_LANGUAGE%_*}"
            fi
            
            if [ "${DESKTOP_SCOPE}" = "1" ]; then
                pkg_install --no-install-recommends \
                    \${KERNEL_PACKAGES} \
                    \${BASE_LANGUAGE_PACKAGES} \
                    \${KDE_LANGUAGE_PACKAGES} \
                    virtualbox-guest-additions-iso \
                    virtualbox-guest-utils \
                    virtualbox-guest-x11
                echo "DEBUG: Desktop-Installation mit Sprachpaketen abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            else
                pkg_install --no-install-recommends \
                    \${KERNEL_PACKAGES} \
                    \${BASE_LANGUAGE_PACKAGES} \
                    \${KDE_LANGUAGE_PACKAGES} \
                    virtualbox-guest-additions-iso \
                    virtualbox-guest-utils \
                    virtualbox-guest-x11                
                echo "DEBUG: Desktop-Installation mit Sprachpaketen abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            fi
            ;;
            
        # Xfce Desktop
        3)
            echo "Xfce wird derzeit noch nicht unterstützt. Installiere GNOME stattdessen..."
            # Xfce-spezifische Sprachpakete
            XFCE_LANGUAGE_PACKAGES="language-pack-${UI_LANGUAGE%_*}-base"
            
            # Füge xfce4-session-l10n nur hinzu wenn verfügbar
            if apt-cache show xfce4-session-l10n >/dev/null 2>&1; then
                XFCE_LANGUAGE_PACKAGES+=" xfce4-session-l10n"
            fi
            
            if [ "${DESKTOP_SCOPE}" = "1" ]; then
                pkg_install --no-install-recommends \
                    \${KERNEL_PACKAGES} \
                    \${BASE_LANGUAGE_PACKAGES} \
                    \${XFCE_LANGUAGE_PACKAGES} \
                    virtualbox-guest-additions-iso \
                    virtualbox-guest-utils \
                    virtualbox-guest-x11
                echo "DEBUG: Desktop-Installation mit Sprachpaketen abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            else
                pkg_install --no-install-recommends \
                    \${KERNEL_PACKAGES} \
                    \${BASE_LANGUAGE_PACKAGES} \
                    \${XFCE_LANGUAGE_PACKAGES} \
                    virtualbox-guest-additions-iso \
                    virtualbox-guest-utils \
                    virtualbox-guest-x11
                echo "DEBUG: Desktop-Installation mit Sprachpaketen abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            fi
            ;;
            
        # Fallback
        *)
            echo "Unbekannte Desktop-Umgebung. Installiere GNOME..."
            # Fallback-Paketliste (GNOME)
            GNOME_LANGUAGE_PACKAGES="language-pack-gnome-${UI_LANGUAGE%_*} language-selector-gnome"
            
            pkg_install --no-install-recommends \
                    \${KERNEL_PACKAGES} \
                    \${BASE_LANGUAGE_PACKAGES} \
                    \${GNOME_LANGUAGE_PACKAGES} \
                    xserver-xorg \
                    xorg \
                    x11-common \
                    x11-xserver-utils \
                    xdotool \
                    dbus-x11 \
                    gnome-session \
                    gnome-shell \
                    gdm3 \
                    libpam-gnome-keyring \
                    gsettings-desktop-schemas \
                    gparted \
                    gnome-disk-utility \
                    gnome-text-editor \
                    gnome-terminal \
                    gnome-tweaks \
                    gnome-shell-extensions \
                    gnome-shell-extension-manager \
                    gnome-system-monitor \
                    chrome-gnome-shell \
                    gufw \
                    gir1.2-gtop-2.0 \
                    libgtop-2.0-11 \
                    dconf-editor \
                    dconf-cli \
                    nautilus \
                    nautilus-hide \
                    nautilus-admin \
                    ubuntu-gnome-wallpapers \
                    yad \
                    bleachbit \
                    stacer \
                    vlc \
                    deluge \
                    virtualbox-guest-additions-iso \
                    virtualbox-guest-utils \
                    virtualbox-guest-x11
            echo "DEBUG: Desktop-Installation mit Sprachpaketen abgeschlossen, exit code: $?" >> /var/log/install-debug.log
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

# Thorium Browser installieren
if [ "${INSTALL_DESKTOP}" = "1" ] && [ -f /tmp/thorium.deb ]; then
    echo "Thorium-Browser-Paket gefunden, installiere..."
    
    # # Wichtige Abhängigkeiten vorab installieren
    # echo "Installiere kritische Abhängigkeiten für Thorium..."
    # apt install -y libasound2 libatk-bridge2.0-0 libatk1.0-0 libatspi2.0-0 libcups2 libcurl4 libglib2.0-0 libgtk-3-0
    
    # Installation mit apt, das Abhängigkeiten automatisch auflöst
    echo "Installiere Thorium-Browser..."
    if apt install -y --fix-broken /tmp/thorium.deb; then
        echo "Thorium wurde erfolgreich installiert."
    else
        echo "Thorium-Installation über apt fehlgeschlagen, versuche alternativen Ansatz..."
        # Abhängigkeiten beheben und erneut versuchen
        apt -f install -y
        if dpkg -i /tmp/thorium.deb; then
            echo "Thorium wurde im zweiten Versuch erfolgreich installiert."
        else
            echo "Thorium-Installation fehlgeschlagen."
        fi
    fi
    
    # Überprüfen, ob die Installation tatsächlich erfolgreich war
    if [ -f /usr/bin/thorium-browser ]; then
        echo "Thorium-Browser wurde erfolgreich installiert und ist unter /usr/bin/thorium-browser verfügbar."
    else
        echo "Thorium-Installation konnte nicht abgeschlossen werden."
    fi
    
    # Aufräumen
    rm -f /tmp/thorium.deb
fi

#  DESKTOPINSTALLATION  #
#########################


# Deaktiviere unerwünschte Systemd-Dienste
echo "Deaktiviere unerwünschte Systemd-Dienste..."
SERVICES_TO_DISABLE=(
    gnome-remote-desktop.service
    gnome-remote-desktop-configuration.service
    apport.service
    apport-autoreport.service
    avahi-daemon.service
    bluetooth.service
    cups.service
    ModemManager.service
    upower.service
    rsyslog.service
    whoopsie.service
    kerneloops.service
    NetworkManager-wait-online.service
)

for service in "${SERVICES_TO_DISABLE[@]}"; do
    systemctl disable $service >/dev/null 2>&1 || true
done

# Aufräumen
echo "Bereinige temporäre Dateien..."
pkg_clean
pkg_autoremove
rm -f /setup.sh
EOSETUP

    # Setup.sh Ausführbar machen
    chmod 755 /mnt/ubuntu/setup.sh

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
# Desktop-Versionen ermitteln
desktop_version_detect() {
    log_progress "Ermittle Desktop-Umgebungsversionen..."
    
    # Variablen initialisieren (ohne Standardwerte)
    GNOME_VERSION=""
    GNOME_MAJOR_VERSION=""
    KDE_VERSION=""
    KDE_MAJOR_VERSION=""
    XFCE_VERSION=""
    XFCE_MAJOR_VERSION=""
    
    if [ "$INSTALL_DESKTOP" = "1" ]; then
        case "$DESKTOP_ENV" in
            # GNOME
            1)
                log_info "Prüfe GNOME-Version..."
                if GNOME_VERSION_OUTPUT=$(chroot /mnt/ubuntu gnome-shell --version 2>/dev/null); then
                    GNOME_VERSION=$(echo "$GNOME_VERSION_OUTPUT" | cut -d ' ' -f 3 | cut -d '.' -f 1,2)
                    GNOME_MAJOR_VERSION=$(echo "$GNOME_VERSION" | cut -d '.' -f 1)
                    log_info "Erkannte GNOME Shell Version: $GNOME_VERSION"
                else
                    log_warn "Konnte GNOME-Version nicht ermitteln. Installation wird trotzdem fortgesetzt."
                fi
                ;;
                
            # KDE Plasma
            2)
                log_info "Prüfe KDE Plasma Version..."
                if KDE_VERSION_OUTPUT=$(chroot /mnt/ubuntu plasmashell --version 2>/dev/null); then
                    KDE_VERSION=$(echo "$KDE_VERSION_OUTPUT" | grep -oP '\d+\.\d+\.\d+')
                    KDE_MAJOR_VERSION=$(echo "$KDE_VERSION" | cut -d '.' -f 1)
                    log_info "Erkannte KDE Plasma Version: $KDE_VERSION (Major: $KDE_MAJOR_VERSION)"
                else
                    log_warn "Konnte KDE-Version nicht ermitteln. Installation wird trotzdem fortgesetzt."
                fi
                ;;
                
            # Xfce
            3)
                log_info "Prüfe Xfce Version..."
                if XFCE_VERSION_OUTPUT=$(chroot /mnt/ubuntu xfce4-about --version 2>/dev/null || chroot /mnt/ubuntu xfce4-session --version 2>/dev/null); then
                    XFCE_VERSION=$(echo "$XFCE_VERSION_OUTPUT" | grep -oP '\d+\.\d+\.\d+' | head -1)
                    XFCE_MAJOR_VERSION=$(echo "$XFCE_VERSION" | cut -d '.' -f 1)
                    log_info "Erkannte Xfce Version: $XFCE_VERSION (Major: $XFCE_MAJOR_VERSION)"
                else
                    log_warn "Konnte Xfce-Version nicht ermitteln. Installation wird trotzdem fortgesetzt."
                fi
                ;;
                
            *)
                log_warn "Unbekannte Desktop-Umgebung: $DESKTOP_ENV. Installation wird trotzdem fortgesetzt."
                ;;
        esac
    else
        log_info "Keine Desktop-Installation ausgewählt."
    fi
    
    # Exportiere alle Variablen
    export GNOME_VERSION GNOME_MAJOR_VERSION KDE_VERSION KDE_MAJOR_VERSION XFCE_VERSION XFCE_MAJOR_VERSION
    
    # Zusätzliche Desktop-spezifische Variablen erstellen
    case "$DESKTOP_ENV" in
        1) DESKTOP_NAME="GNOME"; DESKTOP_VERSION="$GNOME_VERSION"; DESKTOP_MAJOR_VERSION="$GNOME_MAJOR_VERSION" ;;
        2) DESKTOP_NAME="KDE"; DESKTOP_VERSION="$KDE_VERSION"; DESKTOP_MAJOR_VERSION="$KDE_MAJOR_VERSION" ;;
        3) DESKTOP_NAME="Xfce"; DESKTOP_VERSION="$XFCE_VERSION"; DESKTOP_MAJOR_VERSION="$XFCE_MAJOR_VERSION" ;;
        *) DESKTOP_NAME="Unknown"; DESKTOP_VERSION=""; DESKTOP_MAJOR_VERSION="" ;;
    esac
    
    export DESKTOP_NAME DESKTOP_VERSION DESKTOP_MAJOR_VERSION
    
    if [ -n "$DESKTOP_VERSION" ]; then
        log_info "Desktop-Umgebung: $DESKTOP_NAME Version $DESKTOP_VERSION"
    else
        log_info "Desktop-Umgebung: $DESKTOP_NAME"
    fi
}

# Autologin für erstellten Benutzer einrichten
configure_autologin() {
    if [ "$INSTALL_DESKTOP" != "1" ]; then
        log_info "Kein Desktop gewählt, überspringe Autologin-Konfiguration"
        return 0
    fi

    log_info "Konfiguriere automatische Anmeldung für ${USERNAME}..."
    
    case "${DESKTOP_ENV}" in
        # GNOME Desktop
        1)
            log_info "Konfiguriere GDM für automatische Anmeldung..."
            mkdir -p /mnt/ubuntu/etc/gdm3 || log_warn "Konnte GDM3-Verzeichnis nicht erstellen"
            if [ -d "/mnt/ubuntu/etc/gdm3" ]; then
                cat > /mnt/ubuntu/etc/gdm3/custom.conf <<EOFGDM
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
EOFGDM
                chmod 644 /mnt/ubuntu/etc/gdm3/custom.conf
                log_info "GDM-Konfiguration erstellt"
            fi

            # AccountsService konfigurieren
            mkdir -p /mnt/ubuntu/var/lib/AccountsService/users || log_warn "Konnte AccountsService-Verzeichnis nicht erstellen"
            if [ -d "/mnt/ubuntu/var/lib/AccountsService/users" ]; then
                cat > "/mnt/ubuntu/var/lib/AccountsService/users/${USERNAME}" <<EOFACCOUNT
[User]
Language=${LOCALE:-de_DE.UTF-8}
XSession=ubuntu
SystemAccount=false
AutomaticLogin=true
EOFACCOUNT
                chmod 644 "/mnt/ubuntu/var/lib/AccountsService/users/${USERNAME}"
                log_info "AccountsService für Benutzer ${USERNAME} konfiguriert"
            fi
            ;;
            
        # KDE Plasma Desktop
        2)
            log_info "Konfiguriere SDDM für automatische Anmeldung..."
            mkdir -p /mnt/ubuntu/etc/sddm.conf.d || log_warn "Konnte SDDM-Verzeichnis nicht erstellen"
            if [ -d "/mnt/ubuntu/etc/sddm.conf.d" ]; then
                cat > /mnt/ubuntu/etc/sddm.conf.d/autologin.conf <<EOFSDDM
[Autologin]
User=${USERNAME}
Session=plasma.desktop
Relogin=false
EOFSDDM
                chmod 644 /mnt/ubuntu/etc/sddm.conf.d/autologin.conf
                log_info "SDDM-Konfiguration erstellt"
            fi
            ;;
            
        # Xfce Desktop
        3)
            log_info "Konfiguriere LightDM für automatische Anmeldung..."
            mkdir -p /mnt/ubuntu/etc/lightdm || log_warn "Konnte LightDM-Verzeichnis nicht erstellen"
            if [ -d "/mnt/ubuntu/etc/lightdm" ]; then
                cat > /mnt/ubuntu/etc/lightdm/lightdm.conf <<EOFLIGHTDM
[SeatDefaults]
autologin-user=${USERNAME}
autologin-user-timeout=0
user-session=xfce
greeter-session=lightdm-gtk-greeter
EOFLIGHTDM
                chmod 644 /mnt/ubuntu/etc/lightdm/lightdm.conf
                log_info "LightDM-Konfiguration erstellt"
            fi
            ;;
            
        # Fallback für unbekannte Desktop-Umgebungen
        *)
            log_warn "Unbekannte Desktop-Umgebung ${DESKTOP_ENV}, überspringe Autologin-Konfiguration"
            ;;
    esac
}

# Konfiguriere das installierte System
setup_system_settings() {
    log_progress "Erstelle Systemeinstellungen-Skript..."
    
    # Systemd-Service erstellen, der das Skript beim ersten Start mit Root-Rechten ausführt
    mkdir -p /mnt/ubuntu/etc/systemd/system/
    cat > /mnt/ubuntu/etc/systemd/system/post-install-setup.service <<EOPOSTSERVICE
[Unit]
Description=Post-Installation Setup
# Diese Zeile hinzufügen, damit es vor dem Display-Manager (Login-Bildschirm) läuft
Before=display-manager.service
After=network.target
# Diese Option sicherstellen, dass GDM erst startet, wenn dieses Skript fertig ist
Conflicts=rescue.service rescue.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/post_install_setup.sh
RemainAfterExit=yes
TimeoutSec=60

[Install]
WantedBy=multi-user.target
# Auch hier sicherstellen, dass es vor GDM läuft
WantedBy=display-manager.service
EOPOSTSERVICE
    
    # Service aktivieren
    mkdir -p /mnt/ubuntu/etc/systemd/system/multi-user.target.wants/
    ln -sf /etc/systemd/system/post-install-setup.service /mnt/ubuntu/etc/systemd/system/multi-user.target.wants/post-install-setup.service
    
    # Skript für post-install-setup erstellen
    mkdir -p /mnt/ubuntu/usr/local/bin/
    cat > /mnt/ubuntu/usr/local/bin/post_install_setup.sh <<'EOPOSTSCRIPT'
#!/bin/bash
# Post-Installation Setup für systemweite Einstellungen
# Wird VOR der Benutzeranmeldung ausgeführt
#
# Datum: $(date +%Y-%m-%d)

# Erweiterte Logging-Funktionen
LOG_FILE="/var/log/post-install-setup.log"
mkdir -p "$(dirname "$LOG_FILE")"
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

# Prüfe GNOME-Komponenten
log "Prüfe GNOME-Komponenten..."
if [ -f /usr/bin/gnome-shell ]; then
    log "GNOME Shell gefunden: $(gnome-shell --version)"
else
    log "INFO: GNOME Shell nicht gefunden. Dies ist normal, wenn kein Desktop installiert wurde."
fi

# DBus-Session für Systembenutzer starten
if [ ! -e "/run/user/0/bus" ]; then
    log "Starte dbus-daemon für System-Benutzer..."
    mkdir -p /run/user/0
    dbus-daemon --session --address=unix:path=/run/user/0/bus --nofork --print-address &
    sleep 2
    export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/0/bus
fi

# Systemweite GNOME-Einstellungen
log "Verwende erkannte Desktop-Umgebung: ${DESKTOP_NAME} ${DESKTOP_VERSION}"

if [ -z "$DESKTOP_ENV" ]; then
    # Fallback-Erkennung nur wenn nötig
    if [ -f /usr/bin/gnome-shell ]; then
        DESKTOP_ENV="gnome"
    elif [ -f /usr/bin/plasmashell ]; then
        DESKTOP_ENV="kde"
    elif [ -f /usr/bin/xfce4-session ]; then
        DESKTOP_ENV="xfce"
    else
        DESKTOP_ENV="unknown"
    fi
    log "Desktop-Umgebung lokal erkannt: $DESKTOP_ENV"
fi

# GNOME-spezifische Einstellungen
if [ "$DESKTOP_ENV" = "gnome" ]; then
    log "Konfiguriere ${DESKTOP_NAME} ${DESKTOP_VERSION} Einstellungen..."
    
    # Directory für gsettings-override erstellen
    mkdir -p /usr/share/glib-2.0/schemas/
    
    # Erstelle Schema-Override-Datei für allgemeine GNOME-Einstellungen
    cat > /usr/share/glib-2.0/schemas/90_ubuntu-fde.gschema.override <<EOSETTINGS
# UbuntuFDE Schema Override für GNOME

[org.gnome.desktop.input-sources]
sources=[('xkb', '$KEYBOARD_LAYOUT')]
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
picture-uri='file:///usr/share/backgrounds/Puffin_by_moskalenko-v-dark.png'
picture-uri-dark='file:///usr/share/backgrounds/Puffin_by_moskalenko-v-dark.png'
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
favorite-apps=['org.gnome.Nautilus.desktop', 'thorium-browser.desktop', 'org.gnome.Terminal.desktop']
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
sources=[('xkb', '$KEYBOARD_LAYOUT')]
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
    log "Kompiliere glib-Schemas..."
    glib-compile-schemas /usr/share/glib-2.0/schemas/

# GNOME-Umgebungsvariablen konfigurieren
log "Konfiguriere GNOME-Umgebungsvariablen für bessere Performance"
echo "GNOME_SHELL_SLOWDOWN_FACTOR=0.33" >> /etc/environment
echo "NO_AT_BRIDGE=1" >> /etc/environment

# Installiere GNOME Shell Erweiterungen
    log "Installiere GNOME Shell Erweiterungen..."
    
    # GNOME Shell Version ermitteln
    GNOME_VERSION=$(gnome-shell --version 2>/dev/null | cut -d ' ' -f 3 | cut -d '.' -f 1,2 || echo "")
    GNOME_MAJOR_VERSION=$(echo $GNOME_VERSION | cut -d '.' -f 1)
    log "Erkannte GNOME Shell Version: $GNOME_VERSION (Major: $GNOME_MAJOR_VERSION)"
    
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
                    log "WARNUNG: extension.js nicht gefunden!"
                fi
                
                # Setze Berechtigungen
                chmod -R 755 "/usr/share/gnome-shell/extensions/$uuid"
                
                # Passe metadata.json an, um die GNOME-Version explizit zu unterstützen
                if [ -f "/usr/share/gnome-shell/extensions/$uuid/metadata.json" ]; then
                    log "Passe metadata.json an, um GNOME $GNOME_VERSION zu unterstützen"
                    
                    # Sicherungskopie erstellen
                    cp "/usr/share/gnome-shell/extensions/$uuid/metadata.json" "/usr/share/gnome-shell/extensions/$uuid/metadata.json.bak"
                    
                    # Füge die aktuelle GNOME-Version zur Liste der unterstützten Versionen hinzu
                    if command -v jq &>/dev/null; then
                        jq --arg version "$GNOME_MAJOR_VERSION" --arg fullversion "$GNOME_VERSION" \
                           'if .["shell-version"] then .["shell-version"] += [$version, $fullversion] else .["shell-version"] = [$version, $fullversion] end' \
                           "/usr/share/gnome-shell/extensions/$uuid/metadata.json.bak" > "/usr/share/gnome-shell/extensions/$uuid/metadata.json"
                    else
                        # Fallback wenn jq nicht verfügbar ist
                        # Wir verwenden sed, um die Versionen hinzuzufügen
                        sed -i 's/"shell-version": \[\(.*\)\]/"shell-version": [\1, "'$GNOME_MAJOR_VERSION'", "'$GNOME_VERSION'"]/' "/usr/share/gnome-shell/extensions/$uuid/metadata.json"
                    fi
                    
                    log "metadata.json angepasst: Version $GNOME_VERSION hinzugefügt"
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
    
    log "Installiere Burn My Windows..."
    install_extension "$BURN_MY_WINDOWS_UUID"
    
    log "Installiere System Monitor..."
    install_extension "$SYSTEM_MONITOR_UUID" || true  # Fortsetzung auch bei Fehler

    # Einstellungen der Extensions Systemweit einrichten

        # Burn My Windows Standardkonfiguration
        mkdir -p /etc/skel/.local/share/gnome-shell/extensions/burn-my-windows@schneegans.github.com/
        echo '{
        "close-effect": "pixelwipe",
        "open-effect": "pixelwipe",
        "animation-time": 300,
        "pixelwipe-pixel-size": 7
        }' > /etc/skel/.local/share/gnome-shell/extensions/burn-my-windows@schneegans.github.com/prefs.json

        # Dash to Panel Standardkonfiguration
        mkdir -p /etc/skel/.local/share/gnome-shell/extensions/dash-to-panel@jderose9.github.com/
        echo '{
        "panel-size": 48,
        "animate-show-apps": true,
        "appicon-margin": 4,
        "appicon-padding": 4,
        "dot-position": "BOTTOM",
        "dot-style-focused": "DOTS",
        "dot-style-unfocused": "DOTS",
        "focus-highlight": true,
        "isolate-workspaces": true
        }' > /etc/skel/.local/share/gnome-shell/extensions/dash-to-panel@jderose9.github.com/prefs.json

        # Berechtigungen setzen
        chmod -R 755 /etc/skel/.local/share/gnome-shell/extensions/*

    # Erstelle das first_login_setup.sh Skript für Benutzereinstellungen
    log "Erstelle first_login_setup.sh für benutzerspezifische Einstellungen..."
    mkdir -p /usr/local/bin/
    
    cat > /usr/local/bin/first_login_setup.sh << 'EOLOGINSETUP'
#!/bin/bash
# First-Login-Setup für benutzerspezifische Einstellungen

# Theme für YAD-Dialoge setzen
export GTK_THEME=Adwaita:dark

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
            
            # Burn My Windows
            log "Konfiguriere Burn My Windows Extension..."
            mkdir -p $HOME/.config/burn-my-windows/profiles/
            cat > $HOME/.config/burn-my-windows/profiles/1744486167399235.conf <<EOBURN
[burn-my-windows-profile]
fire-enable-effect=false
pixel-wipe-enable-effect=true
pixel-wipe-animation-time=300
pixel-wipe-pixel-size=7
EOBURN

            
        show_progress 40
            
            # Dash to Panel
            log "Konfiguriere Dash to Panel Extension..."
            mkdir -p $HOME/.local/share/gnome-shell/extensions/dash-to-panel@jderose9.github.com/
            echo '{
            "panel-size": 48,
            "animate-show-apps": true,
            "appicon-margin": 4,
            "appicon-padding": 4,
            "dot-position": "BOTTOM",
            "dot-style-focused": "DOTS",
            "dot-style-unfocused": "DOTS",
            "focus-highlight": true,
            "isolate-workspaces": true
            }' > $HOME/.local/share/gnome-shell/extensions/dash-to-panel@jderose9.github.com/prefs.json

            # Setze Berechtigungen
            chown -R $USER:$USER $HOME/.local/share/gnome-shell/
            
        show_progress 45
        
        # Weitere GNOME-spezifische Einstellungen
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
        gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
        gsettings set org.gnome.desktop.session idle-delay 0
        gsettings set org.gnome.desktop.screensaver lock-enabled false
        gsettings set org.gnome.desktop.privacy show-full-name-in-top-bar false
        gsettings set org.gnome.desktop.interface clock-show-seconds true
        gsettings set org.gnome.desktop.interface clock-show-weekday true
        gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer', 'kms-modifiers', 'variable-refresh-rate', 'autoclose-xwayland']"

        
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

        # Nautilus-Favoriten konfigurieren
        if command -v nautilus &>/dev/null; then
            log "Konfiguriere Nautilus-Seitenleiste..."
            
            # Lesezeichen-Datei leeren, um benutzerdefinierte Lesezeichen zu entfernen
            mkdir -p $HOME/.config/gtk-3.0
            touch $HOME/.config/gtk-3.0/bookmarks
            
            # Nautilus-Einstellungen für Seitenleiste anpassen
            gsettings set org.gnome.nautilus.window-state sidebar-width 180
            gsettings set org.gnome.nautilus.window-state start-with-sidebar true
            
            # Zeige Standard-Orte in der Seitenleiste
            gsettings set org.gnome.nautilus.sidebar-panels.places show-places-list true
            
            # Versuche, die Kategorie "Favoriten" auszublenden
            dconf write /org/gnome/nautilus/window-state/sidebar-bookmark-breakpoint false
            
            # Optional: Aktiviere die Anzeige von Verzeichnissen unter "Persönlicher Ordner"
            gsettings set org.gnome.nautilus.preferences show-directory-item-counts 'always'
            
            # Berechtigungen setzen
            chown -R $USER:$USER $HOME/.config/gtk-3.0
            
            # Aktualisierung der Nautilus-Einstellungen erzwingen
            if pgrep nautilus >/dev/null; then
                killall -HUP nautilus || true
            fi
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
        --text="<b><big><span font_family='DejaVu Sans'>System-Setup erfolgreich!</span></big></b>\n\n\nAlle Einstellungen wurden korrekt angewendet.\n\n" \
        --button="OK":0 \
        --center --width=400 \
        --borders=20 \
        --text-align=center \
        --fixed \
        --on-top \
        --buttons-layout=center \
        --undecorated
        
    # Entferne dieses Skript aus dem Autostart
    rm -f "$HOME/.config/autostart/first-login-setup.desktop"
    
    # Selbstzerstörung mit Verzögerung einleiten
    (sleep 3 && sudo rm -f "$0") &
elif [ "$validation_exit_code" -eq 1 ]; then
    # Teilweise erfolgreich mit Warnungen
    yad --warning \
        --title="Setup mit Warnungen abgeschlossen" \
        --text="<b><big><span font_family='DejaVu Sans'>System-Setup teilweise abgeschlossen!</span></big></b>\n\n\nEinige Einstellungen konnten nicht vollständig angewendet werden.\nDas System ist aber funktionsfähig.\n\nSiehe: $HOME/.first-login-validation.log\n\n" \
        --button="OK":0 \
        --center --width=450 \
        --borders=20 \
        --text-align=center \
        --fixed \
        --on-top \
        --buttons-layout=center \
        --undecorated
        
    # Entferne dieses Skript aus dem Autostart
    rm -f "$HOME/.config/autostart/first-login-setup.desktop"
    
    # Selbstzerstörung mit Verzögerung einleiten
    (sleep 3 && sudo rm -f "$0") &
else
    # Fehlgeschlagen
    yad --error \
        --title="Setup unvollständig" \
        --text="<b><big><span font_family='DejaVu Sans'>System-Setup unvollständig!</span></big></b>\n\n\nKritische Einstellungen konnten nicht angewendet werden.\n\nBitte prüfe die Logdatei: $HOME/.first-login-validation.log\n\nDas Setup wird beim nächsten Login erneut versucht.\n\n" \
        --button="OK":0 \
        --center --width=450 \
        --borders=20 \
        --text-align=center \
        --fixed \
        --on-top \
        --buttons-layout=center \
        --undecorated
    
    # Skript bleibt für einen weiteren Versuch erhalten
    echo "Setup unvollständig. Das Skript bleibt für einen weiteren Versuch erhalten."
fi

# Beenden mit entsprechendem Exitcode
exit $validation_exit_code
EOLOGINSETUP

    # Skript ausführbar machen
    chmod 755 /usr/local/bin/first_login_setup.sh
    
    # Erstellen des Autostart-Eintrags für alle Benutzer (Template in /etc/skel)
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

    # Kopiere den Autostart-Eintrag für bestehende Benutzer
    mkdir -p /home/${USERNAME}/.config/autostart
    cp /etc/skel/.config/autostart/first-login-setup.desktop /home/${USERNAME}/.config/autostart/
    chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.config
    
elif [ "$DESKTOP_ENV" = "kde" ]; then
    # KDE-spezifische Einstellungen (ähnliche Struktur wie für GNOME)
    log "KDE-spezifische Einstellungen werden implementiert..."
    # Hier KDE-spezifische Code einfügen
    
elif [ "$DESKTOP_ENV" = "xfce" ]; then
    # Xfce-spezifische Einstellungen (ähnliche Struktur wie für GNOME)
    log "Xfce-spezifische Einstellungen werden implementiert..."
    # Hier Xfce-spezifische Code einfügen
    
else
    log "Keine bekannte Desktop-Umgebung gefunden."
fi

# Funktion zur Überprüfung, ob Systemkomponenten korrekt installiert wurden
check_system_setup() {
    local errors=0
    local log_file="/var/log/system-setup-validation.log"
    
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
    
    # 3. Prüfen, ob der Autostart-Eintrag erstellt wurde
    log "Prüfe Autostart-Konfiguration..." 
    if [ ! -f "/etc/skel/.config/autostart/first-login-setup.desktop" ]; then
        log "FEHLER: Autostart-Eintrag für First-Login-Setup fehlt!"
        ((errors++))
    else
        log "OK: Autostart-Eintrag wurde korrekt erstellt."
    fi
    
    # 4. GNOME-spezifische Prüfungen
    if [ "$DESKTOP_ENV" = "gnome" ]; then
        # Prüfen, ob die GNOME-Shell-Erweiterungen installiert wurden
        log "Prüfe GNOME-Shell-Erweiterungen..." 
        extensions=("dash-to-panel@jderose9.github.com" "user-theme@gnome-shell-extensions.gcampax.github.com")
        for ext in "${extensions[@]}"; do
            if [ ! -d "/usr/share/gnome-shell/extensions/$ext" ]; then
                log "FEHLER: GNOME-Erweiterung $ext fehlt!"
                ((errors++))
            else
                if [ -f "/usr/share/gnome-shell/extensions/$ext/extension.js" ]; then
                    log "OK: Erweiterung $ext wurde korrekt installiert."
                else
                    log "FEHLER: Erweiterung $ext fehlt wesentliche Dateien!"
                    ((errors++))
                fi
            fi
        done
        
        # Prüfen, ob die Schemas kompiliert wurden
        log "Prüfe, ob Schemas kompiliert wurden..." 
        if [ ! -f "/usr/share/glib-2.0/schemas/gschemas.compiled" ]; then
            log "FEHLER: Schema-Kompilierung fehlgeschlagen!"
            ((errors++))
        else
            schema_time=$(stat -c %Y "/usr/share/glib-2.0/schemas/gschemas.compiled")
            current_time=$(date +%s)
            if [ $((current_time - schema_time)) -gt 300 ]; then
                log "WARNUNG: Schema-Kompilierung könnte veraltet sein."
            else
                log "OK: Schemas wurden kürzlich kompiliert."
            fi
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
EOPOSTSCRIPT

    # Skript ausführbar machen
    chmod 755 /mnt/ubuntu/usr/local/bin/post_install_setup.sh

    # Variablen für das Post-Install-Skript setzen
    sed -i "s/\${HOSTNAME}/$HOSTNAME/g" /mnt/ubuntu/usr/local/bin/post_install_setup.sh
    sed -i "s/\${USERNAME}/$USERNAME/g" /mnt/ubuntu/usr/local/bin/post_install_setup.sh
    sed -i "s/\${KEYBOARD_LAYOUT}/$KEYBOARD_LAYOUT/g" /mnt/ubuntu/usr/local/bin/post_install_setup.sh
    sed -i "s/\${UI_LANGUAGE}/$UI_LANGUAGE/g" /mnt/ubuntu/usr/local/bin/post_install_setup.sh
    sed -i "s/\${LOCALE}/$LOCALE/g" /mnt/ubuntu/usr/local/bin/post_install_setup.sh
    sed -i "s/\${TIMEZONE}/$TIMEZONE/g" /mnt/ubuntu/usr/local/bin/post_install_setup.sh
    sed -i "s/\${DESKTOP_ENV}/$DESKTOP_ENV/g" /mnt/ubuntu/usr/local/bin/post_install_setup.sh
    sed -i "s/\${DESKTOP_SCOPE}/$DESKTOP_SCOPE/g" /mnt/ubuntu/usr/local/bin/post_install_setup.sh
    sed -i "s/\${DESKTOP_NAME}/$DESKTOP_NAME/g" /mnt/ubuntu/usr/local/bin/post_install_setup.sh
    sed -i "s/\${DESKTOP_VERSION}/$DESKTOP_VERSION/g" /mnt/ubuntu/usr/local/bin/post_install_setup.sh
    sed -i "s/\${DESKTOP_MAJOR_VERSION}/$DESKTOP_MAJOR_VERSION/g" /mnt/ubuntu/usr/local/bin/post_install_setup.sh
    sed -i "s/\${GNOME_VERSION}/$GNOME_VERSION/g" /mnt/ubuntu/usr/local/bin/post_install_setup.sh
    sed -i "s/\${GNOME_MAJOR_VERSION}/$GNOME_MAJOR_VERSION/g" /mnt/ubuntu/usr/local/bin/post_install_setup.sh
    sed -i "s/\${KDE_VERSION}/$KDE_VERSION/g" /mnt/ubuntu/usr/local/bin/post_install_setup.sh
    sed -i "s/\${KDE_MAJOR_VERSION}/$KDE_MAJOR_VERSION/g" /mnt/ubuntu/usr/local/bin/post_install_setup.sh
    sed -i "s/\${XFCE_VERSION}/$XFCE_VERSION/g" /mnt/ubuntu/usr/local/bin/post_install_setup.sh
    sed -i "s/\${XFCE_MAJOR_VERSION}/$XFCE_MAJOR_VERSION/g" /mnt/ubuntu/usr/local/bin/post_install_setup.sh
    
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

    # Logdatei auf externe Partition kopieren
    if mount /dev/sdb1 /media/data; then
        cp -f "$LOG_FILE" /media/data
        umount /media/data
    else
        echo "WARNUNG: Konnte /dev/sdb1 nicht mounten. Logdatei bleibt an originalem Speicherort."
    fi
    
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
        # find_fastest_mirrors
    fi
    
    # Installation
    echo
    echo -e "${CYAN}Starte Installationsprozess...${NC}"
    echo
    
    # Benutzereingaben sammeln
    gather_user_input
    gather_disk_input

    # Warnung vor der Partitionierung
    if ! confirm "${YELLOW}ALLE DATEN AUF${NC} $DEV ${YELLOW}WERDEN${NC} ${RED}GELÖSCHT!${NC}"; then
        log_warn "Partitionierung abgebrochen. Beginne erneut mit der Auswahl der Festplatte..."
        unset DEV SWAP_SIZE ROOT_SIZE DATA_SIZE
        gather_disk_input
        # Erneute Bestätigung, bis der Benutzer ja sagt
        while ! confirm "${YELLOW}ALLE DATEN AUF${NC} $DEV ${YELLOW}WERDEN${NC} ${RED}GELÖSCHT!${NC}"; do
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
    copy_sources_config
    download_thorium
    prepare_chroot
    execute_chroot
    desktop_version_detect
    configure_autologin
    setup_system_settings
    finalize_installation

}
#  HAUPTFUNKTION  #
###################


# Skript starten
main "$@"
