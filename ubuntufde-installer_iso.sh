#!/bin/bash

# UbuntuFDE ISO-Erstellungsskript
# Dieses Skript erstellt eine bootfähige ISO für UbuntuFDE

# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funktion zum Anzeigen von Schritten
log_step() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Funktion zum Anzeigen von Erfolgen
log_success() {
    echo -e "${GREEN}$1${NC}"
}

# Funktion zum Anzeigen von Fehlern
log_error() {
    echo -e "${RED}FEHLER: $1${NC}"
    exit 1
}

# Funktion zum Anzeigen von Warnungen
log_warning() {
    echo -e "${YELLOW}WARNUNG: $1${NC}"
}

# Prüfe, ob das Skript als root läuft
if [ "$(id -u)" -ne 0 ]; then
    log_error "Dieses Skript muss als root ausgeführt werden!"
fi

# Arbeitsverzeichnis definieren
WORK_DIR=~/ubuntufde_iso
mkdir -p $WORK_DIR
cd $WORK_DIR || log_error "Konnte nicht in das Arbeitsverzeichnis wechseln"

# 1. Benötigte Pakete installieren
log_step "Installiere benötigte Pakete"
apt update -y || log_error "Konnte Paketquellen nicht aktualisieren"
apt install -y xorriso isolinux syslinux-common squashfs-tools wget curl mtools grub-pc-bin grub-efi-amd64-bin dosfstools \
    || log_error "Konnte benötigte Pakete nicht installieren"
log_success "Pakete erfolgreich installiert"

# 2. Arbeitsverzeichnis vorbereiten
log_step "Bereite Arbeitsverzeichnis vor"
mkdir -p {boot/{grub,syslinux},isolinux,efi,extract}
log_success "Verzeichnisstruktur erstellt"

# 3. Alpine Linux Minirootfs herunterladen und entpacken
log_step "Lade Alpine Linux Minirootfs herunter"
cd extract || log_error "Konnte nicht in extract-Verzeichnis wechseln"
wget https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-minirootfs-3.21.3-x86_64.tar.gz \
    || log_error "Konnte Alpine Linux Minirootfs nicht herunterladen"
mkdir -p rootfs || log_error "Konnte rootfs-Verzeichnis nicht erstellen"
tar -xzf alpine-minirootfs-3.21.3-x86_64.tar.gz -C rootfs \
    || log_error "Konnte Alpine Linux Minirootfs nicht entpacken"
log_success "Alpine Linux Minirootfs heruntergeladen und entpackt"

# 4. Sprachdateien für Deutsch und Englisch hinzufügen
log_step "Füge Sprachdateien hinzu"
mkdir -p rootfs/etc/keyboard-layouts
cat > rootfs/etc/keyboard-layouts/de-DE.conf << 'EOF'
KEYMAP=de-latin1
EOF

cat > rootfs/etc/keyboard-layouts/de-CH.conf << 'EOF'
KEYMAP=de_CH-latin1
EOF

cat > rootfs/etc/keyboard-layouts/de-AT.conf << 'EOF'
KEYMAP=de-latin1
EOF

cat > rootfs/etc/keyboard-layouts/en-US.conf << 'EOF'
KEYMAP=us
EOF

mkdir -p rootfs/etc/locale
echo "de_DE.UTF-8 UTF-8" > rootfs/etc/locale/de_DE
echo "en_US.UTF-8 UTF-8" > rootfs/etc/locale/en_US
log_success "Sprachdateien hinzugefügt"

# 5. Startup-Skript erstellen
log_step "Erstelle Startup-Skript"
cat > rootfs/startup.sh << 'EOF'
#!/bin/sh

# Farben für die Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

clear
echo -e "${BLUE}=== UbuntuFDE Installationsumgebung ===${NC}"
echo

# Sprache auswählen
echo -e "${GREEN}Wähle deine Anzeigesprache / Choose display language:${NC}"
echo "1) Deutsch (Standard/Default)"
echo "2) English"
read -p "Auswahl/Choice [1]: " lang_choice
lang_choice=${lang_choice:-1}

if [ "$lang_choice" = "1" ]; then
    LANG="de_DE.UTF-8"
    setup_lang="Deutsch"
else
    LANG="en_US.UTF-8"
    setup_lang="English"
fi

export LANG

# Tastaturlayout auswählen
if [ "$setup_lang" = "Deutsch" ]; then
    echo -e "\n${GREEN}Wähle dein Tastaturlayout:${NC}"
    echo "1) Deutsch - Deutschland (Standard)"
    echo "2) Deutsch - Schweiz"
    echo "3) Deutsch - Österreich"
    echo "4) Englisch - US"
    read -p "Auswahl [1]: " keyboard_choice
