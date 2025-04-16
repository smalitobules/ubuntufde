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
INSTALLATION_URL="https://indianfire.ch/fde"

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
  )

      #ubuntu-pro-client
      #ubuntu-docs
      #plymouth
      #xorriso
      #polkitd
      #libisoburn1t64


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

# Wrapper für Paketoperationen
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
  local commands=("debootstrap" "xorriso" "mksquashfs")
  local packages=("debootstrap" "xorriso" "squashfs-tools")
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
    pkg_update
    pkg_install "${missing_packages[@]}"
    
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
  local base_packages="adduser,apt-utils,bash,ca-certificates,console-setup,cryptsetup,curl \
                      dbus,dhcpcd5,dialog,grub-efi-amd64,grub-pc,gpg,gpgv,iproute2,iputils-ping \
                      keyboard-configuration,kbd,kmod,libgcc-s1,libnss-systemd,libpam-systemd \
                      libstdc++6,libc6,locales,login,lvm2,nala,network-manager,netplan.io,passwd \
                      squashfs-tools,systemd,systemd-sysv,tzdata,udev,wget,zstd"
  
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
  
  # Restliche Pakete installieren
  log info "Installiere zusätzliche Pakete..."
  
  # Bereite chroot-Umgebung vor
  mkdir -p "$CHROOT_DIR/dev" "$CHROOT_DIR/dev/pts" "$CHROOT_DIR/proc" "$CHROOT_DIR/sys"
  mount -B /dev "$CHROOT_DIR/dev"
  mount -B /dev/pts "$CHROOT_DIR/dev/pts"
  mount -B /proc "$CHROOT_DIR/proc" 
  mount -B /sys "$CHROOT_DIR/sys"

  ## Bereite chroot-Umgebung vor
  #for dir in /dev /dev/pts /proc /sys; do
  #  mkdir -p "$CHROOT_DIR$dir"
  #  mount -B $dir "$CHROOT_DIR$dir"
  #done
  
  # Installiere die Pakete im chroot
  local remaining_packages=$(echo "$include_list" | sed "s/$base_packages,//g")
  
  # Erstelle ein temporäres Skript für die chroot-Installation
  cat > "$CHROOT_DIR/install_packages.sh" << EOF
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

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
pkg_update
pkg_upgrade

# Restliche Pakete installieren
nala install -y $remaining_packages
EOF
  
  chmod +x "$CHROOT_DIR/install_packages.sh"
  
  # Führe das Skript im chroot aus
  chroot "$CHROOT_DIR" /install_packages.sh
  
  if [ $? -ne 0 ]; then
    log warn "Einige Pakete konnten nicht installiert werden. Fahre trotzdem fort."
  else
    log info "Pakete erfolgreich installiert."
  fi
  
  # Entferne das temporäre Skript
  rm -f "$CHROOT_DIR/install_packages.sh"
  
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

  # Script für Schlüsselimport erstellen
  cat > "$CHROOT_DIR/import_keys.sh" << 'EOF'
#!/bin/bash
set -e
mkdir -p /etc/apt/keyrings/
cp /tmp/ubuntu-archive-keyring.gpg /etc/apt/keyrings/ubuntu-archive-keyring.gpg
cp /tmp/local-mirror.gpg /etc/apt/keyrings/local-mirror.gpg
pkg_update
EOF

  chmod +x "$CHROOT_DIR/import_keys.sh"

  # Erstelle und hänge benötigte Verzeichnisse ein
  mkdir -p "$CHROOT_DIR/dev" "$CHROOT_DIR/proc" "$CHROOT_DIR/sys"
  mount -B /dev "$CHROOT_DIR/dev"
  mount -B /proc "$CHROOT_DIR/proc" 
  mount -B /sys "$CHROOT_DIR/sys"

  # Führe Schlüsselimport durch
  chroot "$CHROOT_DIR" /import_keys.sh

  # Hänge Verzeichnisse aus
  umount "$CHROOT_DIR/dev" 
  umount "$CHROOT_DIR/proc" 
  umount "$CHROOT_DIR/sys"

  rm -f "$CHROOT_DIR/import_keys.sh"
  
  log info "Paketquellen konfiguriert."
}

