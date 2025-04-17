#!/bin/bash
# UbuntuFDE ISO-Erstellungsskript
# Dieses Skript erstellt eine minimale Ubuntu-basierte ISO für die UbuntuFDE-Umgebung
# Version: 0.0.1

# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' 

# Verzeichnisse
SCRIPT_DIR="$(pwd)"
WORK_DIR="$(pwd)/iso-build"
CHROOT_DIR="${WORK_DIR}/chroot"
ISO_DIR="${WORK_DIR}/iso"
INITRD_DIR="${WORK_DIR}/initrd"
OUTPUT_DIR="${SCRIPT_DIR}"
LOG_FILE="${SCRIPT_DIR}/iso-build.log"

# ISO-Metadaten
ISO_TITLE="UbuntuFDE"
ISO_PUBLISHER="Smali Tobules"
ISO_APPLICATION="Start UbuntuFDE Environment"
ISO_NAME="UbuntuFDE.iso"
INSTALLATION_URL="https://zenayastudios.com/fde"

# Ubuntu-Konfiguration
UBUNTU_CODENAME="oracular"
UBUNTU_MIRROR="http://192.168.56.120/ubuntu/"

# Paket-Listen
  # Diese Pakete werden installiert
  INCLUDE_PACKAGES=(

  )

  # Diese Pakete werden ausgeschlossen
  EXCLUDE_PACKAGES=(
      snapd
      cloud-init
      ubuntu-pro-client
      ubuntu-docs
      plymouth
      xorriso
      polkitd
      libisoburn1t64
  )


#####################
#  HILFSFUNKTIONEN  #
# Logging-Funktion
log() {
  local level=$1
  shift
  local message="$@"
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  
  # Stelle sicher, dass das Logverzeichnis existiert
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
  touch "$LOG_FILE" 2>/dev/null
  
  case $level in
    "info")
      echo -e "${GREEN}[INFO]${NC} $message"
      echo "[INFO] $timestamp - $message" >> "$LOG_FILE" 2>/dev/null
      ;;
    "warn")
      echo -e "${YELLOW}[WARN]${NC} $message"
      echo "[WARN] $timestamp - $message" >> "$LOG_FILE" 2>/dev/null
      ;;
    "error")
      echo -e "${RED}[ERROR]${NC} $message"
      echo "[ERROR] $timestamp - $message" >> "$LOG_FILE" 2>/dev/null
      ;;
    *)
      echo -e "${BLUE}[DEBUG]${NC} $message"
      echo "[DEBUG] $timestamp - $message" >> "$LOG_FILE" 2>/dev/null
      ;;
  esac
}

# Vorherige Arbeitsumgebung auflösen
cleanup_previous_environment() {
  log info "Bereinige vorherige Build-Verzeichnisse..."
    
  # Alle Einhängepunkte finden und trennen
  if [ -d "$WORK_DIR" ]; then
    mount | grep "$WORK_DIR" | while read line; do
      mountpoint=$(echo "$line" | awk '{print $3}')
      umount -l "$mountpoint" 2>/dev/null
    done
      
    # Prozesse beenden
    fuser -k "$WORK_DIR" 2>/dev/null
  fi
  
  # Verzeichnisse löschen
  rm -rf "$WORK_DIR"
}