else
    echo -e "\n${GREEN}Choose your keyboard layout:${NC}"
    echo "1) German - Germany"
    echo "2) German - Switzerland"
    echo "3) German - Austria"
    echo "4) English - US (Default)"
    read -p "Choice [4]: " keyboard_choice
fi

keyboard_choice=${keyboard_choice:-1}
if [ "$setup_lang" = "English" ]; then
    keyboard_choice=${keyboard_choice:-4}
fi

case "$keyboard_choice" in
    1) KEYMAP="de-DE.conf" ;;
    2) KEYMAP="de-CH.conf" ;;
    3) KEYMAP="de-AT.conf" ;;
    4) KEYMAP="en-US.conf" ;;
    *) KEYMAP="de-DE.conf" ;;
esac

# Tastaturlayout anwenden
if [ -f "/etc/keyboard-layouts/$KEYMAP" ]; then
    . "/etc/keyboard-layouts/$KEYMAP"
    loadkeys $KEYMAP
    if [ "$setup_lang" = "Deutsch" ]; then
        echo -e "${GREEN}Tastaturlayout wurde angewendet.${NC}"
    else
        echo -e "${GREEN}Keyboard layout applied.${NC}"
    fi
else
    if [ "$setup_lang" = "Deutsch" ]; then
        echo -e "${RED}Fehler: Tastaturlayout-Datei nicht gefunden.${NC}"
    else
        echo -e "${RED}Error: Keyboard layout file not found.${NC}"
    fi
fi

# Netzwerkverbindung herstellen
if [ "$setup_lang" = "Deutsch" ]; then
    echo -e "\n${GREEN}Netzwerkverbindung wird hergestellt...${NC}"
else
    echo -e "\n${GREEN}Establishing network connection...${NC}"
fi

# Funktion zum Prüfen der Internetverbindung
check_internet() {
    ping -c 1 8.8.8.8 > /dev/null 2>&1
    return $?
}

# Funktion zum Scannen des Netzwerks und Konfigurieren
configure_network() {
    # Liste verfügbarer Netzwerkadapter
    adapters=$(ip link | grep -E '^[0-9]+:' | grep -v lo | cut -d: -f2 | tr -d ' ')
    
    for adapter in $adapters; do
        if [ "$setup_lang" = "Deutsch" ]; then
            echo -e "${YELLOW}Versuche Verbindung über $adapter...${NC}"
        else
            echo -e "${YELLOW}Trying connection via $adapter...${NC}"
        fi
        
        # Versuche DHCP
        ip link set $adapter up
        udhcpc -i $adapter -q -n -t 5
        
        # Prüfe ob Internet funktioniert
        if check_internet; then
            if [ "$setup_lang" = "Deutsch" ]; then
                echo -e "${GREEN}Verbindung erfolgreich über DHCP auf $adapter.${NC}"
            else
                echo -e "${GREEN}Connection successful via DHCP on $adapter.${NC}"
            fi
            return 0
        fi
        
        # Wenn DHCP fehlschlägt, versuche gängige statische IPs
        common_ips=("192.168.1.100" "192.168.0.100" "10.0.0.100" "172.16.0.100")
        common_gateways=("192.168.1.1" "192.168.0.1" "10.0.0.1" "172.16.0.1")
        common_netmasks=("255.255.255.0" "255.255.255.0" "255.255.255.0" "255.255.255.0")
        
        for i in {0..3}; do
            if [ "$setup_lang" = "Deutsch" ]; then
                echo -e "${YELLOW}Versuche statische IP: ${common_ips[$i]}${NC}"
            else
                echo -e "${YELLOW}Trying static IP: ${common_ips[$i]}${NC}"
            fi
            
            ip addr flush dev $adapter
            ip addr add ${common_ips[$i]}/24 dev $adapter
            ip route add default via ${common_gateways[$i]}
            
            echo "nameserver 8.8.8.8" > /etc/resolv.conf
            echo "nameserver 1.1.1.1" >> /etc/resolv.conf
            
            # Prüfe ob Internet funktioniert
            if check_internet; then
                if [ "$setup_lang" = "Deutsch" ]; then
                    echo -e "${GREEN}Verbindung erfolgreich mit statischer IP auf $adapter.${NC}"
                else
                    echo -e "${GREEN}Connection successful with static IP on $adapter.${NC}"
                fi
                return 0
            fi
        done
    done
    
    # Wenn automatische Konfiguration fehlschlägt, manuelle Eingabe anbieten
    if [ "$setup_lang" = "Deutsch" ]; then
        echo -e "${RED}Automatische Netzwerkkonfiguration fehlgeschlagen.${NC}"
        echo -e "${YELLOW}Verfügbare Netzwerkadapter:${NC}"
    else
        echo -e "${RED}Automatic network configuration failed.${NC}"
        echo -e "${YELLOW}Available network adapters:${NC}"
    fi
    
    ip link | grep -E '^[0-9]+:' | grep -v lo | cut -d: -f2 | tr -d ' '
    
    if [ "$setup_lang" = "Deutsch" ]; then
        read -p "Netzwerkadapter wählen: " manual_adapter
        read -p "IP-Adresse (z.B. 192.168.1.100): " manual_ip
        read -p "Netzmaske (z.B. 255.255.255.0): " manual_netmask
        read -p "Gateway (z.B. 192.168.1.1): " manual_gateway
    else
        read -p "Select network adapter: " manual_adapter
        read -p "IP address (e.g. 192.168.1.100): " manual_ip
        read -p "Netmask (e.g. 255.255.255.0): " manual_netmask
        read -p "Gateway (e.g. 192.168.1.1): " manual_gateway
    fi
    
    # Manuelle Konfiguration anwenden
    ip addr flush dev $manual_adapter
    ip addr add $manual_ip/$manual_netmask dev $manual_adapter
    ip route add default via $manual_gateway
    
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
    echo "nameserver 1.1.1.1" >> /etc/resolv.conf
    
    # Prüfe ob Internet funktioniert
    if check_internet; then
        if [ "$setup_lang" = "Deutsch" ]; then
            echo -e "${GREEN}Verbindung erfolgreich mit manuellen Einstellungen.${NC}"
        else
            echo -e "${GREEN}Connection successful with manual settings.${NC}"
        fi
        return 0
    else
        if [ "$setup_lang" = "Deutsch" ]; then
            echo -e "${RED}Verbindung fehlgeschlagen. Bitte überprüfe deine Einstellungen.${NC}"
        else
            echo -e "${RED}Connection failed. Please check your settings.${NC}"
        fi
        return 1
    fi
}