# Systemkonfiguration im chroot
configure_system() {
  log info "Konfiguriere System im chroot..."
  
  # Hostname setzen
  echo "ubuntufde-live" > "$CHROOT_DIR/etc/hostname"
  echo "127.0.1.1 ubuntufde-live" >> "$CHROOT_DIR/etc/hosts"
  
  # Basisverzeichnisse für chroot erstellen und einhängen
  for dir in /dev /dev/pts /proc /sys /run; do
    mkdir -p "$CHROOT_DIR$dir"
    mount -B $dir "$CHROOT_DIR$dir"
  done
  
  # Sprach- und Zeitzonen konfigurieren
  chroot "$CHROOT_DIR" locale-gen de_DE.UTF-8 en_US.UTF-8
  chroot "$CHROOT_DIR" update-locale LANG=de_DE.UTF-8
  
  # Tastaturlayout einrichten
  cat > "$CHROOT_DIR/etc/default/keyboard" << EOF
XKBMODEL="pc105"
XKBLAYOUT="de"
XKBVARIANT=""
XKBOPTIONS=""
EOF

  # Zeitzone setzen
  chroot "$CHROOT_DIR" ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
  
  # Netzwerk konfigurieren
  cat > "$CHROOT_DIR/etc/network/interfaces" << EOF
# The loopback network interface
auto lo
iface lo inet loopback

# Primary network interface - DHCP by default
auto eth0
iface eth0 inet dhcp
EOF

  # Benutzer und Passwörter erstellen
  chroot "$CHROOT_DIR" useradd -m -s /bin/bash ubuntu
  echo "ubuntu:ubuntu" | chroot "$CHROOT_DIR" chpasswd
  echo "root:toor" | chroot "$CHROOT_DIR" chpasswd
  
  log info "System konfiguriert."
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
    systemctl start NetworkManager || service network-manager start
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
  
  log warn "Netzwerkkonfiguration fehlgeschlagen. Bitte manuell konfigurieren."
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
  log info "Erstelle Hauptinstallationsskript..."
  
  cat > "$CHROOT_DIR/opt/ubuntufde/start_installation.sh" << EOF
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
INSTALLATION_URL="${INSTALLATION_URL}"

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

# Tastaturlayout aktivieren
set_keyboard() {
  log info "Setze Tastaturlayout: de"
  loadkeys de-latin1 || echo "Fehler beim Setzen des Konsolen-Layouts"
}

# Netzwerkverbindung einrichten
setup_network() {
  clear
  echo "==============================================="
  echo "           UbuntuFDE Installation"
  echo "==============================================="
  echo ""
  echo "Richte Netzwerkverbindung ein..."
  echo ""
  
  # Führe das Netzwerk-Setup-Skript aus
  bash /opt/ubuntufde/network_setup.sh
}

# Installationsskript herunterladen und ausführen
download_and_run() {
  log info "Lade Installationsskript herunter..."
  
  wget -O /tmp/UbuntuFDE.sh "\$INSTALLATION_URL"
  
  if [ \$? -eq 0 ]; then
    chmod +x /tmp/UbuntuFDE.sh
    log info "Starte Installation..."
    /tmp/UbuntuFDE.sh
  else
    log error "Download fehlgeschlagen. Versuche Netzwerk neu einzurichten..."
    sleep 3
    setup_network
    download_and_run
  fi
}

# Hauptablauf
main() {
  set_keyboard
  setup_network
  download_and_run
}

# Starte den Hauptablauf
main
EOF
  
  chmod +x "$CHROOT_DIR/opt/ubuntufde/start_installation.sh"
  
  log info "Hauptinstallationsskript erstellt."
}

# Autostart des Installationsskripts einrichten
create_autostart() {
  log info "Erstelle Autostart für die Installation..."
  
  # rc.local mit automatischem Start
  cat > "$CHROOT_DIR/etc/rc.local" << 'EOF'
#!/bin/bash
# Auto-start UbuntuFDE installer

# Starte Installation im ersten tty
openvt -c 1 -s -w -- /bin/bash /opt/ubuntufde/start_installation.sh

exit 0
EOF

  chmod +x "$CHROOT_DIR/etc/rc.local"
  
  log info "Autostart für die Installation erstellt."
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
pkg_clean
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
    
    # Installiere Kernel und Casper
    chroot "$CHROOT_DIR" bash -c "pkg_update && pkg_install linux-image-generic casper"
    
    # Neuen Kernel erkennen
    KERNEL_VERSION=$(ls -1 "$CHROOT_DIR/boot/vmlinuz-"* | head -1 | sed "s|$CHROOT_DIR/boot/vmlinuz-||")
    
    if [ -z "$KERNEL_VERSION" ]; then
      log error "Konnte keine Kernel-Version finden. Breche ab."
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

  # EFI-Unterstützung
  mkdir -p "$ISO_DIR/EFI/BOOT"
  cp "$CHROOT_DIR/usr/lib/grub/x86_64-efi/monolithic/grubx64.efi" "$ISO_DIR/EFI/BOOT/BOOTx64.EFI" || true
  
  # Erstelle ISO-Metadaten
  mkdir -p "$ISO_DIR/.disk"
  echo "UbuntuFDE" > "$ISO_DIR/.disk/info"
  echo "full_cd/single" > "$ISO_DIR/.disk/cd_type"
  
  log info "System für ISO-Erstellung vorbereitet."
}

# ISO erstellen
create_iso() {
  log info "Erstelle ISO-Image..."
  
  # ISO-Erstellung
  if command -v xorriso &> /dev/null; then
    log info "Erstelle ISO mit xorriso..."
    xorriso -as mkisofs \
      -r -J -joliet-long \
      -V "$ISO_TITLE" \
      -o "$OUTPUT_DIR/$ISO_NAME" \
      "$ISO_DIR"
  elif command -v genisoimage &> /dev/null; then
    log info "Erstelle ISO mit genisoimage..."
    genisoimage -r -J -joliet-long \
      -V "$ISO_TITLE" \
      -o "$OUTPUT_DIR/$ISO_NAME" \
      "$ISO_DIR"
  else
    log error "Kein Tool zur ISO-Erstellung gefunden (xorriso oder genisoimage)."
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
  configure_sources
  configure_system
  create_network_setup
  create_main_script
  create_autostart
  cleanup_system
  prepare_for_iso
  create_iso
  cleanup
  
  log info "UbuntuFDE ISO-Erstellung abgeschlossen!"
  log info "Die neue ISO befindet sich hier: $OUTPUT_DIR"
}
#  STARTFUNKTION  #
###################


# Starte das Hauptprogramm
main "$@"