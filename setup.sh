# System-Setup in chroot
log_progress "Konfiguriere System in chroot-Umgebung..."
cat > /mnt/ubuntu/setup.sh <<MAINEOF
#!/bin/bash
set -e

set -x  # Detailliertes Debug-Logging aktivieren
exec > >(tee -a /var/log/setup-debug.log) 2>&1

export DEBIAN_FRONTEND=noninteractive

# Zeitzone setzen
if [ -n "${TIMEZONE}" ]; then
    ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
else
    ln -sf /usr/share/zoneinfo/Europe/Zurich /etc/localtime
fi

# GPG-Schlüssel für lokales Repository importieren
if [ ! -f "/etc/apt/trusted.gpg.d/local-mirror.gpg" ]; then
    curl -fsSL http://192.168.56.120/repo-key.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/local-mirror.gpg
fi

# Quellen einrichten
cat > /etc/apt/sources.list <<SOURCES
#deb http://192.168.56.120/ubuntu/ oracular main restricted universe multiverse
#deb http://192.168.56.120/ubuntu/ oracular-updates main restricted universe multiverse
#deb http://192.168.56.120/ubuntu/ oracular-security main restricted universe multiverse
#deb http://192.168.56.120/ubuntu/ oracular-backports main restricted universe multiverse

deb https://archive.ubuntu.com/ubuntu/ oracular main restricted universe multiverse
deb https://archive.ubuntu.com/ubuntu/ oracular-updates main restricted  universe multiverse
deb https://archive.ubuntu.com/ubuntu/ oracular-security main restricted universe multiverse
deb https://archive.ubuntu.com/ubuntu/ oracular-backports main restricted universe multiverse
SOURCES

# Automatische Updates konfigurieren
cat > /etc/apt/apt.conf.d/20auto-upgrades <<AUTOUPDATE
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "${UPDATE_OPTION}";
AUTOUPDATE

# Systemaktualisierung durchführen
apt-get update
apt-get dist-upgrade -y

# Grundlegende Tools installieren
TOOLS=(
    ${KERNEL_PACKAGES}
    shim-signed timeshift bleachbit coreutils stacer
    fastfetch gparted vlc deluge ufw zram-tools nala jq
)

apt-get install -y --no-install-recommends "${TOOLS[@]}"

# Notwendige Pakete installieren 
echo "Installiere Basis-Pakete..."
KERNEL_PACKAGES=""
if [ "${KERNEL_TYPE}" = "standard" ]; then
    KERNEL_PACKAGES="linux-image-generic linux-headers-generic"
elif [ "${KERNEL_TYPE}" = "lowlatency" ]; then
    KERNEL_PACKAGES="linux-image-lowlatency linux-headers-lowlatency"
fi

# Liquorix-Kernel installieren wenn gewählt
if [ "${KERNEL_TYPE}" = "liquorix" ]; then
    apt-get install -y apt-transport-https
    echo "deb http://liquorix.net/debian stable main" > /etc/apt/sources.list.d/liquorix.list
    mkdir -p /etc/apt/keyrings
    curl -s 'https://liquorix.net/linux-liquorix-keyring.gpg' | gpg --dearmor -o /etc/apt/keyrings/liquorix-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/liquorix-keyring.gpg] https://liquorix.net/debian stable main" | tee /etc/apt/sources.list.d/liquorix.list
    # apt-get update hier notwendig, da neue Paketquelle hinzugefügt wurde
    apt-get update
    apt-get install -y linux-image-liquorix-amd64 linux-headers-liquorix-amd64
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
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash nomodeset loglevel=3 rd.systemd.show_status=auto rd.udev.log_level=3"
GRUB_CMDLINE_LINUX=""
GRUB_ENABLE_CRYPTODISK=y
GRUB_GFXMODE=1024x768
GRUBCFG

# GRUB Konfigurationsdatei-Rechte setzen
chmod 644 /etc/default/grub

# GRUB Hauptkonfiguration aktualisieren
sed -i 's/GRUB_ENABLE_CRYPTODISK=.*/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub

# Initramfs aktualisieren und GRUB installieren
update-initramfs -u -k all
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck
update-grub

# Schlüsseldatei für automatische Entschlüsselung
echo "KEYFILE_PATTERN=/etc/luks/*.keyfile" >> /etc/cryptsetup-initramfs/conf-hook
echo "CRYPTSETUP=y" >> /etc/cryptsetup-initramfs/conf-hook
echo "UMASK=0077" >> /etc/initramfs-tools/initramfs.conf

mkdir -p /etc/luks
dd if=/dev/urandom of=/etc/luks/boot_os.keyfile bs=4096 count=1
chmod -R u=rx,go-rwx /etc/luks
chmod u=r,go-rwx /etc/luks/boot_os.keyfile

