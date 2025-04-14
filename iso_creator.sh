#!/bin/bash
# UbuntuFDE ISO-Erstellungsskript
# Dieses Skript erstellt eine TinyCore-basierte ISO für die UbuntuFDE-Installation
# Version: 0.1

# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Verzeichnisse
WORK_DIR="$(pwd)/ubuntufde_build"
EXTRACT_DIR="${WORK_DIR}/extract"
ISO_DIR="${WORK_DIR}/iso"
NEW_ISO="${WORK_DIR}/ubuntufde.iso"
INITRD_DIR="${WORK_DIR}/initrd"

# URLs und Pfade
TINYCORE_URL="http://tinycorelinux.net/16.x/x86_64/release/CorePure64-16.0.iso"
TINYCORE_ISO="${WORK_DIR}/CorePure64-16.0.iso"

# --------------------------------
# Hilfsfunktionen
# --------------------------------

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

# Abhängigkeiten prüfen
check_dependencies() {
  log info "Prüfe Abhängigkeiten..."
  local deps=("wget" "xorriso" "gzip" "cpio" "mkisofs" "squashfs-tools")
  local missing=()
  
  for dep in "${deps[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
      missing+=("$dep")
    fi
  done
  
  if [ ${#missing[@]} -ne 0 ]; then
    log warn "Folgende Abhängigkeiten fehlen: ${missing[*]}"
    log info "Installiere fehlende Abhängigkeiten..."
    apt-get update
    apt-get install -y "${missing[@]}"
  else
    log info "Alle Abhängigkeiten sind installiert."
  fi
}

# Arbeitsverzeichnisse erstellen
setup_directories() {
  log info "Erstelle Arbeitsverzeichnisse..."
  
  mkdir -p "$WORK_DIR"
  mkdir -p "$EXTRACT_DIR"
  mkdir -p "$ISO_DIR"
  mkdir -p "$INITRD_DIR"
  
  log info "Arbeitsverzeichnisse bereit."
}

# --------------------------------
# Hauptfunktionen
# --------------------------------

# TinyCore herunterladen
download_tinycore() {
  log info "Lade TinyCore herunter..."
  
  if [ -f "$TINYCORE_ISO" ]; then
    log info "TinyCore ISO bereits heruntergeladen."
  else
    log info "Lade TinyCore ISO von $TINYCORE_URL herunter..."
    wget -q --show-progress "$TINYCORE_URL" -O "$TINYCORE_ISO"
    
    if [ $? -ne 0 ]; then
      log error "Download von TinyCore ISO fehlgeschlagen."
      exit 1
    fi
    
    log info "TinyCore ISO erfolgreich heruntergeladen."
  fi
}

# ISO extrahieren
extract_iso() {
  log info "Extrahiere TinyCore ISO..."
  
  if [ -d "${EXTRACT_DIR}" ] && [ "$(ls -A ${EXTRACT_DIR})" ]; then
    log warn "Extraktionsverzeichnis existiert bereits und ist nicht leer."
    read -p "Möchtest du das Verzeichnis leeren? (j/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Jj]$ ]]; then
      log info "Lösche Inhalt des Extraktionsverzeichnisses..."
      rm -rf "${EXTRACT_DIR:?}/"*
    else
      log info "Verzeichnis wird nicht geleert."
      return
    fi
  fi
  
  log info "Mounten der ISO und Kopieren der Dateien..."
  xorriso -osirrox on -indev "$TINYCORE_ISO" -extract / "$EXTRACT_DIR"
  
  if [ $? -ne 0 ]; then
    log error "Extraktion der ISO fehlgeschlagen."
    exit 1
  fi
  
  log info "ISO-Extraktion abgeschlossen."
  
  # Kopieren für weitere Modifikationen
  log info "Kopiere Dateien für ISO-Neuerstellung..."
  cp -r "$EXTRACT_DIR"/* "$ISO_DIR"
  
  log info "Extraktion und Kopieren erfolgreich abgeschlossen."
}

# Modifiziere die Boot-Konfiguration
modify_boot_config() {
  log info "Modifiziere Boot-Konfiguration..."
  
  # GRUB-Konfiguration anpassen
  GRUB_CFG="${ISO_DIR}/boot/grub/grub.cfg"
  
  if [ -f "$GRUB_CFG" ]; then
    log info "Passe GRUB-Timeout an (1 Sekunde)..."
    sed -i 's/timeout=.*/timeout=1/' "$GRUB_CFG"
    
    log info "Ändere GRUB-Titel zu UbuntuFDE..."
    sed -i 's/Core Pure 64/UbuntuFDE/g' "$GRUB_CFG"
    sed -i 's/Core Linux/UbuntuFDE/g' "$GRUB_CFG"
    sed -i 's/menuentry .*/menuentry "UbuntuFDE Installation" {/' "$GRUB_CFG"
  else
    log warn "GRUB-Konfigurationsdatei nicht gefunden: $GRUB_CFG"
  fi
  
  # Isolinux-Konfiguration anpassen, falls vorhanden
  ISOLINUX_CFG="${ISO_DIR}/boot/isolinux/isolinux.cfg"
  
  if [ -f "$ISOLINUX_CFG" ]; then
    log info "Passe ISOLINUX-Konfiguration an..."
    sed -i 's/timeout .*/timeout 10/' "$ISOLINUX_CFG"
    sed -i 's/MENU TITLE .*/MENU TITLE UbuntuFDE Installation/' "$ISOLINUX_CFG"
    sed -i 's/LABEL .*/LABEL ubuntufde/' "$ISOLINUX_CFG"
    sed -i 's/MENU LABEL .*/MENU LABEL UbuntuFDE Installation/' "$ISOLINUX_CFG"
  else
    log warn "ISOLINUX-Konfigurationsdatei nicht gefunden: $ISOLINUX_CFG"
  fi
  
  log info "Boot-Konfiguration wurde angepasst."
}

# Initrd extrahieren und modifizieren
extract_modify_initrd() {
  log info "Extrahiere initrd.gz..."
  
  # Finde initrd.gz
  INITRD_PATH=$(find "$ISO_DIR" -name "initrd.gz" | head -n 1)
  
  if [ -z "$INITRD_PATH" ]; then
    log error "initrd.gz nicht gefunden."
    exit 1
  fi
  
  log info "Gefundene initrd: $INITRD_PATH"
  
  # Erstelle ein Sicherungskopie
  cp "$INITRD_PATH" "${INITRD_PATH}.orig"
  
  # Entpacke initrd
  cd "$INITRD_DIR" || exit 1
  gzip -dc "$INITRD_PATH" | cpio -id
  
  if [ $? -ne 0 ]; then
    log error "Extraktion von initrd.gz fehlgeschlagen."
    exit 1
  fi
  
  log info "initrd.gz erfolgreich extrahiert."
}

# Erstelle Netzwerk-Setup-Skript
create_network_setup() {
  log info "Erstelle Netzwerk-Setup-Skript..."
  
  # Pfad zum Netzwerk-Skript
  NETWORK_SCRIPT="${INITRD_DIR}/opt/network_setup.sh"
  
  # Verzeichnis erstellen falls es noch nicht existiert
  mkdir -p "${INITRD_DIR}/opt"
  
  # Netzwerk-Setup-Skript erstellen
  cat > "$NETWORK_SCRIPT" << 'EOF'
#!/bin/sh
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

# Versuche DHCP für eine Schnittstelle
try_dhcp() {
  local iface=$1
  log info "Versuche DHCP auf Schnittstelle $iface..."
  ip link set $iface up
  udhcpc -i $iface -q -n -t 5
  
  if check_internet; then
    log info "DHCP erfolgreich für $iface, Internetverbindung hergestellt."
    return 0
  else
    log warn "DHCP für $iface erfolgreich, aber keine Internetverbindung."
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
      udhcpc -i "$selected_iface" -q
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
  
  # Alle Netzwerkschnittstellen aktivieren
  interfaces=($(get_network_interfaces))
  
  if [ ${#interfaces[@]} -eq 0 ]; then
    log error "Keine Netzwerkschnittstellen gefunden."
    return 1
  fi
  
  # Versuche erst DHCP auf allen Schnittstellen
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
  
  # Skript ausführbar machen
  chmod +x "$NETWORK_SCRIPT"
  
  log info "Netzwerk-Setup-Skript erstellt."
}

# Sprachunterstützung erstellen
create_language_support() {
  log info "Erstelle Sprachunterstützungsdateien..."
  
  # Verzeichnis für Sprachdateien
  LANG_DIR="${INITRD_DIR}/opt/lang"
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
add_keyboard_layouts() {
  log info "Füge Tastaturlayouts hinzu..."
  
  # Verzeichnis für Tastaturlayouts in TinyCore
  KEYBOARD_DIR="${INITRD_DIR}/opt/kbd"
  mkdir -p "$KEYBOARD_DIR"
  
  # Verzeichnis für XKB-Layouts
  XKB_DIR="${KEYBOARD_DIR}/xkb/symbols"
  mkdir -p "$XKB_DIR"
  
  # Konfigurationsdatei für die Tastaturlayouts erstellen
  cat > "${KEYBOARD_DIR}/keyboard.conf" << 'EOF'
# Tastaturlayout-Konfiguration
# Format: layout_id,xkb_layout,xkb_variant
de_de,de,
de_ch,ch,de_CH
de_at,at,
en_us,us,
EOF
  
  # Kopiere die XKB-Layouts aus dem Host-System
  if [ -d "/usr/share/X11/xkb/symbols" ]; then
    log info "Kopiere XKB-Layout-Dateien aus dem Host-System..."
    
    # Kopiere die benötigten Layoutdateien
    cp -f "/usr/share/X11/xkb/symbols/de" "$XKB_DIR/" || log warn "Konnte deutsche Tastaturlayout-Datei nicht kopieren."
    cp -f "/usr/share/X11/xkb/symbols/ch" "$XKB_DIR/" || log warn "Konnte schweizer Tastaturlayout-Datei nicht kopieren."
    cp -f "/usr/share/X11/xkb/symbols/at" "$XKB_DIR/" || log warn "Konnte österreichische Tastaturlayout-Datei nicht kopieren."
    cp -f "/usr/share/X11/xkb/symbols/us" "$XKB_DIR/" || log warn "Konnte US-Tastaturlayout-Datei nicht kopieren."
    
    # Kopiere notwendige gemeinsame Dateien
    cp -f "/usr/share/X11/xkb/symbols/inet" "$XKB_DIR/" || log warn "Konnte inet-Symboldatei nicht kopieren."
    cp -f "/usr/share/X11/xkb/symbols/level3" "$XKB_DIR/" || log warn "Konnte level3-Symboldatei nicht kopieren."
    cp -f "/usr/share/X11/xkb/symbols/level5" "$XKB_DIR/" || log warn "Konnte level5-Symboldatei nicht kopieren."
    cp -f "/usr/share/X11/xkb/symbols/compose" "$XKB_DIR/" || log warn "Konnte compose-Symboldatei nicht kopieren."
    
    log info "XKB-Layout-Dateien erfolgreich kopiert."
  else
    log warn "XKB-Layoutverzeichnis nicht gefunden. Fallback zu traditionellen Keymaps."
    
    # Fallback: Verwende traditionelle Console-Keymaps, falls XKB nicht verfügbar ist
    if [ -d "/usr/share/kbd/keymaps" ]; then
      log info "Kopiere traditionelle Keymap-Dateien aus dem Host-System..."
      mkdir -p "${KEYBOARD_DIR}/keymaps"
      cp -f /usr/share/kbd/keymaps/i386/qwertz/de-latin1.map.gz "${KEYBOARD_DIR}/keymaps/" || true
      cp -f /usr/share/kbd/keymaps/i386/qwertz/de_CH-latin1.map.gz "${KEYBOARD_DIR}/keymaps/" || true
      cp -f /usr/share/kbd/keymaps/i386/qwerty/us.map.gz "${KEYBOARD_DIR}/keymaps/" || true
    else
      log warn "Keine Keymap-Verzeichnisse gefunden. Tastaturlayouts werden möglicherweise nicht korrekt funktionieren."
    fi
  fi
  
  # Erstelle ein einfaches Skript zum Setzen des XKB-Layouts
  cat > "${KEYBOARD_DIR}/set-xkb-layout.sh" << 'EOF'
#!/bin/sh
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
      loadkeys de_CH-latin1 || echo "Fehler beim Setzen des Konsolen-Layouts"
      ;;
    "at")
      loadkeys de-latin1 || echo "Fehler beim Setzen des Konsolen-Layouts"
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
  
  log info "Tastaturlayouts und Konfigurationsskript hinzugefügt."
}

# Erstelle Haupt-Startskript
create_main_script() {
  log info "Erstelle Hauptstartskript..."
  
  # Pfad zum Hauptskript
  MAIN_SCRIPT="${INITRD_DIR}/opt/start_installation.sh"
  
  # Erstelle das Skript
  cat > "$MAIN_SCRIPT" << 'EOF'
#!/bin/sh
# UbuntuFDE Hauptstartskript
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
INSTALLATION_URL="https://indianfire.ch/fde"

# Pfade
LANG_DIR="/opt/lang"
KEYBOARD_DIR="/opt/kbd"

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

# Lade Sprachdefinitionen
load_language() {
  local lang_file="$LANG_DIR/$SELECTED_LANGUAGE.conf"
  if [ -f "$lang_file" ]; then
    source "$lang_file"
    log info "Sprache geladen: $LANGUAGE_NAME"
  else
    log error "Sprachdatei nicht gefunden: $lang_file"
    # Fallback zu Englisch
    SELECTED_LANGUAGE="en_US"
    source "$LANG_DIR/en_US.conf"
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
  
  case ${choice:-1} in
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
  echo "$KEYBOARD_PROMPT"
  echo ""
  echo "1) $KEYBOARD_DE_DE [Standard/Default]"
  echo "2) $KEYBOARD_DE_CH"
  echo "3) $KEYBOARD_DE_AT"
  echo "4) $KEYBOARD_EN_US"
  echo ""
  read -p "Auswahl/Selection [1]: " choice
  
  case ${choice:-1} in
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
  local kbd_conf="$KEYBOARD_DIR/keyboard.conf"
  if [ -f "$kbd_conf" ]; then
    local xkb_layout=$(grep "^$SELECTED_KEYBOARD," "$kbd_conf" | cut -d, -f2)
    local xkb_variant=$(grep "^$SELECTED_KEYBOARD," "$kbd_conf" | cut -d, -f3)
    
    if [ -n "$xkb_layout" ]; then
      log info "Setze Tastaturlayout: $xkb_layout $([ -n "$xkb_variant" ] && echo "Variante: $xkb_variant")"
      
      # Verwende das Skript, um das Tastaturlayout zu setzen
      if [ -f "$KEYBOARD_DIR/set-xkb-layout.sh" ]; then
        "$KEYBOARD_DIR/set-xkb-layout.sh" "$xkb_layout" "$xkb_variant"
      else
        # Fallback: Versuche direkt die Befehle auszuführen
        if command -v setxkbmap >/dev/null 2>&1 && [ -n "$DISPLAY" ]; then
          # Grafische Umgebung mit X11
          if [ -n "$xkb_variant" ]; then
            setxkbmap -layout "$xkb_layout" -variant "$xkb_variant" 2>/dev/null || 
              log warn "Konnte X-Tastaturlayout nicht setzen: $xkb_layout ($xkb_variant)"
          else
            setxkbmap -layout "$xkb_layout" 2>/dev/null || 
              log warn "Konnte X-Tastaturlayout nicht setzen: $xkb_layout"
          fi
        elif command -v loadkeys >/dev/null 2>&1; then
          # Konsole/Textmodus
          case "$xkb_layout" in
            "de")
              loadkeys de-latin1 2>/dev/null || loadkeys de 2>/dev/null || 
                log warn "Konnte Konsolen-Tastaturlayout nicht setzen: de"
              ;;
            "ch")
              loadkeys de_CH-latin1 2>/dev/null || loadkeys ch 2>/dev/null || 
                log warn "Konnte Konsolen-Tastaturlayout nicht setzen: ch"
              ;;
            "at")
              loadkeys de-latin1 2>/dev/null || loadkeys at 2>/dev/null || 
                log warn "Konnte Konsolen-Tastaturlayout nicht setzen: at"
              ;;
            "us")
              loadkeys us 2>/dev/null || 
                log warn "Konnte Konsolen-Tastaturlayout nicht setzen: us"
              ;;
            *)
              log warn "Unbekanntes Layout: $xkb_layout"
              ;;
          esac
        else
          log warn "Weder loadkeys noch setxkbmap gefunden. Tastaturlayout konnte nicht gesetzt werden."
        fi
      fi
    else
      log error "Tastaturlayout nicht gefunden: $SELECTED_KEYBOARD"
    fi
  else
    log error "Tastaturkonfiguration nicht gefunden: $kbd_conf"
  fi
}

# Netzwerkverbindung einrichten
setup_network() {
  clear
  echo "==============================================="
  echo "           UbuntuFDE Installation"
  echo "==============================================="
  echo ""
  echo "$NETWORK_SETUP"
  echo ""
  
  # Führe das Netzwerk-Setup-Skript aus
  sh /opt/network_setup.sh
}

# Installationsskript herunterladen und ausführen
download_and_run() {
  # Installationsskript direkt herunterladen ohne weitere Benachrichtigungen
  wget -O /tmp/install.sh "$INSTALLATION_URL"
  
  if [ $? -eq 0 ]; then
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
  
  # Skript ausführbar machen
  chmod +x "$MAIN_SCRIPT"
  
  log info "Hauptstartskript erstellt."
}

# Modifiziere das Init-Skript in initrd
modify_init() {
  log info "Modifiziere Init-Skript..."
  
  # Pfad zum Init-Skript
  INIT_SCRIPT="${INITRD_DIR}/init"
  
  if [ ! -f "$INIT_SCRIPT" ]; then
    log error "Init-Skript nicht gefunden: $INIT_SCRIPT"
    exit 1
  fi
  
  # Sicherungskopie erstellen
  cp "$INIT_SCRIPT" "${INIT_SCRIPT}.orig"
  
  # Finde die richtige Stelle zum Einfügen unseres Skriptes (vor 'exec')
  EXEC_LINE=$(grep -n "exec" "$INIT_SCRIPT" | head -1 | cut -d: -f1)
  
  if [ -z "$EXEC_LINE" ]; then
    log warn "Konnte 'exec' nicht im Init-Skript finden. Füge am Ende ein."
    # Füge Aufruf am Ende des Skripts ein
    echo -e "\n# UbuntuFDE Installation starten\n/opt/start_installation.sh\n" >> "$INIT_SCRIPT"
  else
    # Teile das Skript
    head -n $((EXEC_LINE-1)) "$INIT_SCRIPT" > "${INIT_SCRIPT}.tmp"
    echo -e "\n# UbuntuFDE Installation starten\n/opt/start_installation.sh\n" >> "${INIT_SCRIPT}.tmp"
    tail -n +$EXEC_LINE "$INIT_SCRIPT" >> "${INIT_SCRIPT}.tmp"
    mv "${INIT_SCRIPT}.tmp" "$INIT_SCRIPT"
  fi
  
  # Stelle sicher, dass das Skript ausführbar ist
  chmod +x "$INIT_SCRIPT"
  
  log info "Init-Skript erfolgreich modifiziert."
}

# Aktualisiere initrd
update_initrd() {
  log info "Erstelle neue initrd.gz..."
  
  # Finde initrd.gz
  INITRD_PATH=$(find "$ISO_DIR" -name "initrd.gz" | head -n 1)
  
  if [ -z "$INITRD_PATH" ]; then
    log error "initrd.gz nicht gefunden."
    exit 1
  fi
  
  # Erstelle neue initrd
  cd "$INITRD_DIR" || exit 1
  find . | cpio -o -H newc | gzip -9 > "$INITRD_PATH"
  
  if [ $? -ne 0 ]; then
    log error "Erstellung der neuen initrd.gz fehlgeschlagen."
    exit 1
  fi
  
  log info "Neue initrd.gz erfolgreich erstellt."
}

# UbuntuFDE Branding
apply_branding() {
  log info "Wende UbuntuFDE Branding an..."
  
  # Ersetzen von TinyCore-Branding in Textdateien
  find "$ISO_DIR" -type f -name "*.txt" -o -name "*.cfg" -o -name "*.menu" | \
  while read file; do
    sed -i 's/Tiny Core/UbuntuFDE/g' "$file"
    sed -i 's/TinyCore/UbuntuFDE/g' "$file"
    sed -i 's/CorePure/UbuntuFDE/g' "$file"
  done
  
  # Wenn ein Logo vorhanden ist, könnte es ersetzt werden
  # Dies würde zusätzliche Grafikbearbeitung erfordern
  
  log info "UbuntuFDE Branding angewendet."
}

# ISO erstellen
create_iso() {
  log info "Erstelle neue ISO..."
  
  # ISO-Optionen
  ISO_LABEL="UbuntuFDE"
  
  # Erstelle ISO mit xorriso oder genisoimage/mkisofs
  if command -v xorriso &> /dev/null; then
    xorriso -as mkisofs \
      -l -J -R \
      -V "$ISO_LABEL" \
      -no-emul-boot -boot-load-size 4 -boot-info-table \
      -b boot/isolinux/isolinux.bin \
      -c boot/isolinux/boot.cat \
      -isohybrid-mbr "$ISO_DIR/boot/isolinux/isohdpfx.bin" \
      -o "$NEW_ISO" \
      "$ISO_DIR"
  elif command -v mkisofs &> /dev/null; then
    mkisofs -l -J -R \
      -V "$ISO_LABEL" \
      -no-emul-boot -boot-load-size 4 -boot-info-table \
      -b boot/isolinux/isolinux.bin \
      -c boot/isolinux/boot.cat \
      -o "$NEW_ISO" \
      "$ISO_DIR"
    
    # Mache ISO hybrid, falls isohybrid verfügbar
    if command -v isohybrid &> /dev/null; then
      isohybrid "$NEW_ISO"
    fi
  else
    log error "Weder xorriso noch mkisofs gefunden. ISO-Erstellung fehlgeschlagen."
    exit 1
  fi
  
  if [ $? -ne 0 ]; then
    log error "ISO-Erstellung fehlgeschlagen."
    exit 1
  fi
  
  log info "Neue ISO erfolgreich erstellt: $NEW_ISO"
  log info "ISO-Größe: $(du -h "$NEW_ISO" | cut -f1)"
}

# Aufräumen
cleanup() {
  log info "Räume temporäre Dateien auf..."
  
  read -p "Möchtest du die temporären Dateien aufräumen? (j/n): " -n 1 -r
  echo
  
  if [[ $REPLY =~ ^[Jj]$ ]]; then
    log info "Lösche temporäre Dateien..."
    rm -rf "$EXTRACT_DIR" "$INITRD_DIR"
    log info "Temporäre Dateien gelöscht."
  else
    log info "Temporäre Dateien wurden beibehalten."
  fi
}

# --------------------------------
# Hauptprogramm
# --------------------------------
main() {
  log info "Starte UbuntuFDE ISO-Erstellung..."
  
  # Prüfe Root-Rechte
  if [ "$(id -u)" -ne 0 ]; then
    log error "Dieses Skript benötigt Root-Rechte. Bitte mit sudo ausführen."
    exit 1
  fi
  
  # Schritte ausführen
  check_dependencies
  setup_directories
  download_tinycore
  extract_iso
  modify_boot_config
  extract_modify_initrd
  create_network_setup
  create_language_support
  add_keyboard_layouts
  create_main_script
  modify_init
  update_initrd
  apply_branding
  create_iso
  cleanup
  
  log info "UbuntuFDE ISO-Erstellung abgeschlossen!"
  log info "Die neue ISO befindet sich hier: $NEW_ISO"
}

# Starte das Hauptprogramm
main "$@"