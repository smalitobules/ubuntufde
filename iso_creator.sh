#!/bin/bash
# UbuntuFDE ISO-Erstellungsskript (Ubuntu-basiert)
# Dieses Skript erstellt eine minimale Ubuntu-basierte ISO für die UbuntuFDE-Installation
# Version: 0.1
# Es verwendet live-build, um eine angepasste Ubuntu-Live-ISO zu erstellen

# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Verzeichnisse
WORK_DIR="$(pwd)/ubuntufde_build"
BUILD_DIR="${WORK_DIR}/live-build"
CONFIG_DIR="${BUILD_DIR}/config"
CHROOT_HOOKS="${CONFIG_DIR}/hooks/live"
BINARY_HOOKS="${CONFIG_DIR}/hooks/binary"
PACKAGE_LISTS="${CONFIG_DIR}/package-lists"
INCLUDES_CHROOT="${CONFIG_DIR}/includes.chroot"
INCLUDES_BINARY="${CONFIG_DIR}/includes.binary"
OUTPUT_DIR="${WORK_DIR}/output"
LOG_FILE="${WORK_DIR}/build.log"

# ISO-Metadaten
ISO_TITLE="UbuntuFDE"
ISO_PUBLISHER="UbuntuFDE"
ISO_APPLICATION="UbuntuFDE Installation"
INSTALLATION_URL="https://indianfire.ch/fde"

# --------------------------------
# Hilfsfunktionen
# --------------------------------

# Logging-Funktion
log() {
  local level=$1
  shift
  local message="$@"
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  
  case $level in
    "info")
      echo -e "${GREEN}[INFO]${NC} $message"
      echo "[INFO] $timestamp - $message" >> "$LOG_FILE"
      ;;
    "warn")
      echo -e "${YELLOW}[WARN]${NC} $message"
      echo "[WARN] $timestamp - $message" >> "$LOG_FILE"
      ;;
    "error")
      echo -e "${RED}[ERROR]${NC} $message"
      echo "[ERROR] $timestamp - $message" >> "$LOG_FILE"
      ;;
    *)
      echo -e "${BLUE}[DEBUG]${NC} $message"
      echo "[DEBUG] $timestamp - $message" >> "$LOG_FILE"
      ;;
  esac
}