# Schlüsseldatei zu LUKS-Volumes hinzufügen
echo -n "${LUKS_PASSWORD}" | cryptsetup luksAddKey ${DEVP}1 /etc/luks/boot_os.keyfile -
echo -n "${LUKS_PASSWORD}" | cryptsetup luksAddKey ${DEVP}5 /etc/luks/boot_os.keyfile -

# Crypttab aktualisieren
echo "LUKS_BOOT UUID=\$(blkid -s UUID -o value ${DEVP}1) /etc/luks/boot_os.keyfile luks,discard" > /etc/crypttab
echo "${DM}5_crypt UUID=\$(blkid -s UUID -o value ${DEVP}5) /etc/luks/boot_os.keyfile luks,discard" >> /etc/crypttab

# zram für Swap konfigurieren
cat > /etc/default/zramswap <<EOZ
# Konfiguration für zramswap
PERCENT=200
ALLOCATION=lz4
EOZ

# Benutzer anlegen
useradd -m -s /bin/bash -G sudo ${USERNAME}
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd

# SSH-Server installieren (aber nicht aktivieren)
apt-get install -y openssh-server
# SSH-Server deaktivieren
systemctl disable ssh

# Firewall konfigurieren
apt-get install -y ufw
# GUI-Tool nur installieren wenn Desktop
if [ "${INSTALL_DESKTOP}" = "1" ]; then
    apt-get install -y gufw
fi
ufw default deny incoming
ufw default allow outgoing
ufw enable

# Desktop-Umgebung installieren wenn gewünscht
echo "DEBUG: INSTALL_DESKTOP=${INSTALL_DESKTOP}, DESKTOP_ENV=${DESKTOP_ENV}, DESKTOP_SCOPE=${DESKTOP_SCOPE}" >> /var/log/install-debug.log
if [ "${INSTALL_DESKTOP}" = "1" ]; then
    case "${DESKTOP_ENV}" in
        # GNOME Desktop
        1)
            echo "Installiere GNOME-Desktop-Umgebung..."
            if [ "${DESKTOP_SCOPE}" = "1" ]; then
                # Standard-Installation
                apt-get install -y --no-install-recommends gnome-session gnome-shell gdm3 nautilus nautilus-hide gnome-terminal gnome-text-editor ubuntu-gnome-wallpapers gnome-tweaks virtualbox-guest-additions-iso virtualbox-guest-utils virtualbox-guest-x11
                echo "DEBUG: Desktop-Installation abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            else
                # Minimale Installation
                apt-get install -y --no-install-recommends gnome-session gnome-shell gdm3 nautilus nautilus-hide gnome-terminal gnome-text-editor ubuntu-gnome-wallpapers gnome-tweaks virtualbox-guest-additions-iso virtualbox-guest-utils virtualbox-guest-x11
                echo "DEBUG: Desktop-Installation abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            fi
            ;;
            
        # KDE Plasma Desktop (momentan nur Platzhalter)
        2)
            echo "KDE Plasma wird derzeit noch nicht unterstützt. Installiere GNOME stattdessen..."
            if [ "${DESKTOP_SCOPE}" = "1" ]; then
                apt-get install -y --no-install-recommends gnome-session gnome-shell gdm3 nautilus nautilus-hide gnome-terminal gnome-text-editor ubuntu-gnome-wallpapers gnome-tweaks virtualbox-guest-additions-iso virtualbox-guest-utils virtualbox-guest-x11
                echo "DEBUG: Desktop-Installation abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            else
                apt-get install -y --no-install-recommends gnome-session gnome-shell gdm3 nautilus nautilus-hide gnome-terminal gnome-text-editor ubuntu-gnome-wallpapers gnome-tweaks virtualbox-guest-additions-iso virtualbox-guest-utils virtualbox-guest-x11
                echo "DEBUG: Desktop-Installation abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            fi
            ;;
            
        # Xfce Desktop (momentan nur Platzhalter)
        3)
            echo "Xfce wird derzeit noch nicht unterstützt. Installiere GNOME stattdessen..."
            if [ "${DESKTOP_SCOPE}" = "1" ]; then
                apt-get install -y --no-install-recommends gnome-session gnome-shell gdm3 nautilus nautilus-hide gnome-terminal gnome-text-editor ubuntu-gnome-wallpapers gnome-tweaks virtualbox-guest-additions-iso virtualbox-guest-utils virtualbox-guest-x11
                echo "DEBUG: Desktop-Installation abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            else
                apt-get install -y --no-install-recommends gnome-session gnome-shell gdm3 nautilus nautilus-hide gnome-terminal gnome-text-editor ubuntu-gnome-wallpapers gnome-tweaks virtualbox-guest-additions-iso virtualbox-guest-utils virtualbox-guest-x11
                echo "DEBUG: Desktop-Installation abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            fi
            ;;
            
        # Fallback
        *)
            echo "Unbekannte Desktop-Umgebung. Installiere GNOME..."
            apt-get install -y --no-install-recommends gnome-session gnome-shell gdm3 nautilus nautilus-hide gnome-terminal gnome-text-editor ubuntu-gnome-wallpapers gnome-tweaks virtualbox-guest-additions-iso virtualbox-guest-utils virtualbox-guest-x11
            echo "DEBUG: Desktop-Installation abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            ;;
    esac