# Netzwerk konfigurieren
configure_network

# Installationsskript herunterladen und ausführen
if check_internet; then
    if [ "$setup_lang" = "Deutsch" ]; then
        echo -e "\n${GREEN}Installationsskript wird heruntergeladen...${NC}"
    else
        echo -e "\n${GREEN}Downloading installation script...${NC}"
    fi
    
    wget -O /tmp/install.sh indianfire.ch/fde
    
    if [ -f "/tmp/install.sh" ]; then
        if [ "$setup_lang" = "Deutsch" ]; then
            echo -e "${GREEN}Installationsskript wird ausgeführt...${NC}"
        else
            echo -e "${GREEN}Running installation script...${NC}"
        fi
        chmod +x /tmp/install.sh
        sh /tmp/install.sh
    else
        if [ "$setup_lang" = "Deutsch" ]; then
            echo -e "${RED}Fehler beim Herunterladen des Installationsskripts.${NC}"
        else
            echo -e "${RED}Error downloading installation script.${NC}"
        fi
    fi
else
    if [ "$setup_lang" = "Deutsch" ]; then
        echo -e "${RED}Keine Internetverbindung verfügbar. Installationsskript kann nicht heruntergeladen werden.${NC}"
    else
        echo -e "${RED}No internet connection available. Cannot download installation script.${NC}"
    fi
fi

# Fallback-Shell, falls etwas schief geht
if [ "$setup_lang" = "Deutsch" ]; then
    echo -e "\n${YELLOW}Falls Probleme auftreten, kannst du diese Shell nutzen.${NC}"
else
    echo -e "\n${YELLOW}If problems occur, you can use this shell.${NC}"
fi

/bin/sh
EOF

chmod +x rootfs/startup.sh
log_success "Startup-Skript erstellt"

# 6. Bootloader für BIOS und UEFI konfigurieren
log_step "Konfiguriere Bootloader für BIOS und UEFI"

