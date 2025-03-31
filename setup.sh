# System-Setup in chroot
log_progress "Konfiguriere System in chroot-Umgebung..."
cat > /mnt/ubuntu/setup.sh <<MAINEOF
#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

# Zeitzone setzen
if [ -n "${TIMEZONE}" ]; then
    ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
else
    ln -sf /usr/share/zoneinfo/Europe/Zurich /etc/localtime
fi

# Quellen einrichten
cat > /etc/apt/sources.list <<SOURCES
deb https://archive.ubuntu.com/ubuntu/ oracular main restricted universe multiverse
deb https://archive.ubuntu.com/ubuntu/ oracular-updates main restricted universe multiverse
deb https://archive.ubuntu.com/ubuntu/ oracular-security main restricted universe multiverse
deb https://archive.ubuntu.com/ubuntu/ oracular-backports main restricted universe multiverse
SOURCES

# Automatische Updates konfigurieren
cat > /etc/apt/apt.conf.d/20auto-upgrades <<AUTOUPDATE
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "${UPDATE_OPTION}";
AUTOUPDATE

# Systemaktualisierung durchführen und Nala installieren
apt-get update
apt-get dist-upgrade -y
apt-get install -y nala
#nala fetch --auto --https-only

# Notwendige Pakete installieren 
echo "Installiere Basis-Pakete..."
KERNEL_PACKAGES=""
if [ "${KERNEL_TYPE}" = "standard" ]; then
    KERNEL_PACKAGES="linux-image-generic linux-headers-generic"
elif [ "${KERNEL_TYPE}" = "lowlatency" ]; then
    KERNEL_PACKAGES="linux-image-lowlatency linux-headers-lowlatency"
fi

apt-get install -y --no-install-recommends \
    \${KERNEL_PACKAGES} \
    initramfs-tools \
    cryptsetup-initramfs \
    cryptsetup \
    lvm2 \
    grub-efi-amd64 \
    grub-efi-amd64-signed \
    shim-signed \
    efibootmgr \
    zram-tools \
    sudo \
    locales \
    console-setup \
    systemd-resolved \
    coreutils \
    nano \
    vim \
    curl \
    wget \
    gnupg \
    ca-certificates \
    jq \
    bash-completion

# Liquorix-Kernel installieren wenn gewählt
if [ "${KERNEL_TYPE}" = "liquorix" ]; then
    apt-get install -y apt-transport-https
    echo "deb http://liquorix.net/debian stable main" > /etc/apt/sources.list.d/liquorix.list
    mkdir -p /etc/apt/keyrings
    curl -s 'https://liquorix.net/linux-liquorix-keyring.gpg' | gpg --dearmor -o /etc/apt/keyrings/liquorix-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/liquorix-keyring.gpg] https://liquorix.net/debian stable main" | tee /etc/apt/sources.list.d/liquorix.list
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

# GRUB für Verschlüsselung und Display konfigurieren
cat > /etc/default/grub.d/local.cfg <<GRUBCFG
GRUB_ENABLE_CRYPTODISK=y
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash nomodeset loglevel=3 rd.systemd.show_status=auto rd.udev.log_level=3"
GRUB_TIMEOUT=1
GRUB_GFXMODE=1024x768
GRUBCFG

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

# Grundlegende Tools installieren
apt-get install -y timeshift bleachbit fastfetch gparted vlc deluge ubuntu-gnome-wallpapers gnome-tweaks

# Desktop-Umgebung installieren wenn gewünscht
if [ "${INSTALL_DESKTOP}" = "1" ]; then
    case "${DESKTOP_ENV}" in
        # GNOME Desktop
        1)
            echo "Installiere GNOME-Desktop-Umgebung..."
            if [ "${DESKTOP_SCOPE}" = "1" ]; then
                # Standard-Installation
                apt-get install -y gnome-session gnome-shell gdm3 nautilus nautilus-hide gnome-terminal virtualbox-guest-additions-iso virtualbox-guest-utils virtualbox-guest-x11 
            else
                # Minimale Installation
                apt-get install -y gnome-session gnome-shell gdm3 nautilus nautilus-hide gnome-terminal virtualbox-guest-additions-iso virtualbox-guest-utils virtualbox-guest-x11 
            fi
            ;;
            
        # KDE Plasma Desktop (momentan nur Platzhalter)
        2)
            echo "KDE Plasma wird derzeit noch nicht unterstützt. Installiere GNOME stattdessen..."
            if [ "${DESKTOP_SCOPE}" = "1" ]; then
                apt-get install -y gnome-session gnome-shell gdm3 nautilus nautilus-hide gnome-terminal virtualbox-guest-additions-iso virtualbox-guest-utils virtualbox-guest-x11  
            else
                apt-get install -y gnome-session gnome-shell gdm3 nautilus nautilus-hide gnome-terminal virtualbox-guest-additions-iso virtualbox-guest-utils virtualbox-guest-x11 
            fi
            ;;
            
        # Xfce Desktop (momentan nur Platzhalter)
        3)
            echo "Xfce wird derzeit noch nicht unterstützt. Installiere GNOME stattdessen..."
            if [ "${DESKTOP_SCOPE}" = "1" ]; then
                apt-get install -y gnome-session gnome-shell gdm3 nautilus nautilus-hide gnome-terminal virtualbox-guest-additions-iso virtualbox-guest-utils virtualbox-guest-x11  
            else
                apt-get install -y gnome-session gnome-shell gdm3 nautilus nautilus-hide gnome-terminal virtualbox-guest-additions-iso virtualbox-guest-utils virtualbox-guest-x11 
            fi
            ;;
            
        # Fallback
        *)
            echo "Unbekannte Desktop-Umgebung. Installiere GNOME..."
            apt-get install -y gnome-session gnome-shell gdm3 nautilus nautilus-hide gnome-terminal virtualbox-guest-additions-iso virtualbox-guest-utils virtualbox-guest-x11 
            ;;
    esac