# Abhängigkeiten prüfen
check_dependencies() {
  log info "Prüfe Abhängigkeiten auf dem Host-System..."
  local commands=("debootstrap" "mtools" "xorriso" "mksquashfs")
  local packages=("debootstrap" "mtools" "xorriso" "squashfs-tools")
  local missing_packages=()
  
  for i in "${!commands[@]}"; do
    if ! command -v "${commands[$i]}" &> /dev/null; then
      missing_packages+=("${packages[$i]}")
    fi
  done

  # Einstellungen für schnellere Paketinstallation
  mkdir -p /etc/dpkg/dpkg.cfg.d/
  echo "force-unsafe-io" > /etc/dpkg/dpkg.cfg.d/unsafe-io

  mkdir -p /etc/apt/apt.conf.d/
  echo "Dpkg::Parallelize=true;" > /etc/apt/apt.conf.d/70parallelize
  
  if [ ${#missing_packages[@]} -ne 0 ]; then
    log warn "Folgende Abhängigkeiten fehlen auf dem Host-System: ${missing_packages[*]}"
    log info "Installiere fehlende Abhängigkeiten..."
    nala update
    nala install -y "${missing_packages[@]}"
    
    # Erneut prüfen
    for i in "${!commands[@]}"; do
      if ! command -v "${commands[$i]}" &> /dev/null; then
        log error "Abhängigkeit konnte nicht installiert werden: ${packages[$i]}"
        log info "Versuche alternativen Ansatz ohne ${packages[$i]}..."
      fi
    done
  fi
  
  log info "Host-System-Abhängigkeiten sind bereit."
}

# Arbeitsverzeichnisse erstellen
setup_directories() {
  log info "Erstelle Arbeitsverzeichnisse..."
  
  # Hauptverzeichnisstruktur
  rm -rf "$WORK_DIR"
  mkdir -p "$WORK_DIR"
  mkdir -p "$CHROOT_DIR"
  mkdir -p "$ISO_DIR"
  mkdir -p "$INITRD_DIR"
  mkdir -p "$OUTPUT_DIR"
  
  # ISO-Verzeichnisstruktur
  mkdir -p "$ISO_DIR/boot/grub"
  mkdir -p "$ISO_DIR/casper"
  mkdir -p "$ISO_DIR/EFI/BOOT"
  
  # Logdatei initialisieren
  touch "$LOG_FILE"
  
  log info "Arbeitsverzeichnisse bereit."
}
#  HILFSFUNKTIONEN  #
#####################


#####################
#  HAUPTFUNKTIONEN  #
# Basis-System erstellen
create_base_system() {
  log info "Erstelle Basis-System..."
  
  # Paketlisten in kommagetrennte Strings umwandeln
  local include_list=$(IFS=,; echo "${INCLUDE_PACKAGES[*]}")
  local exclude_list=$(IFS=,; echo "${EXCLUDE_PACKAGES[*]}")
  
  # Basisinstallation mit kritischen Paketen
  local base_packages="adduser,apt-utils,bash,ca-certificates,casper,console-setup,cryptsetup,curl \
                      dbus,dhcpcd5,dialog,gpg,gpgv,grub-common,grub-efi-amd64,grub-efi-amd64-bin \
                      grub-pc,grub-pc-bin,grub2-common,iputils-ping,iproute2,keyboard-configuration \
                      kbd,kmod,language-pack-de,language-pack-de-base,language-pack-en \
                      language-pack-en-base,libgcc-s1,libnss-systemd,libpam-systemd,libstdc++6 \
                      libc6,linux-image-generic,locales,login,lvm2,nala,netplan.io,network-manager \
                      passwd,squashfs-tools,systemd,systemd-sysv,tzdata,udev,wget,zstd"
  
  log info "Führe Basisinstallation durch..."
  debootstrap \
    --arch=amd64 \
    --variant=minbase \
    --include="$base_packages,$include_list" \
    --exclude="$exclude_list" \
    --components=main,restricted,universe,multiverse \
    "$UBUNTU_CODENAME" \
    "$CHROOT_DIR" \
    "$UBUNTU_MIRROR"
  
  if [ $? -ne 0 ]; then
    log error "Debootstrap-Installation fehlgeschlagen."
    exit 1
  fi
  
  # Paketquellen konfigurieren 
  configure_sources
  
  # Bereite chroot-Umgebung vor und führe die zentrale Systemaktualisierung und Paketinstallation durch
  prepare_and_update_system
  
  log info "Basis-System erfolgreich erstellt."
}

# Paketquellen konfigurieren
configure_sources() {
  log info "Konfiguriere Paketquellen im chroot..."
  
  # Paketquellen definieren
  cat > "$CHROOT_DIR/etc/apt/sources.list.d/nala-sources.list" << EOF
deb http://192.168.56.120/ubuntu/ oracular main restricted universe multiverse
deb http://192.168.56.120/ubuntu/ oracular-updates main restricted universe multiverse
deb http://192.168.56.120/ubuntu/ oracular-security main restricted universe multiverse
deb http://192.168.56.120/ubuntu/ oracular-backports main restricted universe multiverse
EOF

  # Einstellungen für schnellere Paketinstallation
  mkdir -p "$CHROOT_DIR/etc/dpkg/dpkg.cfg.d/"
  echo "force-unsafe-io" > "$CHROOT_DIR/etc/dpkg/dpkg.cfg.d/unsafe-io"
  mkdir -p "$CHROOT_DIR/etc/apt/apt.conf.d/"
  echo "Dpkg::Parallelize=true;" > "$CHROOT_DIR/etc/apt/apt.conf.d/70parallelize"
  
  # Priorität des lokalen Spiegelservers festlegen
  mkdir -p "$CHROOT_DIR/etc/apt/preferences.d/"
  cat > "$CHROOT_DIR/etc/apt/preferences.d/local-mirror" << EOF
Package: *
Pin: origin 192.168.56.120
Pin-Priority: 1001
EOF

  # GPG-Schlüssel importieren
  mkdir -p "$CHROOT_DIR/tmp"
  curl -fsSL https://archive.ubuntu.com/ubuntu/project/ubuntu-archive-keyring.gpg -o "$CHROOT_DIR/tmp/ubuntu-archive-keyring.gpg"
  curl -fsSL http://192.168.56.120/repo-key.gpg -o "$CHROOT_DIR/tmp/local-mirror.gpg"

  log info "Paketquellen konfiguriert."
}

# Zentrale Funktion für Systemaktualisierung und Paketinstallation
prepare_and_update_system() {
  log info "Bereite chroot-Umgebung vor und führe Systemaktualisierung durch..."
  chroot "$CHROOT_DIR" /bin/bash -c "echo 'Bash wird systemweit als Standard-Shell eingerichtet'"
  chroot "$CHROOT_DIR" /bin/bash -c "update-alternatives --install /bin/sh sh /bin/bash 100"
  chroot "$CHROOT_DIR" /bin/bash -c "locale-gen de_DE.UTF-8 en_US.UTF-8"
  chroot "$CHROOT_DIR" /bin/bash -c "update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8"
  
  # Restliche Pakete identifizieren
  local include_list=$(IFS=,; echo "${INCLUDE_PACKAGES[*]}")
  local remaining_packages=$(echo "$include_list" | sed "s/$base_packages,//g")
  
  # Bereite chroot-Umgebung vor
  mkdir -p "$CHROOT_DIR/dev" "$CHROOT_DIR/dev/pts" "$CHROOT_DIR/proc" "$CHROOT_DIR/sys"
  mount -B /dev "$CHROOT_DIR/dev"
  mount -B /dev/pts "$CHROOT_DIR/dev/pts"
  mount -B /proc "$CHROOT_DIR/proc" 
  mount -B /sys "$CHROOT_DIR/sys"

  # Live-System-Umgebung auf bash forcieren
  chroot "$CHROOT_DIR" /bin/bash -c "ln -sf /bin/bash /bin/sh"
  
  # Erstelle ein temporäres Skript für die vollständige System-Konfiguration
  cat > "$CHROOT_DIR/system_setup.sh" << EOF
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

# Bash als Default-Shell forcieren
ln -sf /bin/bash /bin/sh
echo "Bash wurde als Standard-Shell forciert."

# GPG-Schlüssel einrichten
mkdir -p /etc/apt/keyrings/
cp /tmp/ubuntu-archive-keyring.gpg /etc/apt/keyrings/ubuntu-archive-keyring.gpg
cp /tmp/local-mirror.gpg /etc/apt/keyrings/local-mirror.gpg

# Nala Konfiguration erstellen
mkdir -p /etc/nala
cat > /etc/nala/nala.conf << EONALA
aptlist = false
auto_remove = true
auto_update = true
would_like_to_enable_nala_madness = false
update_all = false
update_reboot = false
plain = false
progress_bar = on
spinner = on
fancy_bar = true
throttle = 0
color = true
EONALA

# Berechtigungen setzen
chmod 644 /etc/nala/nala.conf

# System aktualisieren
nala update
nala full-upgrade -y

# Sprach- und Zeitzonen konfigurieren
locale-gen de_DE.UTF-8 en_US.UTF-8
update-locale LANG=de_DE.UTF-8

# Zeitzone setzen
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime

# Hostname setzen
echo "ubuntufde-live" > /etc/hostname
echo "127.0.1.1 ubuntufde-live" >> /etc/hosts

# Tastaturlayout einrichten
cat > /etc/default/keyboard << KEYBOARD_EOF
XKBMODEL="pc105"
XKBLAYOUT="de"
XKBVARIANT=""
XKBOPTIONS=""
KEYBOARD_EOF

# Benutzer und Passwörter erstellen
useradd -m -s /bin/bash ubuntufde
echo "ubuntufde:ubuntufde" | chpasswd
echo "root:toor" | chpasswd

# Netzwerk konfigurieren
cat > /etc/network/interfaces << INTERFACES_EOF
# The loopback network interface
auto lo
iface lo inet loopback

# Primary network interface - DHCP by default
auto eth0
iface eth0 inet dhcp
INTERFACES_EOF
EOF
  
  chmod +x "$CHROOT_DIR/system_setup.sh"
  
  # Führe das Skript im chroot aus
  chroot "$CHROOT_DIR" /system_setup.sh
  
  if [ $? -ne 0 ]; then
    log warn "Einige Konfigurationsschritte konnten nicht abgeschlossen werden. Fahre trotzdem fort."
  else
    log info "System erfolgreich konfiguriert und aktualisiert."
  fi
  
  # Entferne das temporäre Skript
  rm -f "$CHROOT_DIR/system_setup.sh"
}

# Netzwerkkonfigurations-Skript erstellen
create_network_setup() {
  log info "Erstelle Netzwerk-Setup-Skript..."
  
  mkdir -p "$CHROOT_DIR/opt/ubuntufde"
  
  cat > "$CHROOT_DIR/opt/ubuntufde/network_setup.sh" << 'EOF'
#!/bin/bash
# Netzwerk-Setup-Skript für UbuntuFDE
# Dieses Skript richtet die Netzwerkverbindung intelligent ein

# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Netzwerkschnittstellen ermitteln
get_network_interfaces() {
  local interfaces=()
  local i=0
  
  echo -e "${YELLOW}Verfügbare Netzwerkschnittstellen:${NC}"
  echo "--------------------------------------------"
  
  while read -r iface flags; do
    if [[ "$iface" != "lo:" && "$iface" != "lo" ]]; then
      # Interface-Name extrahieren
      local if_name=${iface%:}
      
      # IP-Adresse und Status ermitteln
      local ip_info=$(ip -o -4 addr show $if_name 2>/dev/null | awk '{print $4}')
      local status=$(ip -o link show $if_name | grep -o "state [A-Z]*" | cut -d' ' -f2)
      
      # MAC-Adresse ermitteln
      local mac=$(ip -o link show $if_name | awk '{print $17}')
      
      interfaces+=("$if_name")
      echo "$((i+1))) $if_name - Status: $status, IP: ${ip_info:-keine}, MAC: $mac"
      ((i++))
    fi
  done < <(ip -o link show | awk -F': ' '{print $2}')
  
  echo "--------------------------------------------"
  echo -e "${YELLOW}Wähle eine Schnittstelle (1-$i) oder ESC für zurück:${NC}"
  
  # Direktes Einlesen ohne Enter
  local choice
  read -n 1 -s choice
  
  # ESC-Taste abfangen (ASCII 27)
  if [[ $choice == $'\e' ]]; then
    return 255  # Spezialwert für "zurück"
  elif [[ $choice =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$i" ]; then
    echo "${interfaces[$((choice-1))]}"
    return 0
  else
    echo -e "${RED}Ungültige Auswahl${NC}"
    sleep 1
    return 1
  fi
}

# Test ob Internetverbindung besteht
check_internet() {
  if ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Versuche NetworkManager für eine Schnittstelle
try_networkmanager() {
  echo -e "${GREEN}[INFO]${NC} Versuche NetworkManager für automatische Konfiguration..."
  
  # Prüfen, ob NetworkManager läuft
  if ! systemctl is-active NetworkManager >/dev/null 2>&1; then
    systemctl start NetworkManager || service network-manager start
    sleep 3
  fi
  
  # Warte auf automatische Verbindung
  for i in {1..3}; do
    if check_internet; then
      echo -e "${GREEN}[INFO]${NC} NetworkManager hat erfolgreich eine Verbindung hergestellt."
      return 0
    fi
    echo -e "${GREEN}[INFO]${NC} Warte auf NetworkManager Verbindung... ($i/3)"
    sleep 2
  done
  
  echo -e "${YELLOW}[WARN]${NC} NetworkManager konnte keine automatische Verbindung herstellen."
  return 1
}

# Versuche DHCP für eine Schnittstelle
try_dhcp() {
  local iface=$1
  echo -e "${GREEN}[INFO]${NC} Versuche DHCP auf Schnittstelle $iface..."
  
  # Alte IP-Konfiguration und Leases entfernen
  ip addr flush dev "$iface"
  rm -f /var/lib/dhcp/dhclient."$iface".leases 2>/dev/null
  rm -f /var/lib/dhcpcd/"$iface".lease 2>/dev/null
  
  # Interface aktivieren
  ip link set $iface up
  sleep 1
  
  # Bessere Fehlerbehandlung für dhclient
  if command -v dhclient >/dev/null 2>&1; then
    # Versuche dhclient mit Timeout
    timeout 10s dhclient -v -1 $iface || true
  elif command -v dhcpcd >/dev/null 2>&1; then
    # Versuche dhcpcd mit Timeout
    timeout 10s dhcpcd -t 5 $iface || true
  else
    # Fallback: Versuche ip mit DHCP
    echo -e "${YELLOW}[WARN]${NC} Kein DHCP-Client gefunden, versuche direktes ip-DHCP..."
    ip address add 0.0.0.0/0 dev $iface
    timeout 5s ip dhcp client -v start $iface || true
  fi
  
  # Warte kurz und prüfe die Verbindung
  sleep 2
  
  if check_internet; then
    echo -e "${GREEN}[INFO]${NC} DHCP erfolgreich für $iface, Internetverbindung hergestellt."
    return 0
  else
    echo -e "${YELLOW}[WARN]${NC} DHCP für $iface war nicht erfolgreich."
    return 1
  fi
}

# Intelligenter Scan für Netzwerkparameter
scan_network_for_settings() {
  local iface=$1
  echo -e "${GREEN}[INFO]${NC} Führe intelligenten Netzwerkscan für $iface durch..."
  
  # Aktiviere die Schnittstelle
  ip link set $iface up
  sleep 1
  
  # Versuche, Netzwerkinformationen durch passive Überwachung zu erhalten
  # Starte tcpdump im Hintergrund und fange Pakete für 10 Sekunden ab
  if command -v tcpdump >/dev/null 2>&1; then
    echo -e "${GREEN}[INFO]${NC} Überwache Netzwerkverkehr für potenzielle Konfiguration..."
    tcpdump -i $iface -n -v -c 30 2>/dev/null | tee /tmp/tcpdump_output &
    tcpdump_pid=$!
    
    # Warte bis zu 10 Sekunden
    for i in {1..10}; do
      sleep 1
      
      # Überprüfe, ob tcpdump noch läuft
      if ! kill -0 $tcpdump_pid 2>/dev/null; then
        break
      fi
    done
    
    # Töte tcpdump, falls es noch läuft
    kill $tcpdump_pid 2>/dev/null || true
    
    # Versuche, Gateway und Netzmaske zu extrahieren
    potential_gateways=$(grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" /tmp/tcpdump_output | sort | uniq -c | sort -nr | head -5)
    
    # Wenn wir potenzielle Gateways haben, versuche die häufigste IP
    if [ -n "$potential_gateways" ]; then
      gateway=$(echo "$potential_gateways" | head -1 | awk '{print $2}')
      
      # Bestimme den Netzwerkpräfix (erste 3 Oktette)
      network_prefix=$(echo $gateway | cut -d. -f1-3)
      
      # Generiere eine freie IP-Adresse im selben Netzwerk
      for i in {100..200}; do
        potential_ip="${network_prefix}.$i"
        
        # Überprüfe, ob diese IP bereits verwendet wird
        if ! ping -c 1 -W 1 $potential_ip >/dev/null 2>&1; then
          # Diese IP ist wahrscheinlich frei
          echo -e "${GREEN}[INFO]${NC} Potenzielle freie IP gefunden: $potential_ip"
          
          # Konfiguriere mit dieser IP
          ip addr add "${potential_ip}/24" dev $iface
          ip route add default via $gateway dev $iface
          echo "nameserver 8.8.8.8" > /etc/resolv.conf
          echo "nameserver 1.1.1.1" >> /etc/resolv.conf
          
          # Überprüfe, ob wir jetzt eine Verbindung haben
          if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            echo -e "${GREEN}[INFO]${NC} Intelligente Konfiguration erfolgreich!"
            return 0
          else
            # Entferne die Konfiguration wieder
            ip addr del "${potential_ip}/24" dev $iface
          fi
        fi
      done
    fi
  fi
  
  echo -e "${YELLOW}[WARN]${NC} Intelligenter Scan konnte keine passende Konfiguration finden."
  return 1
}

# Hauptfunktion
setup_network() {
  echo -e "${GREEN}[INFO]${NC} Starte Netzwerkkonfiguration..."

  # Prüfe zuerst, ob bereits Internet vorhanden ist
  echo -e "${GREEN}[INFO]${NC} Prüfe ob bereits Internetverbindung besteht..."
  if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
    echo -e "${GREEN}[INFO]${NC} Internetverbindung bereits vorhanden, keine Konfiguration nötig!"
    return 0
  fi
  
  # Versuche erst NetworkManager
  if command -v nmcli >/dev/null 2>&1; then
    if try_networkmanager; then
      return 0
    fi
  fi
  
  # Scannen aller Schnittstellen
  local interfaces=()
  while read -r iface _; do
    if [[ "$iface" != "lo" && "$iface" != "lo:"* ]]; then
      interfaces+=("${iface%:}")
    fi
  done < <(ip -o link show | awk -F': ' '{print $2}')
  
  if [ ${#interfaces[@]} -eq 0 ]; then
    echo -e "${RED}[ERROR]${NC} Keine Netzwerkschnittstellen gefunden."
    return 1
  fi
  
  # Versuche DHCP auf allen Schnittstellen
  for iface in "${interfaces[@]}"; do
    echo -e "${GREEN}[INFO]${NC} Versuche automatisches DHCP auf $iface..."
    if try_dhcp "$iface"; then
      return 0
    fi
  done
  
  echo -e "${YELLOW}[WARN]${NC} Automatische Netzwerkkonfiguration fehlgeschlagen. Bitte manuell konfigurieren."
  return 1
}

# Führe die Netzwerkkonfiguration durch
setup_network
EOF
  
  chmod +x "$CHROOT_DIR/opt/ubuntufde/network_setup.sh"
  
  log info "Netzwerk-Setup-Skript erstellt."
}

# Hauptinstallationsskript erstellen
create_main_script() {
  log info "Erstelle Autostartskript..."
  cat > "$CHROOT_DIR/opt/ubuntufde/start_environment.sh" << EOSTART
#!/bin/bash
# UbuntuFDE Umgebung
# Dieses Skript startet die UbuntuFDE Umgebung

# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Standardwerte
INSTALLATION_URL="${INSTALLATION_URL}"
SELECTED_LANGUAGE="de_DE.UTF-8"
SELECTED_KEYBOARD="de"

# Sprachauswahl-Dialog
select_language() {
  clear
  echo -e "${CYAN}=======================================${NC}"
  echo -e "${CYAN}       UbuntuFDE Umgebung              ${NC}"
  echo -e "${CYAN}=======================================${NC}"
  echo
  echo -e "${YELLOW}Bitte wähle die Anzeigesprache / Please select display language:${NC}"
  echo
  echo "1) Deutsch (Standard)"
  echo "2) English"
  echo
  echo -n "Auswahl/Choice [1]: "
  read -n 1 lang_choice
  echo
  
  case ${lang_choice:-1} in
    1|""|"Deutsch"|"deutsch")
      SELECTED_LANGUAGE="de_DE.UTF-8"
      echo -e "${GREEN}Deutsch ausgewählt${NC}"
      ;;
    2|"English"|"english")
      SELECTED_LANGUAGE="en_US.UTF-8"
      echo -e "${GREEN}English selected${NC}"
      ;;
    *)
      SELECTED_LANGUAGE="de_DE.UTF-8"
      echo -e "${YELLOW}Unbekannte Auswahl, Deutsch wird verwendet${NC}"
      ;;
  esac
  
  # Sprache temporär setzen
  export LANG=$SELECTED_LANGUAGE
  sleep 1
}

# Tastaturlayout-Auswahl
select_keyboard() {
  clear
  echo -e "${CYAN}=======================================${NC}"
  echo -e "${CYAN}       UbuntuFDE Umgebung              ${NC}"
  echo -e "${CYAN}=======================================${NC}"
  echo
  
  if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
    echo -e "${YELLOW}Bitte wähle dein Tastaturlayout:${NC}"
    echo
    echo "1) Deutsch - Deutschland (Standard)"
    echo "2) Deutsch - Schweiz"
    echo "3) Deutsch - Österreich"
    echo "4) Englisch - US"
    echo
    echo -n "Auswahl [1]: "
    read -n 1 kb_choice
    echo
    
    case ${kb_choice:-1} in
      1|"")
        SELECTED_KEYBOARD="de"
        echo -e "${GREEN}Tastaturlayout: Deutsch (Deutschland)${NC}"
        ;;
      2)
        SELECTED_KEYBOARD="ch"
        echo -e "${GREEN}Tastaturlayout: Deutsch (Schweiz)${NC}"
        ;;
      3)
        SELECTED_KEYBOARD="at"
        echo -e "${GREEN}Tastaturlayout: Deutsch (Österreich)${NC}"
        ;;
      4)
        SELECTED_KEYBOARD="us"
        echo -e "${GREEN}Tastaturlayout: Englisch (US)${NC}"
        ;;
      *)
        SELECTED_KEYBOARD="de"
        echo -e "${YELLOW}Unbekannte Auswahl, Deutsch (Deutschland) wird verwendet${NC}"
        ;;
    esac
  else
    echo -e "${YELLOW}Please select your keyboard layout:${NC}"
    echo
    echo "1) English - US (Default)"
    echo "2) German - Germany" 
    echo "3) German - Switzerland"
    echo "4) German - Austria"
    echo
    echo -n "Selection [1]: "
    read -n 1 kb_choice
    echo
    
    case ${kb_choice:-1} in
      1|"")
        SELECTED_KEYBOARD="us"
        echo -e "${GREEN}Keyboard layout: English (US)${NC}"
        ;;
      2)
        SELECTED_KEYBOARD="de"
        echo -e "${GREEN}Keyboard layout: German (Germany)${NC}"
        ;;
      3)
        SELECTED_KEYBOARD="ch"
        echo -e "${GREEN}Keyboard layout: German (Switzerland)${NC}"
        ;;
      4)
        SELECTED_KEYBOARD="at"
        echo -e "${GREEN}Keyboard layout: German (Austria)${NC}"
        ;;
      *)
        SELECTED_KEYBOARD="us"
        echo -e "${YELLOW}Unknown selection, using English (US)${NC}"
        ;;
    esac
  fi
  
  # Tastaturlayout sofort aktivieren
  loadkeys ${SELECTED_KEYBOARD} 2>/dev/null
  sleep 1
}