# SYSLINUX für Legacy BIOS
cd $WORK_DIR || log_error "Konnte nicht in Arbeitsverzeichnis zurückkehren"
mkdir -p isolinux
cp /usr/lib/ISOLINUX/isolinux.bin isolinux/ || log_error "Konnte isolinux.bin nicht kopieren"
cp /usr/lib/syslinux/modules/bios/*.c32 isolinux/ || log_error "Konnte BIOS-Module nicht kopieren"

cat > isolinux/isolinux.cfg << 'EOF'
DEFAULT ubuntufde
LABEL ubuntufde
  MENU LABEL UbuntuFDE Installer
  KERNEL /boot/vmlinuz
  APPEND initrd=/boot/initfs.gz quiet console=tty0 modules=loop,squashfs,sd-mod,usb-storage
TIMEOUT 20
EOF

# GRUB für UEFI
mkdir -p boot/grub
cat > boot/grub/grub.cfg << 'EOF'
set default=0
set timeout=5
set color_normal=white/black
set menu_color_normal=white/black
set menu_color_highlight=black/white

menuentry "UbuntuFDE Installer" {
    linux /boot/vmlinuz quiet console=tty0 modules=loop,squashfs,sd-mod,usb-storage
    initrd /boot/initfs.gz
}
EOF
log_success "Bootloader konfiguriert"

# 7. Alpine Linux Kernel und Initramfs herunterladen
log_step "Lade Alpine Linux Kernel und Initramfs herunter"
mkdir -p boot
wget https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/netboot/vmlinuz-lts -O boot/vmlinuz \
    || log_error "Konnte vmlinuz nicht herunterladen"
wget https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/netboot/initramfs-lts -O boot/initfs.gz \
    || log_error "Konnte initfs.gz nicht herunterladen"
log_success "Kernel und Initramfs heruntergeladen"

# 8. Rootfs-Anpassungen für den Boot
log_step "Bereite Rootfs für Boot vor"
mkdir -p extract/rootfs/boot

cat > extract/rootfs/boot/mount-boot.sh << 'EOF'
#!/bin/sh
# Finde den Kernel und das initramfs
mount -o ro /dev/cdrom /media/cdrom
if [ -f /media/cdrom/boot/vmlinuz ]; then
    cp /media/cdrom/boot/vmlinuz /boot/
    cp /media/cdrom/boot/initfs.gz /boot/
    echo "Kernel und initramfs kopiert"
fi
EOF
chmod +x extract/rootfs/boot/mount-boot.sh

# Squashfs des rootfs erstellen
mksquashfs extract/rootfs/ boot/rootfs.squashfs -comp xz || log_error "Konnte Squashfs nicht erstellen"
log_success "Rootfs für Boot vorbereitet und Squashfs erstellt"

# 9. UEFI-Bootfähige ISO erstellen
log_step "Erstelle UEFI-bootfähige ISO"

# EFI-Boot-Image erstellen
mkdir -p efi/boot
grub-mkstandalone -O x86_64-efi -o efi/boot/bootx64.efi "boot/grub/grub.cfg=boot/grub/grub.cfg" \
    || log_error "Konnte EFI-Boot-Image nicht erstellen"

# FAT-Image für EFI erstellen (16MB statt 4MB für mehr Platz)
dd if=/dev/zero of=efi.img bs=1M count=16 || log_error "Konnte efi.img nicht erstellen"
mkfs.vfat efi.img || log_error "Konnte efi.img nicht formatieren"
mmd -i efi.img ::/EFI || log_error "Konnte EFI-Verzeichnis nicht erstellen"
mmd -i efi.img ::/EFI/BOOT || log_error "Konnte EFI/BOOT-Verzeichnis nicht erstellen"
mcopy -i efi.img efi/boot/bootx64.efi ::/EFI/BOOT/ || log_error "Konnte bootx64.efi nicht kopieren"

# Überprüfen, ob efi.img existiert und lesbar ist
if [ ! -f "efi.img" ]; then
    log_error "efi.img wurde nicht erstellt oder ist nicht lesbar!"
fi

# Info ausgeben
ls -la efi.img
file efi.img

# ISO erstellen
xorriso -as mkisofs \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -c isolinux/boot.cat \
    -b isolinux/isolinux.bin \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-alt-boot \
    -e efi.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -volid "UBUNTUFDE" \
    -o ubuntufde-installer.iso \
    . || log_error "Konnte ISO nicht erstellen"

log_success "ISO erfolgreich erstellt: $WORK_DIR/ubuntufde-installer.iso"

# 10. Zusammenfassung anzeigen
echo -e "${GREEN}=== ISO-Erstellung abgeschlossen ===${NC}"
echo "ISO-Datei: $WORK_DIR/ubuntufde-installer.iso"
ls -lh ubuntufde-installer.iso

exit 0
