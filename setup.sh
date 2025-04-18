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

## Nala-Mirror-Optimierung für das finale System
#if command -v nala &> /dev/null; then
#    echo "Konfiguriere nala im neuen System..."
#    
#    # Falls wir bereits optimierte Mirrors haben, nutze diese
#    if [ -f /etc/apt/sources.list.d/nala-sources.list ]; then
#        echo "Übernehme optimierte Mirror-Konfiguration, überspringe erneute Suche..."
#    else
#        # Ermittle Land basierend auf IP-Adresse
#        echo "Keine optimierte Mirror-Konfiguration gefunden, starte Suche..."
#        COUNTRY_CODE=\$(curl -s https://ipapi.co/country_code)
#        
#        if [ -z "\$COUNTRY_CODE" ]; then
#            # Fallback
#            COUNTRY_CODE=\$(curl -s https://ipinfo.io/country)
#        fi
#        
#        if [ -z "\$COUNTRY_CODE" ]; then
#            # Letzter Fallback
#            COUNTRY_CODE="${COUNTRY_CODE:-all}"
#        else
#            echo "Erkanntes Land: \$COUNTRY_CODE"
#        fi
#        
#        echo "Suche nach schnellsten Mirrors für das neue System..."
#        nala fetch --ubuntu "\${UBUNTU_CODENAME}" --auto --fetches 3 --country "\$COUNTRY_CODE"
#    fi
#fi

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