# Netzwerkverbindungseinrichtung
setup_network() {
  local return_to_menu=0
  
  while [ $return_to_menu -eq 0 ]; do
    clear
    echo -e "${CYAN}=======================================${NC}"
    echo -e "${CYAN}       UbuntuFDE Umgebung              ${NC}"
    echo -e "${CYAN}=======================================${NC}"
    echo
    
    if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
      echo -e "${YELLOW}Netzwerkverbindung einrichten:${NC}"
      echo "1) Automatische Konfiguration versuchen (DHCP)"
      echo "2) Manuell konfigurieren"
      echo
      echo -n "Auswahl [1]: "
    else
      echo -e "${YELLOW}Configure network connection:${NC}"
      echo "1) Try automatic configuration (DHCP)"
      echo "2) Configure manually"
      echo
      echo -n "Selection [1]: "
    fi
    
    read -n 1 config_method
    echo
    
    case ${config_method:-1} in
      2)
        # Manuelle Konfiguration
        manual_network_setup
        local manual_result=$?
        
        # Wenn ESC gedrückt wurde (manual_result=1), zurück zum Menü
        if [ $manual_result -eq 1 ]; then
          continue  # Zurück zum Anfang der Schleife
        elif [ $manual_result -eq 0 ]; then
          # Erfolgreiche Konfiguration
          return 0
        else
          # Fehlerfall
          if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
            echo -e "${YELLOW}Netzwerkkonfiguration unvollständig.${NC}"
            echo -e "${YELLOW}Möchtest du es erneut versuchen? (j/n) [j]:${NC}"
          else
            echo -e "${YELLOW}Network configuration incomplete.${NC}"
            echo -e "${YELLOW}Would you like to try again? (y/n) [y]:${NC}"
          fi
          read -n 1 retry
          echo
          
          case ${retry:-j} in
            j|J|y|Y|"")
              continue  # Zurück zum Menü
              ;;
            *)
              # Trotz Absage wieder zurück zum Menü
              if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
                echo -e "${RED}Ohne Netzwerkverbindung ist diese ISO-Umgebung nicht funktionsfähig.${NC}"
                echo -e "${YELLOW}Kehre zum Netzwerkmenü zurück...${NC}"
              else
                echo -e "${RED}Without network connection, this ISO environment is not functional.${NC}"
                echo -e "${YELLOW}Returning to network menu...${NC}"
              fi
              sleep 2
              continue  # Zurück zum Menü statt Beenden
              ;;
          esac
        fi
        ;;
      *)
        # Automatische Konfiguration
        if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
          echo -e "${YELLOW}Richte Netzwerkverbindung ein...${NC}"
        else
          echo -e "${YELLOW}Setting up network connection...${NC}"
        fi
        echo
        
        # Führe das Netzwerk-Setup-Skript aus
        bash /opt/ubuntufde/network_setup.sh
        NETWORK_SETUP_RESULT=$?
        
        # Überprüfe, ob die Netzwerkverbindung hergestellt wurde
        if [ $NETWORK_SETUP_RESULT -ne 0 ] || ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
          if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
            echo -e "${RED}Automatische Netzwerkkonfiguration fehlgeschlagen.${NC}"
            echo -e "${YELLOW}Möchtest du das Netzwerk manuell konfigurieren?${NC}"
            echo -n "Manuelle Konfiguration starten? (j/n) [j]: "
            read -n 1 manual_config
            echo
          else
            echo -e "${RED}Automatic network configuration failed.${NC}"
            echo -e "${YELLOW}Would you like to configure the network manually?${NC}"
            read -p "Start manual configuration? (y/n) [y]: " manual_config
          fi
          
          case ${manual_config:-j} in
            j|J|y|Y|"")
              manual_network_setup
              local manual_result=$?
              
              # Wenn ESC gedrückt wurde, zurück zum Menü
              if [ $manual_result -eq 1 ]; then
                continue  # Zurück zum Anfang der Schleife
              elif [ $manual_result -eq 0 ]; then
                # Erfolgreiche Konfiguration
                return 0
              else
                # Fehlerfall - trotzdem zum Menü zurückkehren
                if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
                  echo -e "${YELLOW}Netzwerkkonfiguration nicht abgeschlossen.${NC}"
                  echo -e "${YELLOW}Kehre zum Netzwerkmenü zurück...${NC}"
                else
                  echo -e "${YELLOW}Network configuration not completed.${NC}"
                  echo -e "${YELLOW}Returning to network menu...${NC}"
                fi
                sleep 2
                continue  # Zurück zum Menü, nie beenden
              fi
              ;;
            *)
              # Benutzer hat "n" gewählt - Erklärung und erneute Chance bieten
              if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
                echo -e "${RED}Achtung: Ohne Netzwerkverbindung kann UbuntuFDE nicht heruntergeladen werden.${NC}"
                echo -e "${YELLOW}Möchtest du zur Netzwerkauswahl zurückkehren? (j/n) [j]: ${NC}"
              else
                echo -e "${RED}Warning: Without network connection, UbuntuFDE cannot be downloaded.${NC}"
                echo -e "${YELLOW}Would you like to return to the network selection? (y/n) [y]: ${NC}"
              fi
              read -n 1 return_choice
              echo
              
              case ${return_choice:-j} in
                j|J|y|Y|"")
                  continue  # Zurück zum Menü
                  ;;
                *)
                  # Selbst bei endgültiger Ablehnung noch eine letzte Chance geben
                  if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
                    echo -e "${RED}Ohne Netzwerkverbindung ist diese ISO-Umgebung nicht funktionsfähig.${NC}"
                    echo -e "${YELLOW}Drücke eine beliebige Taste, um zum Netzwerkmenü zurückzukehren...${NC}"
                  else
                    echo -e "${RED}Without network connection, this ISO environment cannot function.${NC}"
                    echo -e "${YELLOW}Press any key to return to the network menu...${NC}"
                  fi
                  read -n 1
                  continue  # Immer zurück zum Menü, nie beenden
                  ;;
              esac
              ;;
          esac
        else
          # Netzwerk erfolgreich konfiguriert
          return 0
        fi
        ;;
    esac
    
    # Schleife beenden, wenn wir hierher gelangen
    return_to_menu=1
  done
}