# Abhängigkeiten prüfen
check_dependencies() {
  log info "Prüfe Abhängigkeiten..."
  local commands=("lb" "debootstrap" "xorriso" "mksquashfs")
  local packages=("live-build" "debootstrap" "xorriso" "squashfs-tools")
  local missing_packages=()
  
  for i in "${!commands[@]}"; do
    if ! command -v "${commands[$i]}" &> /dev/null; then
      missing_packages+=("${packages[$i]}")
    fi
  done
  
  if [ ${#missing_packages[@]} -ne 0 ]; then
    log warn "Folgende Abhängigkeiten fehlen: ${missing_packages[*]}"
    log info "Installiere fehlende Abhängigkeiten..."
    nala update
    nala install -y "${missing_packages[@]}"
    
    # Erneut prüfen
    for i in "${!commands[@]}"; do
      if ! command -v "${commands[$i]}" &> /dev/null; then
        log error "Abhängigkeit konnte nicht installiert werden: ${packages[$i]}"
        exit 1
      fi
    done
  fi
  
  log info "Alle Abhängigkeiten sind installiert."
}

# Arbeitsverzeichnisse erstellen
setup_directories() {
  log info "Erstelle Arbeitsverzeichnisse..."

  # Cache leeren
  rm -rf "${BUILD_DIR}/cache"
  lb clean --purge
  rm -rf config
  
  mkdir -p "$WORK_DIR"
  mkdir -p "$BUILD_DIR"
  mkdir -p "$OUTPUT_DIR"
  mkdir -p "$CHROOT_HOOKS"
  mkdir -p "$BINARY_HOOKS"
  mkdir -p "$PACKAGE_LISTS"
  mkdir -p "$INCLUDES_CHROOT/etc/systemd/system"
  mkdir -p "$INCLUDES_CHROOT/opt/ubuntufde"
  
  # Logdatei initialisieren
  touch "$LOG_FILE"
  
  log info "Arbeitsverzeichnisse bereit."
}

# --------------------------------
# Hauptfunktionen
# --------------------------------

# Bootstrap modifizieren
customize_lb_bootstrap() {
  log info "Modifiziere lb_bootstrap für Kernel-Kopie..."
  
  # Den aktuellen Kernel-Namen ermitteln
  KERNEL_VERSION=$(uname -r)
  
  # Zielverzeichnis sicherstellen
  mkdir -p "${INCLUDES_CHROOT}/boot"
  
  # Kernel-Dateien kopieren
  if [ -f "/boot/vmlinuz-${KERNEL_VERSION}" ] && [ -f "/boot/initrd.img-${KERNEL_VERSION}" ]; then
    # Kopiere Kernel-Image mit exaktem Dateinamen
    cp "/boot/vmlinuz-${KERNEL_VERSION}" "${INCLUDES_CHROOT}/boot/vmlinuz-${KERNEL_VERSION}"
    cp "/boot/vmlinuz-${KERNEL_VERSION}" "${INCLUDES_CHROOT}/boot/vmlinuz"
    cp "/boot/vmlinuz-${KERNEL_VERSION}" "${INCLUDES_CHROOT}/boot/vmlinuz.old"
    
    # Kopiere Initialisierungs-RAM-Festplatte mit exaktem Dateinamen
    cp "/boot/initrd.img-${KERNEL_VERSION}" "${INCLUDES_CHROOT}/boot/initrd.img-${KERNEL_VERSION}"
    cp "/boot/initrd.img-${KERNEL_VERSION}" "${INCLUDES_CHROOT}/boot/initrd.img"
    cp "/boot/initrd.img-${KERNEL_VERSION}" "${INCLUDES_CHROOT}/boot/initrd.img.old"
    
    # Setze Berechtigungen
    chmod 644 "${INCLUDES_CHROOT}/boot/vmlinuz-${KERNEL_VERSION}" \
               "${INCLUDES_CHROOT}/boot/vmlinuz" \
               "${INCLUDES_CHROOT}/boot/vmlinuz.old" \
               "${INCLUDES_CHROOT}/boot/initrd.img-${KERNEL_VERSION}" \
               "${INCLUDES_CHROOT}/boot/initrd.img" \
               "${INCLUDES_CHROOT}/boot/initrd.img.old"
    
    log info "Kernel ${KERNEL_VERSION} erfolgreich in Chroot kopiert."
  else
    log error "Kernel-Dateien für Version ${KERNEL_VERSION} nicht gefunden!"
    log error "Pfade geprüft:"
    log error "- /boot/vmlinuz-${KERNEL_VERSION}"
    log error "- /boot/initrd.img-${KERNEL_VERSION}"
    exit 1
  fi
}

# Erstelle live-build Konfiguration
configure_live_build() {
  log info "Konfiguriere live-build..."
  
  cd "$BUILD_DIR"
  
  # Minimale Konfigurationsdatei anlegen
  mkdir -p /etc/live
  cat > /etc/live/build.conf << EOF
# Live-Build Standardkonfiguration
LIVE_DISTRIBUTION="oracular"
LIVE_MIRROR_BOOTSTRAP="http://192.168.56.120/ubuntu/"
LIVE_MIRROR_BINARY="http://192.168.56.120/ubuntu/"
LIVE_MIRROR_CHROOT="http://192.168.56.120/ubuntu/"
LIVE_MIRROR_CHROOT_SECURITY="http://192.168.56.120/ubuntu/"
LIVE_ARCHITECTURE="amd64"
EOF

  # Bootstrap-Konfiguration
  mkdir -p /etc/live/build.d
  cat > /etc/live/build.d/bootstrap.conf << EOF
# Bootstrap-Konfiguration
DEBOOTSTRAP_OPTIONS="--variant=minbase"
LB_DISTRIBUTION="oracular"
LB_PARENT_DISTRIBUTION="oracular"
EOF

  # Erstelle debootstrap Konfiguration
  mkdir -p "${CONFIG_DIR}"  # Nur das config-Verzeichnis erstellen
  cat > "${CONFIG_DIR}/bootstrap_debootstrap" << 'EOF'
DEBOOTSTRAP_OPTIONS="--variant=minbase --include=\
        live-boot systemd-sysv busybox-static iproute2 iputils-ping \
        network-manager dhcpcd5 wget curl console-setup kbd locales \
        bash dialog zstd"
EOF

  # Live-Build Konfiguration
  lb config \
    --mirror-bootstrap "http://192.168.56.120/ubuntu/" \
    --mirror-binary "http://192.168.56.120/ubuntu/" \
    --mirror-chroot "http://192.168.56.120/ubuntu/" \
    --mirror-chroot-security "http://192.168.56.120/ubuntu/" \
    --distribution oracular \
    --architectures amd64 \
    --binary-images iso-hybrid \
    --mode ubuntu \
    --security false \
    --apt-recommends false \
    --debian-installer false \
    --memtest none \
    --firmware-binary false \
    --firmware-chroot false \
    --backports false \
    --cache-packages false \
    --cache-stages false \
    --interactive false \
    --compression xz \
    --apt-indices false \
    --apt-source-archives false \
    --iso-volume "$ISO_TITLE" \
    --iso-publisher "$ISO_PUBLISHER" \
    --iso-application "$ISO_APPLICATION"

  log info "Live-build Konfiguration abgeschlossen."
}

# Erstelle Paketlisten
create_package_lists() {
  log info "Erstelle minimale Paketliste..."

  # Paketliste des Live-Systems
  cat > "${PACKAGE_LISTS}/minimal.list.chroot" << EOF
# Minimale Systempakete
zstd
# live-boot
systemd-sysv
linux-image-generic
busybox-static

# Netzwerkunterstützung
iproute2
iputils-ping
network-manager
dhcpcd-base
wget
curl

# Tastatur- und Sprachunterstützung
console-setup
kbd
locales

# Extras für UbuntuFDE
bash
# dialog
EOF

  log info "Paketliste erstellt."
}

# APT-Quellen im Chroot einrichten
fix_chroot_apt_sources() {
  log info "Setze APT-Quellen im chroot..."
  
  # Erstelle sources.list im chroot
  mkdir -p "${BUILD_DIR}/chroot/etc/apt/sources.list.d"
  cat > "${BUILD_DIR}/chroot/etc/apt/sources.list" << EOF
deb http://archive.ubuntu.com/ubuntu/ oracular main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ oracular-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ oracular-security main restricted universe multiverse
EOF

  # Kopiere die Standardzertifikate in das chroot (falls nicht vorhanden)
  if [ ! -d "${BUILD_DIR}/chroot/usr/share/ca-certificates" ]; then
    mkdir -p "${BUILD_DIR}/chroot/usr/share/ca-certificates"
    cp -r /usr/share/ca-certificates/* "${BUILD_DIR}/chroot/usr/share/ca-certificates/"
  fi
  
  log info "APT-Quellen im chroot eingerichtet."
}

# Erstelle Hook zum Entfernen unnötiger Dateien
create_cleanup_hook() {
  log info "Erstelle Hook zum Bereinigen des Systems..."

  cat > "${CHROOT_HOOKS}/0100-cleanup-system.hook.chroot" << 'EOF'
#!/bin/bash
set -e

echo "Entferne unnötige Dokumentation..."
rm -rf /usr/share/doc/*
rm -rf /usr/share/man/*
rm -rf /usr/share/info/*

echo "Entferne alle Lokalisierungsdateien außer Deutsch und Englisch..."
# Sichere de_DE und en_US
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

# Lösche alle Lokalisierungsdateien
rm -rf /usr/share/locale/*

# Stelle de_DE und en_US wieder her
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

echo "Bereinige APT Caches..."
nala clean
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/archives/*

echo "Entferne temporäre Dateien..."
rm -rf /var/tmp/*
rm -rf /tmp/*
rm -f /var/crash/*

echo "Entferne unnötige Kernel-Module..."
# Behalte nur essentielle Module für Netzwerk und Dateisysteme
KEEP_MODULES="e1000 e1000e r8169 igb ixgbe virtio_net 8021q ext4 vfat isofs nls_iso8859_1 nls_cp437 nls_utf8 usbhid xhci_hcd ehci_hcd uhci_hcd"

cd /lib/modules/$(uname -r)
for MODULE_DIR in kernel/drivers/net/ethernet kernel/fs; do
  if [ -d "$MODULE_DIR" ]; then
    cd "$MODULE_DIR"
    for MODULE in $KEEP_MODULES; do
      # Suche nicht nach exaktem Modulnamen, sondern nach Teilstrings
      find . -name "*.ko" | grep -i "$MODULE" | while read -r MODULE_FILE; do
        echo "Behalte Modul: $MODULE_FILE"
      done
    done
    cd /lib/modules/$(uname -r)
  fi
done

echo "System erfolgreich bereinigt."
EOF

  chmod +x "${CHROOT_HOOKS}/0100-cleanup-system.hook.chroot"

  log info "Bereinigungs-Hook erstellt."
}

# Erstelle Netzwerk-Setup-Skript
create_network_setup() {
  log info "Erstelle Netzwerk-Setup-Skript..."
  
  mkdir -p "${INCLUDES_CHROOT}/opt/ubuntufde"
  
  cat > "${INCLUDES_CHROOT}/opt/ubuntufde/network_setup.sh" << 'EOF'
#!/bin/bash
# Netzwerk-Setup-Skript für UbuntuFDE
# Dieses Skript richtet die Netzwerkverbindung intelligent ein

# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging-Funktion
log() {
  local level=$1
  shift
  local message="$@"
  
  case $level in
    "info")
      echo -e "${GREEN}[INFO]${NC} $message"
      ;;
    "warn")
      echo -e "${YELLOW}[WARN]${NC} $message"
      ;;
    "error")
      echo -e "${RED}[ERROR]${NC} $message"
      ;;
    *)
      echo -e "${BLUE}[DEBUG]${NC} $message"
      ;;
  esac
}

# Netzwerkschnittstellen ermitteln
get_network_interfaces() {
  local interfaces=()
  for iface in $(ip -o link show | grep -v "lo:" | awk -F': ' '{print $2}'); do
    interfaces+=("$iface")
  done
  echo "${interfaces[@]}"
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
  log info "Versuche NetworkManager für automatische Konfiguration..."
  
  # Prüfen, ob NetworkManager läuft
  if ! systemctl is-active NetworkManager >/dev/null 2>&1; then
    systemctl start NetworkManager
    sleep 3
  fi
  
  # Warte auf automatische Verbindung
  for i in {1..10}; do
    if check_internet; then
      log info "NetworkManager hat erfolgreich eine Verbindung hergestellt."
      return 0
    fi
    log info "Warte auf NetworkManager Verbindung... ($i/10)"
    sleep 2
  done
  
  log warn "NetworkManager konnte keine automatische Verbindung herstellen."
  return 1
}

# Versuche DHCP für eine Schnittstelle
try_dhcp() {
  local iface=$1
  log info "Versuche DHCP auf Schnittstelle $iface..."
  
  ip link set $iface up
  
  # Versuche dhclient, falls verfügbar
  if command -v dhclient >/dev/null 2>&1; then
    dhclient -v -1 $iface
  else
    # Versuche dhcpcd als Alternative
    dhcpcd -t 10 $iface
  fi
  
  # Warte kurz und prüfe die Verbindung
  sleep 3
  
  if check_internet; then
    log info "DHCP erfolgreich für $iface, Internetverbindung hergestellt."
    return 0
  else
    log warn "DHCP für $iface war nicht erfolgreich."
    return 1
  fi
}

# Intelligente statische IP-Konfiguration
try_static_ip() {
  local iface=$1
  log info "Versuche statische IP-Konfiguration für $iface..."
  
  # Versuche, Netzwerkinformationen zu ermitteln
  local subnet_prefix="192.168.1"
  local gateways=("1" "254")
  
  # Falls Informationen über die vorhandene Netzwerkumgebung existieren,
  # können wir das nutzen
  local arp_output=$(ip neigh show)
  if [ -n "$arp_output" ]; then
    local existing_ips=$(echo "$arp_output" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
    if [ -n "$existing_ips" ]; then
      subnet_prefix=$(echo "$existing_ips" | cut -d. -f1-3)
      log info "Erkanntes Subnetz: $subnet_prefix"
    fi
  fi
  
  # Versuche mehrere mögliche IP-Adressen
  for i in {100..105}; do
    local ip_addr="${subnet_prefix}.${i}"
    log info "Versuche IP: $ip_addr"
    
    # Prüfe, ob die IP bereits verwendet wird
    if ping -c 1 -W 1 "$ip_addr" > /dev/null 2>&1; then
      log warn "IP $ip_addr ist bereits vergeben, probiere nächste..."
      continue
    fi
    
    ip addr add ${ip_addr}/24 dev $iface
    
    # Gateways durchprobieren
    for gw in "${gateways[@]}"; do
      local gateway="${subnet_prefix}.${gw}"
      log info "Versuche Gateway: $gateway"
      
      ip route add default via "$gateway" dev $iface
      
      # Prüfe, ob Internetverbindung besteht
      if check_internet; then
        log info "Statische IP-Konfiguration erfolgreich: $ip_addr mit Gateway $gateway"
        return 0
      else
        # Lösche die Route und versuche den nächsten Gateway
        ip route del default via "$gateway" dev $iface 2>/dev/null
      fi
    done
    
    # Diese IP-Adresse funktioniert nicht, zurücksetzen und nächste probieren
    ip addr del ${ip_addr}/24 dev $iface 2>/dev/null
  done
  
  log warn "Konnte keine automatische statische IP-Konfiguration für $iface einrichten."
  return 1
}

# Manuelle Netzwerkkonfiguration
manual_network_setup() {
  echo ""
  echo "=== Manuelle Netzwerkkonfiguration ==="
  echo ""
  
  # Zeige verfügbare Netzwerkschnittstellen
  local interfaces=($(get_network_interfaces))
  echo "Verfügbare Netzwerkschnittstellen:"
  local i=0
  for iface in "${interfaces[@]}"; do
    echo "[$i] $iface"
    i=$((i+1))
  done
  
  # Schnittstelle auswählen
  read -p "Wähle eine Netzwerkschnittstelle (0-$((i-1))): " choice
  local selected_iface="${interfaces[$choice]}"
  
  if [ -z "$selected_iface" ]; then
    log error "Ungültige Auswahl. Abbruch."
    return 1
  fi
  
  ip link set "$selected_iface" up
  
  # IP-Konfiguration auswählen
  echo "Netzwerkkonfiguration für $selected_iface:"
  echo "[1] DHCP (automatisch)"
  echo "[2] Statische IP-Adresse"
  read -p "Wähle eine Option (1-2): " config_choice
  
  case $config_choice in
    1)
      if command -v dhclient >/dev/null 2>&1; then
        dhclient -v "$selected_iface"
      else
        dhcpcd -t 15 "$selected_iface"
      fi
      ;;
    2)
      read -p "IP-Adresse (z.B. 192.168.1.100): " ip_addr
      read -p "Netzmaske (z.B. 24 für /24): " netmask
      read -p "Gateway (z.B. 192.168.1.1): " gateway
      read -p "DNS-Server (z.B. 8.8.8.8): " dns
      
      ip addr add ${ip_addr}/${netmask} dev "$selected_iface"
      ip route add default via "$gateway" dev "$selected_iface"
      echo "nameserver $dns" > /etc/resolv.conf
      ;;
    *)
      log error "Ungültige Auswahl. Abbruch."
      return 1
      ;;
  esac
  
  # Prüfe Verbindung
  if check_internet; then
    log info "Netzwerkkonfiguration erfolgreich. Internetverbindung hergestellt."
    return 0
  else
    log error "Netzwerkkonfiguration fehlgeschlagen. Keine Internetverbindung."
    return 1
  fi
}

# Hauptfunktion
setup_network() {
  log info "Starte Netzwerkkonfiguration..."
  
  # Versuche erst NetworkManager (wenn verfügbar)
  if command -v nmcli >/dev/null 2>&1; then
    if try_networkmanager; then
      return 0
    fi
  fi
  
  # Alle Netzwerkschnittstellen ermitteln
  interfaces=($(get_network_interfaces))
  
  if [ ${#interfaces[@]} -eq 0 ]; then
    log error "Keine Netzwerkschnittstellen gefunden."
    return 1
  fi
  
  # Versuche DHCP auf allen Schnittstellen
  for iface in "${interfaces[@]}"; do
    if try_dhcp "$iface"; then
      return 0
    fi
  done
  
  log warn "DHCP-Konfiguration fehlgeschlagen. Versuche statische IP..."
  
  # Versuche statische IP auf allen Schnittstellen
  for iface in "${interfaces[@]}"; do
    if try_static_ip "$iface"; then
      return 0
    fi
  done
  
  log warn "Automatische Netzwerkkonfiguration fehlgeschlagen. Wechsle zu manueller Konfiguration."
  
  # Als letzten Ausweg manuelle Konfiguration anbieten
  manual_network_setup
}

# Führe die Netzwerkkonfiguration durch
setup_network
EOF
  
  chmod +x "${INCLUDES_CHROOT}/opt/ubuntufde/network_setup.sh"
  
  log info "Netzwerk-Setup-Skript erstellt."
}

# Erstelle Sprachunterstützungsdateien
create_language_support() {
  log info "Erstelle Sprachunterstützungsdateien..."
  
  # Verzeichnis für Sprachdateien
  LANG_DIR="${INCLUDES_CHROOT}/opt/ubuntufde/lang"
  mkdir -p "$LANG_DIR"
  
  # Erstelle deutsche Sprachdatei
  cat > "${LANG_DIR}/de_DE.conf" << 'EOF'
# Deutsche Sprache für UbuntuFDE
LANGUAGE_NAME="Deutsch"
WELCOME_MESSAGE="Willkommen bei UbuntuFDE Installation!"
LANGUAGE_PROMPT="Wähle die Anzeigesprache:"
KEYBOARD_PROMPT="Wähle das Tastaturlayout:"
KEYBOARD_DE_DE="Deutsch (Deutschland)"
KEYBOARD_DE_CH="Deutsch (Schweiz)"
KEYBOARD_DE_AT="Deutsch (Österreich)"
KEYBOARD_EN_US="Englisch (US)"
NETWORK_SETUP="Richte Netzwerkverbindung ein..."
DOWNLOADING="Lade Installations-Skript herunter..."
STARTING_INSTALL="Starte Installation..."
ERROR_DOWNLOAD="Fehler beim Herunterladen des Skripts. Bitte Netzwerkeinstellungen prüfen."
EOF
  
  # Erstelle englische Sprachdatei
  cat > "${LANG_DIR}/en_US.conf" << 'EOF'
# English language for UbuntuFDE
LANGUAGE_NAME="English"
WELCOME_MESSAGE="Welcome to UbuntuFDE Installation!"
LANGUAGE_PROMPT="Select display language:"
KEYBOARD_PROMPT="Select keyboard layout:"
KEYBOARD_DE_DE="German (Germany)"
KEYBOARD_DE_CH="German (Switzerland)"
KEYBOARD_DE_AT="German (Austria)"
KEYBOARD_EN_US="English (US)"
NETWORK_SETUP="Setting up network connection..."
DOWNLOADING="Downloading installation script..."
STARTING_INSTALL="Starting installation..."
ERROR_DOWNLOAD="Error downloading script. Please check network settings."
EOF
  
  log info "Sprachunterstützungsdateien erstellt."
}

# Tastaturlayouts hinzufügen
create_keyboard_layouts() {
  log info "Erstelle Tastaturlayout-Konfiguration..."
  
  # Verzeichnis für Tastaturlayouts
  KEYBOARD_DIR="${INCLUDES_CHROOT}/opt/ubuntufde/kbd"
  mkdir -p "$KEYBOARD_DIR"
  
  # Konfigurationsdatei für die Tastaturlayouts erstellen
  cat > "${KEYBOARD_DIR}/keyboard.conf" << 'EOF'
# Tastaturlayout-Konfiguration
# Format: layout_id,xkb_layout,xkb_variant
de_de,de,
de_ch,ch,de_CH
de_at,at,
en_us,us,
EOF
  
  # Erstelle ein einfaches Skript zum Setzen des XKB-Layouts
  cat > "${KEYBOARD_DIR}/set-xkb-layout.sh" << 'EOF'
#!/bin/bash
# Skript zum Setzen des XKB-Layouts

if [ $# -lt 1 ]; then
  echo "Verwendung: $0 <layout> [variant]"
  exit 1
fi

LAYOUT="$1"
VARIANT="$2"

# Prüfe, ob wir in einer grafischen Umgebung sind
if [ -n "$DISPLAY" ]; then
  # Wir haben eine grafische Umgebung, nutze setxkbmap
  if [ -n "$VARIANT" ]; then
    setxkbmap -layout "$LAYOUT" -variant "$VARIANT" || echo "Fehler beim Setzen des X-Layouts"
  else
    setxkbmap -layout "$LAYOUT" || echo "Fehler beim Setzen des X-Layouts"
  fi
else
  # Textmodus, nutze loadkeys mit den richtigen Konsolen-Keymaps
  case "${LAYOUT}" in
    "de")
      loadkeys de-latin1 || echo "Fehler beim Setzen des Konsolen-Layouts"
      ;;
    "ch")
      loadkeys ch-de || loadkeys ch || echo "Fehler beim Setzen des Konsolen-Layouts"
      ;;
    "at")
      loadkeys de-latin1 || loadkeys at || echo "Fehler beim Setzen des Konsolen-Layouts"
      ;;
    "us")
      loadkeys us || echo "Fehler beim Setzen des Konsolen-Layouts"
      ;;
    *)
      echo "Unbekanntes Layout: $LAYOUT"
      ;;
  esac
fi
EOF

  chmod +x "${KEYBOARD_DIR}/set-xkb-layout.sh"
  
  log info "Tastaturlayout-Konfiguration erstellt."
}

# Erstelle Hauptskript für die Installation
create_main_script() {
  log info "Erstelle Hauptinstallationsskript..."
  
  cat > "${INCLUDES_CHROOT}/opt/ubuntufde/start_installation.sh" << EOF
#!/bin/bash
# UbuntuFDE Hauptinstallationsskript
# Dieses Skript steuert den Installationsprozess

# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Standardwerte
SELECTED_LANGUAGE="de_DE"
SELECTED_KEYBOARD="de_de"
INSTALLATION_URL="${INSTALLATION_URL}"

# Pfade
LANG_DIR="/opt/ubuntufde/lang"
KEYBOARD_DIR="/opt/ubuntufde/kbd"

# Logging-Funktion
log() {
  local level=\$1
  shift
  local message="\$@"
  
  case \$level in
    "info")
      echo -e "\${GREEN}[INFO]\${NC} \$message"
      ;;
    "warn")
      echo -e "\${YELLOW}[WARN]\${NC} \$message"
      ;;
    "error")
      echo -e "\${RED}[ERROR]\${NC} \$message"
      ;;
    *)
      echo -e "\${BLUE}[DEBUG]\${NC} \$message"
      ;;
  esac
}

# Lade Sprachdefinitionen
load_language() {
  local lang_file="\$LANG_DIR/\$SELECTED_LANGUAGE.conf"
  if [ -f "\$lang_file" ]; then
    source "\$lang_file"
    log info "Sprache geladen: \$LANGUAGE_NAME"
  else
    log error "Sprachdatei nicht gefunden: \$lang_file"
    # Fallback zu Englisch
    SELECTED_LANGUAGE="en_US"
    source "\$LANG_DIR/en_US.conf"
  fi
}

# Sprachauswahl
select_language() {
  clear
  echo "==============================================="
  echo "           UbuntuFDE Installation"
  echo "==============================================="
  echo ""
  echo "Anzeigesprache / Display language:"
  echo ""
  echo "1) Deutsch [Standard/Default]"
  echo "2) English"
  echo ""
  read -p "Auswahl/Selection [1]: " choice
  
  case \${choice:-1} in
    1|"")
      SELECTED_LANGUAGE="de_DE"
      ;;
    2)
      SELECTED_LANGUAGE="en_US"
      ;;
    *)
      log warn "Ungültige Auswahl. Verwende Standard: Deutsch"
      SELECTED_LANGUAGE="de_DE"
      ;;
  esac
  
  # Lade die gewählte Sprache
  load_language
}

# Tastaturlayout-Auswahl
select_keyboard() {
  clear
  echo "==============================================="
  echo "           UbuntuFDE Installation"
  echo "==============================================="
  echo ""
  echo "\$KEYBOARD_PROMPT"
  echo ""
  echo "1) \$KEYBOARD_DE_DE [Standard/Default]"
  echo "2) \$KEYBOARD_DE_CH"
  echo "3) \$KEYBOARD_DE_AT"
  echo "4) \$KEYBOARD_EN_US"
  echo ""
  read -p "Auswahl/Selection [1]: " choice
  
  case \${choice:-1} in
    1|"")
      SELECTED_KEYBOARD="de_de"
      ;;
    2)
      SELECTED_KEYBOARD="de_ch"
      ;;
    3)
      SELECTED_KEYBOARD="de_at"
      ;;
    4)
      SELECTED_KEYBOARD="en_us"
      ;;
    *)
      log warn "Ungültige Auswahl. Verwende Standard: Deutsch (Deutschland)"
      SELECTED_KEYBOARD="de_de"
      ;;
  esac
  
  # Setze das Tastaturlayout
  set_keyboard
}

# Tastaturlayout aktivieren
set_keyboard() {
  local kbd_conf="\$KEYBOARD_DIR/keyboard.conf"
  if [ -f "\$kbd_conf" ]; then
    local xkb_layout=\$(grep "^\$SELECTED_KEYBOARD," "\$kbd_conf" | cut -d, -f2)
    local xkb_variant=\$(grep "^\$SELECTED_KEYBOARD," "\$kbd_conf" | cut -d, -f3)
    
    if [ -n "\$xkb_layout" ]; then
      log info "Setze Tastaturlayout: \$xkb_layout \$([ -n "\$xkb_variant" ] && echo "Variante: \$xkb_variant")"
      
      # Verwende das Skript, um das Tastaturlayout zu setzen
      if [ -f "\$KEYBOARD_DIR/set-xkb-layout.sh" ]; then
        "\$KEYBOARD_DIR/set-xkb-layout.sh" "\$xkb_layout" "\$xkb_variant"
      else
        log warn "Tastaturlayout-Skript nicht gefunden. Tastaturlayout konnte nicht gesetzt werden."
      fi
    else
      log error "Tastaturlayout nicht gefunden: \$SELECTED_KEYBOARD"
    fi
  else
    log error "Tastaturkonfiguration nicht gefunden: \$kbd_conf"
  fi
}

# Netzwerkverbindung einrichten
setup_network() {
  clear
  echo "==============================================="
  echo "           UbuntuFDE Installation"
  echo "==============================================="
  echo ""
  echo "\$NETWORK_SETUP"
  echo ""
  
  # Führe das Netzwerk-Setup-Skript aus
  bash /opt/ubuntufde/network_setup.sh
}

# Installationsskript herunterladen und ausführen
download_and_run() {
  # Installationsskript direkt herunterladen ohne weitere Benachrichtigungen
  wget -O /tmp/install.sh "\$INSTALLATION_URL"
  
  if [ \$? -eq 0 ]; then
    chmod +x /tmp/install.sh
    # Skript sofort ausführen ohne weitere Interaktion
    /tmp/install.sh
  else
    # Bei Fehler erneuter Versuch mit Netzwerkkonfiguration
    log error "Download fehlgeschlagen. Versuche Netzwerk neu einzurichten..."
    sleep 3
    setup_network
    download_and_run
  fi
}

# Hauptablauf
main() {
  select_language
  select_keyboard
  setup_network
  download_and_run
}

# Starte den Hauptablauf
main
EOF
  
  chmod +x "${INCLUDES_CHROOT}/opt/ubuntufde/start_installation.sh"
  
  log info "Hauptinstallationsskript erstellt."
}

# Erstelle Autostart für das Installationsskript
create_autostart() {
  log info "Erstelle Autostart für die Installation..."
  
  # Systemd-Service erstellen
  cat > "${INCLUDES_CHROOT}/etc/systemd/system/ubuntufde-installer.service" << EOF
[Unit]
Description=UbuntuFDE Installer
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash /opt/ubuntufde/start_installation.sh
StandardInput=tty
StandardOutput=tty
StandardError=tty
TTYPath=/dev/tty1

[Install]
WantedBy=multi-user.target
EOF

  # Boot-Konfiguration anpassen
  mkdir -p "${CONFIG_DIR}/includes.binary/boot/grub/grub.cfg.d"
  cat > "${CONFIG_DIR}/includes.binary/boot/grub/grub.cfg.d/ubuntufde.cfg" << EOF
set timeout=1
set default=0
set menu_color_normal=white/black
set menu_color_highlight=black/light-gray
EOF

  # Systemd-Service aktivieren
  mkdir -p "${INCLUDES_CHROOT}/etc/systemd/system/multi-user.target.wants"
  ln -sf "/etc/systemd/system/ubuntufde-installer.service" "${INCLUDES_CHROOT}/etc/systemd/system/multi-user.target.wants/ubuntufde-installer.service"
  
  log info "Autostart für die Installation erstellt."
}

# ISO erstellen
build_iso() {
  log info "Erstelle ISO-Image..."
  
  cd "$BUILD_DIR"
  
  # Debug-Ausgabe aktivieren für bessere Fehlerdiagnose
  export LB_DEBUG=1
  
  # ISO bauen
  lb build 2>&1 | tee -a "$LOG_FILE"
  BUILD_RESULT=$?
  
  if [ $? -ne 0 ]; then
    log error "ISO-Erstellung fehlgeschlagen. Siehe $LOG_FILE für Details."
    # Prüfe, ob das Fehlen der ISO das Problem ist
    if [ ! -f "${BUILD_DIR}/live-image-amd64.hybrid.iso" ]; then
      log info "Versuche den binary-Schritt separat auszuführen..."
      lb binary 2>&1 | tee -a "$LOG_FILE"
    fi
    exit 1
  fi
  
  # Verschiebe die erstellte ISO in das Ausgabeverzeichnis
  if [ -f "${BUILD_DIR}/live-image-amd64.hybrid.iso" ]; then
    mkdir -p "$OUTPUT_DIR"
    mv "${BUILD_DIR}/live-image-amd64.hybrid.iso" "${OUTPUT_DIR}/ubuntufde.iso"
    
    # ISO-Größe anzeigen
    ISO_SIZE=$(du -h "${OUTPUT_DIR}/ubuntufde.iso" | cut -f1)
    log info "ISO erfolgreich erstellt: ${OUTPUT_DIR}/ubuntufde.iso (Größe: $ISO_SIZE)"
  else
    # Suche nach der ISO an alternativen Orten
    ALTERNATIVE_ISO=$(find "$BUILD_DIR" -name "*.iso" -type f | head -1)
    
    if [ -n "$ALTERNATIVE_ISO" ]; then
      mkdir -p "$OUTPUT_DIR"
      cp "$ALTERNATIVE_ISO" "${OUTPUT_DIR}/ubuntufde.iso"
      
      ISO_SIZE=$(du -h "${OUTPUT_DIR}/ubuntufde.iso" | cut -f1)
      log info "ISO erfolgreich erstellt (alternativer Pfad): ${OUTPUT_DIR}/ubuntufde.iso (Größe: $ISO_SIZE)"
    else
      log error "ISO-Datei wurde nicht gefunden. Build fehlgeschlagen."
      exit 1
    fi
  fi
}

# Aufräumen
cleanup() {
  log info "Räume temporäre Dateien auf..."
  
  read -p "Möchtest du die temporären Build-Dateien aufräumen? (j/n): " -n 1 -r
  echo
  
  if [[ $REPLY =~ ^[Jj]$ ]]; then
    # Lösche nur bestimmte Verzeichnisse, behalte die Konfiguration
    rm -rf "${BUILD_DIR}/.build"
    rm -rf "${BUILD_DIR}/cache"
    log info "Temporäre Build-Dateien gelöscht."
  else
    log info "Temporäre Build-Dateien wurden beibehalten."
  fi
}

# --------------------------------
# Hauptprogramm
# --------------------------------
main() {
  echo -e "${BLUE}===== UbuntuFDE ISO-Erstellung (Ubuntu-basiert) =====${NC}"
  echo
  
  # Prüfe Root-Rechte
  if [ "$(id -u)" -ne 0 ]; then
    log error "Dieses Skript benötigt Root-Rechte. Bitte mit sudo ausführen."
    exit 1
  fi
  
  # Schritte ausführen
  check_dependencies
  setup_directories
  customize_lb_bootstrap
  configure_live_build
  create_package_lists
  # fix_chroot_apt_sources
  create_cleanup_hook
  create_network_setup
  create_language_support
  create_keyboard_layouts
  create_main_script
  create_autostart
  build_iso
  cleanup
  
  log info "UbuntuFDE ISO-Erstellung abgeschlossen!"
  log info "Die neue ISO befindet sich hier: ${OUTPUT_DIR}/ubuntufde.iso"
}

# Starte das Hauptprogramm
main "$@"