fi

# Desktop-Sprachpakete installieren
if [ "${INSTALL_DESKTOP}" = "1" ]; then
    echo "Installiere Sprachpakete für ${UI_LANGUAGE}..."
    
    # Gemeinsame Sprachpakete für alle Desktop-Umgebungen
    apt-get install -y language-pack-${UI_LANGUAGE%_*} language-selector-common
    
    # Desktop-spezifische Sprachpakete
    case "${DESKTOP_ENV}" in
        # GNOME Desktop
        1)
            apt-get install -y language-pack-gnome-${UI_LANGUAGE%_*} language-selector-gnome
            ;;
        # KDE Plasma Desktop
        2)
            apt-get install -y language-pack-kde-${UI_LANGUAGE%_*} kde-l10n-${UI_LANGUAGE%_*} || true
            ;;
        # Xfce Desktop
        3)
            apt-get install -y language-pack-${UI_LANGUAGE%_*}-base xfce4-session-l10n || true
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
if [[ "${ADDITIONAL_PACKAGES}" == *"thorium"* ]] || [ "${INSTALL_DESKTOP}" = "1" ]; then
    echo "Installiere Thorium Browser..." > /var/log/thorium_install.log
    
    # Farbdefinitionen für bessere Lesbarkeit (lokale Variablen im Skript)
    T_GREEN='\033[0;32m'
    T_YELLOW='\033[1;33m'
    T_RED='\033[0;31m'
    T_NC='\033[0m' # No Color
    
    echo -e "${T_GREEN}Teste Thorium Browser Installation...${T_NC}" >> /var/log/thorium_install.log
    
    # CPU-Erweiterungen prüfen
    echo -e "${T_YELLOW}Prüfe CPU-Erweiterungen...${T_NC}" >> /var/log/thorium_install.log
    if grep -q " avx2 " /proc/cpuinfo; then
        CPU_EXT="AVX2"
        echo "AVX2-Unterstützung gefunden." >> /var/log/thorium_install.log
    elif grep -q " avx " /proc/cpuinfo; then
        CPU_EXT="AVX"
        echo "AVX-Unterstützung gefunden." >> /var/log/thorium_install.log
    elif grep -q " sse4_1 " /proc/cpuinfo; then
        CPU_EXT="SSE4"
        echo "SSE4-Unterstützung gefunden." >> /var/log/thorium_install.log
    else
        CPU_EXT="SSE3"
        echo "Verwende SSE3-Basisversion." >> /var/log/thorium_install.log
    fi
    
    # Prüfe, ob wichtige Tools installiert sind
    for cmd in curl wget jq; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${T_RED}$cmd ist nicht installiert. Installiere...${T_NC}" >> /var/log/thorium_install.log
            apt-get update && apt-get install -y $cmd
        fi
    done
    
    # Versuche automatisch die neueste Version zu ermitteln
    echo -e "${T_YELLOW}Ermittle neueste Thorium-Version...${T_NC}" >> /var/log/thorium_install.log
    THORIUM_VERSION=$(curl -s https://api.github.com/repos/Alex313031/Thorium/releases/latest | jq -r '.tag_name' | sed 's/^M//')
    echo "Ermittelte Version: $THORIUM_VERSION" >> /var/log/thorium_install.log
    
    # Falls jq fehlschlägt, nutze einen Fallback-Ansatz
    if [ -z "$THORIUM_VERSION" ]; then
        echo -e "${T_YELLOW}Versuche alternativen Ansatz zur Ermittlung der Version...${T_NC}" >> /var/log/thorium_install.log
        # Prüfe direkt die Releases-Seite
        THORIUM_VERSION=$(curl -s https://github.com/Alex313031/Thorium/releases/latest | grep -o 'M[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1 | sed 's/^M//')
        echo "Ermittelte Version mit Fallback-Methode: $THORIUM_VERSION" >> /var/log/thorium_install.log
    fi
    
    THORIUM_SUCCESS=0  # Annahme: Installation schlägt fehl, bis sie erfolgreich ist
    
    # Download und Installation mit aktueller Version versuchen
    if [ -n "$THORIUM_VERSION" ]; then
        echo -e "${T_GREEN}Verwende Thorium-Version: $THORIUM_VERSION${T_NC}" >> /var/log/thorium_install.log
        THORIUM_URL="https://github.com/Alex313031/Thorium/releases/download/M${THORIUM_VERSION}/thorium-browser_${THORIUM_VERSION}_${CPU_EXT}.deb"
        
        echo -e "${T_YELLOW}Lade Thorium herunter: $THORIUM_URL${T_NC}" >> /var/log/thorium_install.log
        if wget -O /tmp/thorium.deb "$THORIUM_URL" >> /var/log/thorium_install.log 2>&1; then
            THORIUM_SUCCESS=1
        else
            echo -e "${T_RED}Download fehlgeschlagen, versuche generische Version...${T_NC}" >> /var/log/thorium_install.log
            # Versuche generische Version ohne CPU-Erweiterung
            THORIUM_URL="https://github.com/Alex313031/Thorium/releases/download/M${THORIUM_VERSION}/thorium-browser_${THORIUM_VERSION}_amd64.deb"
            
            if wget -O /tmp/thorium.deb "$THORIUM_URL" >> /var/log/thorium_install.log 2>&1; then
                THORIUM_SUCCESS=1
            else
                echo -e "${T_RED}Generischer Download fehlgeschlagen, verwende Fallback-Links...${T_NC}" >> /var/log/thorium_install.log
                FALLBACK_VERSION="130.0.6723.174"
                FALLBACK_URL="https://github.com/Alex313031/thorium/releases/download/M${FALLBACK_VERSION}/thorium-browser_${FALLBACK_VERSION}_${CPU_EXT}.deb"
                echo -e "${T_YELLOW}Versuche Fallback URL: $FALLBACK_URL${T_NC}" >> /var/log/thorium_install.log
                
                if wget -O /tmp/thorium.deb "$FALLBACK_URL" >> /var/log/thorium_install.log 2>&1; then
                    THORIUM_SUCCESS=1
                else
                    echo -e "${T_RED}Auch Fallback fehlgeschlagen, Installation von Thorium übersprungen.${T_NC}" >> /var/log/thorium_install.log
                    # Hier stand ursprünglich exit 1, jetzt lassen wir das Skript weiterlaufen
                    THORIUM_SUCCESS=0
                fi
            fi
        fi
    else
        # Bei Fehler bei der Versionsermittlung direkt zu Fallback-Links
        echo -e "${T_RED}Versionsermittlung fehlgeschlagen, verwende Fallback-Links...${T_NC}" >> /var/log/thorium_install.log
        FALLBACK_VERSION="130.0.6723.174"
        FALLBACK_URL="https://github.com/Alex313031/thorium/releases/download/M${FALLBACK_VERSION}/thorium-browser_${FALLBACK_VERSION}_${CPU_EXT}.deb"
        echo -e "${T_YELLOW}Versuche Fallback URL: $FALLBACK_URL${T_NC}" >> /var/log/thorium_install.log
        
        if wget -O /tmp/thorium.deb "$FALLBACK_URL" >> /var/log/thorium_install.log 2>&1; then
            THORIUM_SUCCESS=1
        else
            echo -e "${T_RED}Fallback-Download fehlgeschlagen, Installation von Thorium übersprungen.${T_NC}" >> /var/log/thorium_install.log
            # Hier stand ursprünglich exit 1, jetzt lassen wir das Skript weiterlaufen
            THORIUM_SUCCESS=0
        fi
    fi
    
    # Installation ausführen
    if [ -f /tmp/thorium.deb ] && [ "$THORIUM_SUCCESS" -eq 1 ]; then
        echo -e "${T_GREEN}Download erfolgreich, installiere Thorium...${T_NC}" >> /var/log/thorium_install.log
        if apt-get install -y /tmp/thorium.deb >> /var/log/thorium_install.log 2>&1; then
            rm /tmp/thorium.deb
            echo -e "${T_GREEN}Installation abgeschlossen.${T_NC}" >> /var/log/thorium_install.log
        else
            echo -e "${T_RED}Installation fehlgeschlagen.${T_NC}" >> /var/log/thorium_install.log
            rm -f /tmp/thorium.deb
        fi
    else
        echo -e "${T_RED}Download fehlgeschlagen, keine Thorium-Datei zum Installieren.${T_NC}" >> /var/log/thorium_install.log
        # Hier stand ursprünglich exit 1, jetzt lassen wir das Skript weiterlaufen
    fi
fi

# Aufräumen
echo "Bereinige temporäre Dateien..."
apt-get clean
apt-get autoremove -y
rm -f /setup.sh
MAINEOF