# Manuelle Netzwerkkonfiguration
manual_network_setup() {
  # Hauptschleife für die gesamte manuelle Konfiguration
  while true; do
    clear
    echo -e "${CYAN}=======================================${NC}"
    echo -e "${CYAN}     UbuntuFDE Netzwerkkonfiguration   ${NC}"
    echo -e "${CYAN}=======================================${NC}"
    echo
    
    if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
      echo -e "${YELLOW}Verfügbare Netzwerkschnittstellen:${NC}"
    else
      echo -e "${YELLOW}Available network interfaces:${NC}"
    fi
    echo "--------------------------------------------"
    
    local interfaces=()
    local i=0
    
    # Alle Netzwerkschnittstellen ermitteln (außer lo)
    while read -r iface _; do
      if [[ "$iface" != "lo" && "$iface" != "lo:"* ]]; then
        # Interface-Name extrahieren
        local if_name=${iface%:}
        
        # IP-Adresse und Status ermitteln
        local ip_info=$(ip -o -4 addr show $if_name 2>/dev/null | awk '{print $4}')
        if [ -z "$ip_info" ]; then ip_info="keine"; fi
        
        local status=$(ip -o link show $if_name | grep -o "state [A-Z]*" | cut -d' ' -f2)
        
        # MAC-Adresse ermitteln
        local mac=$(ip link show $if_name | grep -o 'link/ether [^ ]*' | cut -d' ' -f2)
        if [ -z "$mac" ]; then mac="unbekannt"; fi
        
        interfaces+=("$if_name")
        
        # Zeige erweiterte Informationen
        if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
          echo "$((i+1))) $if_name - Status: $status, IP: $ip_info, MAC: $mac"
        else
          echo "$((i+1))) $if_name - Status: $status, IP: $ip_info, MAC: $mac"
        fi
        ((i++))
      fi
    done < <(ip -o link show | awk -F': ' '{print $2}')
    
    if [ "${#interfaces[@]}" -eq 0 ]; then
      if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
        echo -e "${RED}Keine Netzwerkschnittstellen gefunden!${NC}"
      else
        echo -e "${RED}No network interfaces found!${NC}"
      fi
      sleep 3
      return 1
    fi
    
    echo "--------------------------------------------"
    if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
      echo -e "${YELLOW}Wähle eine Schnittstelle (1-$i) oder ESC für zurück:${NC}"
    else
      echo -e "${YELLOW}Select an interface (1-$i) or ESC to go back:${NC}"
    fi
    
    # Direktes Einlesen ohne Enter
    local iface_choice
    read -n 1 -s iface_choice
    echo
    
    # ESC-Taste abfangen
    if [[ $iface_choice == $'\e' ]]; then
      if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
        echo -e "${YELLOW}Zurück zum Hauptmenü...${NC}"
      else
        echo -e "${YELLOW}Back to main menu...${NC}"
      fi
      return 1
    fi
    
    # Überprüfe, ob die Eingabe gültig ist
    if ! [[ "$iface_choice" =~ ^[0-9]+$ ]] || [ "$iface_choice" -lt 1 ] || [ "$iface_choice" -gt "${#interfaces[@]}" ]; then
      if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
        echo -e "${RED}Ungültige Auswahl. Bitte erneut versuchen.${NC}"
      else
        echo -e "${RED}Invalid selection. Please try again.${NC}"
      fi
      sleep 1
      continue
    fi
    
    local selected_iface="${interfaces[$((iface_choice-1))]}"
    
    # Schnittstelle aktivieren
    echo
    if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
      echo -e "${GREEN}Schnittstelle ${selected_iface} ausgewählt.${NC}"
    else
      echo -e "${GREEN}Interface ${selected_iface} selected.${NC}"
    fi
    
    # Aktiviere die Schnittstelle, falls sie nicht bereits aktiv ist
    ip link set "$selected_iface" up
    sleep 1
    
    # Unterschleife für Konfigurationsoptionen
    while true; do
      clear
      echo -e "${CYAN}=======================================${NC}"
      echo -e "${CYAN}     UbuntuFDE Netzwerkkonfiguration   ${NC}"
      echo -e "${CYAN}=======================================${NC}"
      echo
      
      if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
        echo -e "${GREEN}Schnittstelle: ${selected_iface}${NC}"
        echo
        echo -e "${YELLOW}Konfigurationsoptionen:${NC}"
        echo "1) DHCP (automatische IP-Konfiguration)"
        echo "2) Statische IP-Konfiguration"
        echo
        echo -e "${YELLOW}Wähle eine Option (1-2) oder ESC für zurück:${NC}"
      else
        echo -e "${GREEN}Interface: ${selected_iface}${NC}"
        echo
        echo -e "${YELLOW}Configuration options:${NC}"
        echo "1) DHCP (automatic IP configuration)"
        echo "2) Static IP configuration"
        echo
        echo -e "${YELLOW}Select an option (1-3) or ESC to go back:${NC}"
      fi
      
      # Direktes Einlesen ohne Enter
      local config_choice
      read -n 1 -s config_choice
      echo
      
      # ESC-Taste abfangen
      if [[ $config_choice == $'\e' ]]; then
        break
      fi
      
      case $config_choice in
        1) # DHCP
          if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
            echo -e "${YELLOW}Prüfe bestehende Internetverbindung...${NC}"
          else
            echo -e "${YELLOW}Checking existing internet connection...${NC}"
          fi
          
          # Zuerst prüfen, ob bereits eine Internetverbindung besteht
          if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
            if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
              echo -e "${GREEN}Internetverbindung bereits vorhanden!${NC}"
              echo -e "${GREEN}Keine DHCP-Konfiguration notwendig.${NC}"
            else
              echo -e "${GREEN}Internet connection already exists!${NC}"
              echo -e "${GREEN}No DHCP configuration necessary.${NC}"
            fi
            sleep 2
            return 0
          else
            # Nur wenn keine Verbindung besteht, DHCP konfigurieren
            if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
              echo -e "${YELLOW}Versuche DHCP-Konfiguration für ${selected_iface}...${NC}"
            else
              echo -e "${YELLOW}Trying DHCP configuration for ${selected_iface}...${NC}"
            fi
            
            # Alte IP-Konfiguration entfernen
            ip addr flush dev "$selected_iface"
            
            # DHCP starten (verbesserte Version)
            if command -v dhclient >/dev/null 2>&1; then
              # Beende vorherige Prozesse
              pkill -f "dhclient.*$selected_iface" 2>/dev/null || true
              sleep 1
              # Starte mit Timeout
              timeout 15s dhclient -v -1 "$selected_iface" || true
            elif command -v dhcpcd >/dev/null 2>&1; then
              # Beende vorherige dhcpcd-Prozesse
              pkill -f "dhcpcd.*$selected_iface" 2>/dev/null || true
              sleep 1
              # Starte mit Timeout
              timeout 15s dhcpcd -t 5 "$selected_iface" || true
            else
              # Alternative: IP direkt konfigurieren
              if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
                echo -e "${YELLOW}Kein DHCP-Client gefunden, versuche Fallback-Methode...${NC}"
              else
                echo -e "${YELLOW}No DHCP client found, trying fallback method...${NC}"
              fi
              ip address add 0.0.0.0/0 dev "$selected_iface" 2>/dev/null
              ip link set "$selected_iface" up
            fi
            
            # Warte kurz und prüfe die Verbindung
            sleep 3
            
            if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
              if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
                echo -e "${GREEN}DHCP erfolgreich für $selected_iface, Internetverbindung hergestellt.${NC}"
              else
                echo -e "${GREEN}DHCP successful for $selected_iface, Internet connection established.${NC}"
              fi
              sleep 2
              return 0
            else
              if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
                echo -e "${RED}DHCP für $selected_iface war nicht erfolgreich.${NC}"
                echo -e "${YELLOW}Drücke eine Taste, um fortzufahren...${NC}"
              else
                echo -e "${RED}DHCP for $selected_iface was not successful.${NC}"
                echo -e "${YELLOW}Press any key to continue...${NC}"
              fi
              read -n 1 -s
            fi
          fi
          ;;
          
        2) # Statische IP
          # Unterschleife für statische IP-Konfiguration
          while true; do
            clear
            echo -e "${CYAN}=======================================${NC}"
            echo -e "${CYAN}   Statische IP-Konfiguration für ${selected_iface}   ${NC}"
            echo -e "${CYAN}=======================================${NC}"
            echo
            
            if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
              echo -e "${YELLOW}Bitte gib die statischen Netzwerkparameter ein:${NC}"
              echo -e "${YELLOW}(Drücke ESC während der Eingabe, um zur vorherigen Seite zurückzukehren)${NC}"
              echo
              
              # Verwende read -e für bearbeitbare Eingabe
              read -p "IP-Adresse (z.B. 192.168.1.100): " -e ip_addr
              
              # Prüfe auf ESC
              if [[ $? -eq 1 ]]; then
                break
              fi
              
              read -p "Netzmaske (z.B. 24 für /24): " -e netmask
              if [[ $? -eq 1 ]]; then
                break
              fi
              
              read -p "Gateway (z.B. 192.168.1.1): " -e gateway
              if [[ $? -eq 1 ]]; then
                break
              fi
              
              read -p "DNS-Server (z.B. 8.8.8.8): " -e dns
              if [[ $? -eq 1 ]]; then
                break
              fi
            else
              echo -e "${YELLOW}Please enter the static network parameters:${NC}"
              echo -e "${YELLOW}(Press ESC during input to return to the previous page)${NC}"
              echo
              
              read -p "IP address (e.g. 192.168.1.100): " -e ip_addr
              if [[ $? -eq 1 ]]; then
                break
              fi
              
              read -p "Netmask (e.g. 24 for /24): " -e netmask
              if [[ $? -eq 1 ]]; then
                break
              fi
              
              read -p "Gateway (e.g. 192.168.1.1): " -e gateway
              if [[ $? -eq 1 ]]; then
                break
              fi
              
              read -p "DNS server (e.g. 8.8.8.8): " -e dns
              if [[ $? -eq 1 ]]; then
                break
              fi
            fi
            
            # Überprüfe, ob alle erforderlichen Parameter eingegeben wurden
            if [ -z "$ip_addr" ] || [ -z "$netmask" ] || [ -z "$gateway" ] || [ -z "$dns" ]; then
              if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
                echo -e "${RED}Unvollständige Netzwerkparameter. Bitte erneut versuchen.${NC}"
              else
                echo -e "${RED}Incomplete network parameters. Please try again.${NC}"
              fi
              sleep 2
              continue
            fi
            
            # Alte IP-Konfiguration entfernen
            ip addr flush dev "$selected_iface"
            
            # Konfiguriere die Netzwerkschnittstelle
            ip link set "$selected_iface" up
            ip addr add "$ip_addr/$netmask" dev "$selected_iface"
            ip route add default via "$gateway" dev "$selected_iface"
            
            # DNS-Server konfigurieren
            echo "nameserver $dns" > /etc/resolv.conf
            
            # Überprüfe die Verbindung
            if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
              if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
                echo -e "${GREEN}Netzwerkverbindung erfolgreich hergestellt.${NC}"
              else
                echo -e "${GREEN}Network connection successfully established.${NC}"
              fi
              sleep 2
              return 0
            else
              if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
                echo -e "${RED}Netzwerkverbindung fehlgeschlagen.${NC}"
                echo -e "${YELLOW}Möchtest du es erneut versuchen? (j/n)${NC}"
              else
                echo -e "${RED}Network connection failed.${NC}"
                echo -e "${YELLOW}Would you like to try again? (y/n)${NC}"
              fi
              
              read -n 1 -s retry
              echo
              
              if [[ "$retry" != "j" && "$retry" != "J" && "$retry" != "y" && "$retry" != "Y" ]]; then
                break
              fi
            fi
          done
          ;;
          
        *)
          if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
            echo -e "${RED}Ungültige Auswahl. Bitte erneut versuchen.${NC}"
          else
            echo -e "${RED}Invalid selection. Please try again.${NC}"
          fi
          sleep 1
          ;;
      esac
    done
  done
}