fi

# Thorium Browser installieren
if [[ "${ADDITIONAL_PACKAGES}" == *"thorium"* ]] || [ "${INSTALL_DESKTOP}" = "1" ]; then
    echo "Installiere Thorium Browser..."
    
    # CPU-Erweiterungen prüfen
    echo "Prüfe CPU-Erweiterungen..."
    if grep -q " avx2 " /proc/cpuinfo; then
        CPU_EXT="AVX2"
        echo "AVX2-Unterstützung gefunden."
    elif grep -q " avx " /proc/cpuinfo; then
        CPU_EXT="AVX"
        echo "AVX-Unterstützung gefunden."
    elif grep -q " sse4_1 " /proc/cpuinfo; then
        CPU_EXT="SSE4"
        echo "SSE4-Unterstützung gefunden."
    else
        CPU_EXT="SSE3"
        echo "Verwende SSE3-Basisversion."
    fi
    
    # Alternativer Ansatz mit jq für stabilere JSON-Verarbeitung
    THORIUM_VERSION=$(curl -s https://api.github.com/repos/Alex313031/Thorium/releases/latest | jq -r '.tag_name' | sed 's/^M//')
    
    # Falls jq fehlschlägt, nutze einen Fallback-Ansatz
    if [ -z "$THORIUM_VERSION" ]; then
        echo "Versuche alternativen Ansatz zur Ermittlung der Version..."
        # Prüfe direkt die Releases-Seite
        THORIUM_VERSION=$(curl -s https://github.com/Alex313031/Thorium/releases/latest | grep -o 'M[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1 | sed 's/^M//')
    fi
    
    # Wenn immer noch keine Version gefunden wurde, verwende eine feste Version
    if [ -z "$THORIUM_VERSION" ]; then
        echo "Konnte Version nicht dynamisch ermitteln, verwende feste Version..."
        THORIUM_VERSION="130.0.6723.174"
    fi
    
    echo "Verwende Thorium-Version: $THORIUM_VERSION"
    
    # Download und Installation
    THORIUM_URL="https://github.com/Alex313031/Thorium/releases/download/M${THORIUM_VERSION}/thorium-browser_${THORIUM_VERSION}_${CPU_EXT}.deb"
    
    echo "Lade Thorium herunter: $THORIUM_URL"
    if wget -O /tmp/thorium.deb "$THORIUM_URL"; then
        echo "Download erfolgreich, installiere Thorium..."
        apt-get install -y /tmp/thorium.deb
        rm /tmp/thorium.deb
    else
        echo "Download fehlgeschlagen, versuche generische Version..."
        # Versuche generische Version ohne CPU-Erweiterung
        THORIUM_URL="https://github.com/Alex313031/Thorium/releases/download/M${THORIUM_VERSION}/thorium-browser_${THORIUM_VERSION}_amd64.deb"
        if wget -O /tmp/thorium.deb "$THORIUM_URL"; then
            echo "Download erfolgreich, installiere generische Thorium-Version..."
            apt-get install -y /tmp/thorium.deb
            rm /tmp/thorium.deb
        else
            echo "Konnte Thorium nicht herunterladen, Installation übersprungen."
        fi
    fi
fi

# Weitere zusätzliche Pakete installieren
if [ -n "${ADDITIONAL_PACKAGES}" ]; then
    echo "Installiere zusätzliche Pakete: ${ADDITIONAL_PACKAGES}"
    apt-get install -y ${ADDITIONAL_PACKAGES}
fi

# Bootloader (GRUB) installieren
update-initramfs -u -k all
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck
update-grub

# Cleanup
apt-get clean
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
sed -i "s/\${LOCALE}/$LOCALE/g" /mnt/ubuntu/setup.sh
sed -i "s/\${KEYBOARD_LAYOUT}/$KEYBOARD_LAYOUT/g" /mnt/ubuntu/setup.sh
sed -i "s/\${TIMEZONE}/$TIMEZONE/g" /mnt/ubuntu/setup.sh
sed -i "s/\${NETWORK_CONFIG}/$NETWORK_CONFIG/g" /mnt/ubuntu/setup.sh
sed -i "s|\${STATIC_IP_CONFIG}|$STATIC_IP_CONFIG|g" /mnt/ubuntu/setup.sh

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
show_progress 90
}