# UbuntuFDE herunterladen und ausführen
download_and_run() {
  if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
    echo -e "${YELLOW}Lade UbuntuFDE herunter...${NC}"
  else
    echo -e "${YELLOW}Downloading UbuntuFDE script...${NC}"
  fi
  
  # Speichere die ausgewählten Einstellungen in einer temporären Datei
  echo "SELECTED_LANGUAGE=\"$SELECTED_LANGUAGE\"" > /tmp/install_settings.conf
  echo "SELECTED_KEYBOARD=\"$SELECTED_KEYBOARD\"" >> /tmp/install_settings.conf
  
  # Lade das Skript herunter
  if wget -O /tmp/UbuntuFDE.sh "$INSTALLATION_URL"; then
    chmod +x /tmp/UbuntuFDE.sh
    
    if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
      echo -e "${GREEN}Starte UbuntuFDE...${NC}"
    else
      echo -e "${GREEN}Starting UbuntuFDE...${NC}"
    fi
    
    # Führe das Skript mit den gewählten Einstellungen aus
    /tmp/UbuntuFDE.sh --language="$SELECTED_LANGUAGE" --keyboard="$SELECTED_KEYBOARD"
  else
    if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
      echo -e "${RED}Download fehlgeschlagen. Versuche Netzwerk neu einzurichten...${NC}"
    else
      echo -e "${RED}Download failed. Trying to reconfigure network...${NC}"
    fi
    sleep 3
    setup_network
    download_and_run
  fi
}

# Hauptablauf
main() {
  # Sprache und Tastatur wählen
  select_language
  select_keyboard
  
  # Internetverbindung prüfen
  if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
    echo -e "${YELLOW}Prüfe Internetverbindung...${NC}"
  else
    echo -e "${YELLOW}Checking internet connection...${NC}"
  fi
  
  # Test auf bestehende Verbindung
  if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 || ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
    if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
      echo -e "${GREEN}Internetverbindung gefunden!${NC}"
      echo -e "${YELLOW}Fahre mit Download fort...${NC}"
    else
      echo -e "${GREEN}Internet connection found!${NC}"
      echo -e "${YELLOW}Proceeding with download...${NC}"
    fi
    sleep 1
    # Download und Start der UbuntuFDE Umgebung
    download_and_run
  else
    # Keine Verbindung gefunden, Netzwerkkonfiguration starten
    if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
      echo -e "${YELLOW}Keine Internetverbindung gefunden.${NC}"
      echo -e "${YELLOW}Netzwerkkonfiguration wird gestartet...${NC}"
    else
      echo -e "${YELLOW}No internet connection found.${NC}"
      echo -e "${YELLOW}Starting network configuration...${NC}"
    fi
    sleep 1
    
    # Netzwerk einrichten
    setup_network
    NETWORK_RESULT=$?
    
    # Nur wenn Netzwerk konfiguriert wurde
    if [ $NETWORK_RESULT -eq 0 ]; then
      # UbuntuFDE ausführen
      download_and_run
    else
      if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
        echo -e "${YELLOW}Installation ohne Netzwerkverbindung nicht möglich.${NC}"
        echo -e "${YELLOW}Bitte später erneut versuchen.${NC}"
      else
        echo -e "${YELLOW}Installation without network connection not possible.${NC}"
        echo -e "${YELLOW}Please try again later.${NC}"
      fi
      sleep 3
    fi
  fi
}

# Starte den Hauptablauf
main
EOSTART
  
  chmod +x "$CHROOT_DIR/opt/ubuntufde/start_environment.sh"
  
  log info "Autostartskript erstellt."
}

# Autostart der Umgebung einrichten
create_autostart() {
  log info "Erstelle Autologin und Autostart..."
  
  # Getty-Service für automatische Anmeldung konfigurieren
  mkdir -p "$CHROOT_DIR/etc/systemd/system/getty@tty1.service.d/"
  cat > "$CHROOT_DIR/etc/systemd/system/getty@tty1.service.d/autologin.conf" << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ubuntufde --noclear %I \$TERM
EOF

  # Bash-Profil erstellen welches die Umgebung startet
  mkdir -p "$CHROOT_DIR/home/ubuntufde"
  cat > "$CHROOT_DIR/home/ubuntufde/.bash_profile" << EOF
# Wenn in VT1 eingeloggt, starte automatisch das Setup-Skript
if [ "\$(tty)" = "/dev/tty1" ]; then
  # Stelle sicher, dass bash als Standard-Shell verwendet wird
  sudo ln -sf /bin/bash /bin/sh
  echo "Bash wurde als Standard-Shell forciert."
  bash /opt/ubuntufde/start_environment.sh
  # Wenn das Skript beendet wird, bleibst Du in der Shell
  echo "start_environment.sh wurde beendet. Drücke Enter für eine Shell."
  read
fi
EOF

  # rc.local für frühen Systemstart einrichten
  log info "Richte rc.local für bash als Standardshell ein..."
  mkdir -p "$CHROOT_DIR/etc"
  cat > "$CHROOT_DIR/etc/rc.local" << 'EOF'
#!/bin/bash
# Stelle sicher, dass bash als Standard-Shell verwendet wird
ln -sf /bin/bash /bin/sh

# Weitere Startaufgaben könnten hier hinzugefügt werden...

exit 0
EOF

  chmod +x "$CHROOT_DIR/etc/rc.local"

  # Stelle sicher, dass rc.local beim Systemstart ausgeführt wird
  mkdir -p "$CHROOT_DIR/etc/systemd/system"
  cat > "$CHROOT_DIR/etc/systemd/system/rc-local.service" << EOF
[Unit]
Description=/etc/rc.local Compatibility
ConditionPathExists=/etc/rc.local

[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  # Service aktivieren
  mkdir -p "$CHROOT_DIR/etc/systemd/system/multi-user.target.wants"
  ln -sf /etc/systemd/system/rc-local.service "$CHROOT_DIR/etc/systemd/system/multi-user.target.wants/rc-local.service"

  # Berechtigungen definieren
  chroot "$CHROOT_DIR" chown -R ubuntufde:ubuntufde /home/ubuntufde
  chroot "$CHROOT_DIR" chmod 755 /home/ubuntufde/.bash_profile
  
  log info "Autologin und Autostart für Benutzer 'ubuntufde' konfiguriert."
}

# System bereinigen
cleanup_system() {
  log info "Bereinige System für kleinere ISO-Größe..."
  
  # Bereinigungsskript erstellen
  cat > "$CHROOT_DIR/cleanup.sh" << 'EOF'
#!/bin/bash
set -e

# Entferne unnötige Dokumentation
rm -rf /usr/share/doc/*
rm -rf /usr/share/man/*
rm -rf /usr/share/info/*

# Entferne alle Lokalisierungsdateien außer Deutsch und Englisch
mkdir -p /tmp/locales-backup/de_DE
mkdir -p /tmp/locales-backup/en_US

if [ -d /usr/share/locale/de_DE ]; then
  cp -r /usr/share/locale/de_DE/* /tmp/locales-backup/de_DE/
elif [ -d /usr/share/locale/de ]; then
  cp -r /usr/share/locale/de/* /tmp/locales-backup/de_DE/
fi

if [ -d /usr/share/locale/en_US ]; then
  cp -r /usr/share/locale/en_US/* /tmp/locales-backup/en_US/
elif [ -d /usr/share/locale/en ]; then
  cp -r /usr/share/locale/en/* /tmp/locales-backup/en_US/
fi

rm -rf /usr/share/locale/*

mkdir -p /usr/share/locale/de_DE
mkdir -p /usr/share/locale/de
mkdir -p /usr/share/locale/en_US
mkdir -p /usr/share/locale/en

if [ -d /tmp/locales-backup/de_DE ]; then
  cp -r /tmp/locales-backup/de_DE/* /usr/share/locale/de_DE/
  cp -r /tmp/locales-backup/de_DE/* /usr/share/locale/de/
fi

if [ -d /tmp/locales-backup/en_US ]; then
  cp -r /tmp/locales-backup/en_US/* /usr/share/locale/en_US/
  cp -r /tmp/locales-backup/en_US/* /usr/share/locale/en/
fi

rm -rf /tmp/locales-backup

# Bereinige APT Caches
nala clean
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/archives/*

# Entferne temporäre Dateien
rm -rf /var/tmp/*
rm -rf /tmp/*
rm -f /var/crash/*

# Entferne unnötige Kernel-Module
echo "System erfolgreich bereinigt."
EOF

  chmod +x "$CHROOT_DIR/cleanup.sh"
  chroot "$CHROOT_DIR" /cleanup.sh
  rm -f "$CHROOT_DIR/cleanup.sh"
  
  log info "System bereinigt."
}

# System für ISO vorbereiten
prepare_for_iso() {
  log info "Bereite System für ISO-Erstellung vor..."
  
  # Kernel und initrd finden
  KERNEL_VERSION=$(ls -1 "$CHROOT_DIR/boot/vmlinuz-"* 2>/dev/null | head -1 | sed "s|$CHROOT_DIR/boot/vmlinuz-||")
  
  if [ -z "$KERNEL_VERSION" ]; then
    log warn "Kein Kernel in /boot gefunden, installiere einen..."
    
    # Einhängen für chroot
    for dir in /dev /dev/pts /proc /sys; do
      mkdir -p "$CHROOT_DIR$dir"
      mount -B $dir "$CHROOT_DIR$dir"
    done
    
    # Neuen Kernel erkennen
    KERNEL_VERSION=$(ls -1 "$CHROOT_DIR/boot/vmlinuz-"* | head -1 | sed "s|$CHROOT_DIR/boot/vmlinuz-||")
    
    if [ -z "$KERNEL_VERSION" ]; then
      log error "Kein Kernel in /boot gefunden, obwohl linux-image-generic installiert wurde. Breche ab."
      exit 1
    fi
  fi
  
  log info "Verwende Kernel Version: $KERNEL_VERSION"
  
  # Kopiere Kernel für Boot
  mkdir -p "$ISO_DIR/casper"
  cp "$CHROOT_DIR/boot/vmlinuz-$KERNEL_VERSION" "$ISO_DIR/casper/vmlinuz"
  
  # Wenn die initrd fehlt, erstelle sie
  if [ ! -f "$CHROOT_DIR/boot/initrd.img-$KERNEL_VERSION" ]; then
    log warn "Keine initrd gefunden, erstelle eine neue..."
    chroot "$CHROOT_DIR" mkinitramfs -o "/boot/initrd.img-$KERNEL_VERSION" "$KERNEL_VERSION"
  fi
  
  # Kopiere die initrd
  cp "$CHROOT_DIR/boot/initrd.img-$KERNEL_VERSION" "$ISO_DIR/casper/initrd.img"
  
  # Verzeichnisse aushängen
  for dir in /dev/pts /dev /proc /sys; do
    umount "$CHROOT_DIR$dir" 2>/dev/null || true
  done
  
  # Erstelle squashfs vom chroot
  log info "Erstelle squashfs Dateisystem..."
  mksquashfs "$CHROOT_DIR" "$ISO_DIR/casper/filesystem.squashfs" -comp xz -wildcards -e "boot/*" "proc/*" "sys/*" "dev/*" "run/*" "tmp/*"
  
  # Erstelle Größendateien für casper
  du -B 1 -s "$CHROOT_DIR" | cut -f1 > "$ISO_DIR/casper/filesystem.size"
  
  # GRUB-Konfiguration erstellen
  cat > "$ISO_DIR/boot/grub/grub.cfg" << EOF
set default="0"
set timeout=1
set timeout_style=menu
set color_normal=white/black
set color_highlight=black/light-gray

menuentry "UbuntuFDE Installation" {
    set gfxpayload=keep
    linux /casper/vmlinuz boot=casper quiet splash ---
    initrd /casper/initrd.img
}

menuentry "UbuntuFDE Installation (Safe Graphics)" {
    set gfxpayload=keep
    linux /casper/vmlinuz boot=casper nomodeset quiet splash ---
    initrd /casper/initrd.img
}

menuentry "UbuntuFDE Installation (Konsole)" {
    set gfxpayload=keep
    linux /casper/vmlinuz boot=casper text ---
    initrd /casper/initrd.img
}
EOF

# EFI und BIOS Boot-Unterstützung
mkdir -p "$ISO_DIR/EFI/BOOT"
mkdir -p "$ISO_DIR/boot/grub/i386-pc"
mkdir -p "$ISO_DIR/boot/grub/x86_64-efi"

# Kopiere EFI-Bootdatei
if [ -f "$CHROOT_DIR/usr/lib/grub/x86_64-efi/grubx64.efi" ]; then
  cp "$CHROOT_DIR/usr/lib/grub/x86_64-efi/grubx64.efi" "$ISO_DIR/EFI/BOOT/BOOTx64.EFI"
  log info "EFI-Bootdateien erfolgreich kopiert"
else
  log warn "EFI-Bootdatei nicht gefunden. Grub-mkrescue wird versuchen, sie zu erstellen."
fi

# Kopiere GRUB-Module für bessere Kompatibilität
cp -r "$CHROOT_DIR/usr/lib/grub/i386-pc"/* "$ISO_DIR/boot/grub/i386-pc/" 2>/dev/null || true
cp -r "$CHROOT_DIR/usr/lib/grub/x86_64-efi"/* "$ISO_DIR/boot/grub/x86_64-efi/" 2>/dev/null || true

# Erstelle ISO-Metadaten
mkdir -p "$ISO_DIR/.disk"
echo "UbuntuFDE" > "$ISO_DIR/.disk/info"
echo "full_cd/single" > "$ISO_DIR/.disk/cd_type"
  
log info "System für ISO-Erstellung vorbereitet."
}

# ISO-Erstellung mit grub-mkrescue
create_iso_with_grub_mkrescue() {
  log info "Erstelle bootfähige ISO mit grub-mkrescue..."
  
  # Prüfe, ob die grub.cfg existiert
  if [ ! -f "$ISO_DIR/boot/grub/grub.cfg" ]; then
    log error "grub.cfg nicht gefunden in $ISO_DIR/boot/grub/. Breche ab."
    return 1
  fi
  
  # Stelle sicher, dass EFI und BIOS Boot-Verzeichnisse existieren
  mkdir -p "$ISO_DIR/boot/grub/i386-pc"
  mkdir -p "$ISO_DIR/boot/grub/x86_64-efi"
  
  # Nutze grub-mkrescue mit minimalen Optionen
  grub-mkrescue \
    --output="$OUTPUT_DIR/$ISO_NAME" \
    --verbose \
    "$ISO_DIR"
  
  if [ $? -ne 0 ]; then
    log error "ISO-Erstellung mit grub-mkrescue fehlgeschlagen."
    return 1
  fi
  
  log info "ISO erfolgreich erstellt: $OUTPUT_DIR/$ISO_NAME"
  log info "ISO-Größe: $(du -h "$OUTPUT_DIR/$ISO_NAME" | cut -f1)"
  return 0
}

# ISO mit xorriso erstellen
create_iso() {
  log info "Erstelle ISO-Image mit xorriso..."
  
  # ISO-Erstellung
  if command -v xorriso &> /dev/null; then
    log info "Erstelle bootfähige ISO mit vereinfachten Parametern..."
    xorriso -as mkisofs \
      -iso-level 3 \
      -full-iso9660-filenames \
      -volid "$ISO_TITLE" \
      -appid "$ISO_APPLICATION" \
      -publisher "$ISO_PUBLISHER" \
      -eltorito-boot boot/grub/bios.img \
      -no-emul-boot \
      -boot-load-size 4 \
      -boot-info-table \
      -eltorito-alt-boot \
      -e EFI/BOOT/BOOTx64.EFI \
      -no-emul-boot \
      -output "$OUTPUT_DIR/$ISO_NAME" \
      "$ISO_DIR"
  else

    log error "Kein Werkzeug zur ISO-Erstellung gefunden!"
    log info "Versuche minimale ISO mit dd zu erstellen..."
    
    # Erstelle eine leere Datei mit 1GB
    dd if=/dev/zero of="$OUTPUT_DIR/$ISO_NAME" bs=1M count=1000
    
    # Erstelle ein FAT32-Dateisystem
    mkfs.vfat "$OUTPUT_DIR/$ISO_NAME"
    
    # Erstelle temporäres Verzeichnis zum Einhängen
    mkdir -p /tmp/isomount
    
    # Hänge das Image ein
    mount -o loop "$OUTPUT_DIR/$ISO_NAME" /tmp/isomount
    
    # Kopiere die Dateien
    cp -r "$ISO_DIR"/* /tmp/isomount/
    
    # Hänge das Image aus
    umount /tmp/isomount
    
    # Entferne das temporäre Verzeichnis
    rmdir /tmp/isomount
  fi
  
  if [ $? -ne 0 ]; then
    log error "ISO-Erstellung fehlgeschlagen."
    exit 1
  fi
  
  log info "ISO erfolgreich erstellt: $OUTPUT_DIR/$ISO_NAME"
  log info "ISO-Größe: $(du -h "$OUTPUT_DIR/$ISO_NAME" | cut -f1)"
}

# Aufräumen
cleanup() {
  log info "Räume temporäre Dateien auf..."
  
  # Spezifische dev-Unterpfade aushängen
  for special_fs in "$CHROOT_DIR/dev/pts" "$CHROOT_DIR/dev/shm" "$CHROOT_DIR/dev/hugepages" "$CHROOT_DIR/dev/mqueue"; do
    if mountpoint -q "$special_fs" 2>/dev/null; then
      log info "Hänge $special_fs aus..."
      umount -l -f "$special_fs" 2>/dev/null || true
    fi
  done
  
  sleep 1
  
  # Hauptverzeichnisse in umgekehrter Reihenfolge aushängen
  for dir in /run /sys /proc /dev; do
    if mountpoint -q "$CHROOT_DIR$dir" 2>/dev/null; then
      log info "Hänge $CHROOT_DIR$dir aus..."
      umount -l -f "$CHROOT_DIR$dir" 2>/dev/null || true
    fi
  done
  
  sleep 1
  
  # Alle noch verbleibenden eingehängten Dateisysteme in chroot finden und aushängen
  mount | grep "$CHROOT_DIR" | awk '{print $3}' | sort -r | while read mountpoint; do
    log info "Hänge verbleibenden Mountpoint $mountpoint aus..."
    umount -l -f "$mountpoint" 2>/dev/null || true
  done
  
  sleep 2
  
  # Arbeitsverzeichnis löschen
  log info "Lösche temporäre Build-Dateien..."
  rm -rf "$WORK_DIR"
  log info "Temporäre Build-Dateien wurden gelöscht."
}
#  HAUPTFUNKTIONEN  #
#####################


###################
#  STARTFUNKTION  #
main() {
  echo -e "${BLUE}===== UbuntuFDE ISO-Erstellung =====${NC}"
  echo
  
  # Prüfe auf Root-Rechte und starte Skript bei Bedarf mit Sudo neu
  if [ "$(id -u)" -ne 0 ]; then
      echo "Dieses Skript benötigt Root-Rechte. Starte neu mit sudo..."
      sudo "$0" "$@"
      exit $?
  fi

  # Root-Rechte sind vorhanden
  echo "Skript wird mit Root-Rechten ausgeführt."
  
  # Schritte ausführen
  cleanup_previous_environment
  check_dependencies
  setup_directories
  create_base_system
  create_network_setup
  create_main_script
  create_autostart
  cleanup_system
  prepare_for_iso
  create_iso_with_grub_mkrescue
  # create_iso
  cleanup
  
  log info "UbuntuFDE ISO-Erstellung abgeschlossen!"
  log info "Die neue ISO befindet sich hier: $OUTPUT_DIR"
}
#  STARTFUNKTION  #
###################


# Starte das Hauptprogramm
main "$@"