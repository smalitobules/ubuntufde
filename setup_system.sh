#!/bin/bash

# Systemeinrichtung in chroot-Umgebung

# Globale Variablen
export DEBIAN_FRONTEND=noninteractive

# Netzwerkkonfiguration
setup_network() {
    echo "[INFO] Konfiguriere Netzwerk..."
    
    # SSH-Server deaktivieren
    systemctl disable ssh
    
    # Firewall einrichten
    ufw default deny incoming
    ufw default allow outgoing
    ufw enable
}

# Lokalisierung und Zeitzone
setup_localization() {
    echo "[INFO] Konfiguriere Lokalisierung und Zeitzone..."
    
    # Zeitzone setzen
    if [ -n "${TIMEZONE}" ]; then
        ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
    else
        ln -sf /usr/share/zoneinfo/Europe/Zurich /etc/localtime
    fi
    
    # Spracheinstellungen
    locale-gen ${LOCALE} en_US.UTF-8
    update-locale LANG=${LOCALE} LC_CTYPE=${LOCALE}
    
    # Tastaturlayout
    if [ -n "${KEYBOARD_LAYOUT}" ]; then
        echo "[INFO] Setze Tastaturlayout auf ${KEYBOARD_LAYOUT}"
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
}

# Automatische Aktualisierungen aktivieren
setup_automatic_updates() {
    echo "[INFO] Richte automatische Aktualisierungen ein..."
    
    # Automatische Updates konfigurieren
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<AUTOUPDATE
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "${UPDATE_OPTION}";
AUTOUPDATE
}

# System-Aktualisierung durchführen
update_system() {
    echo "[INFO] Importiere Repository-Schlüssel..."
    
    # GPG-Schlüssel für lokales Repository importieren
    if [ ! -f "/etc/apt/trusted.gpg.d/local-mirror.gpg" ]; then
        curl -fsSL http://192.168.56.120/repo-key.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/local-mirror.gpg
    fi
    
    echo "[INFO] Aktualisiere Paketquellen und System..."
    apt update
    apt upgrade -y
}

# Externe Repositories einrichten
setup_external_repositories() {
    echo "[INFO] Richte externe Repositories ein..."
    
    mkdir -p /etc/apt/keyrings
    
    # Liquorix-Kernel Repository
    if [ "${KERNEL_TYPE}" = "liquorix" ]; then
        echo "[INFO] Füge Liquorix-Kernel-Repository hinzu..."
        echo "deb http://liquorix.net/debian stable main" > /etc/apt/sources.list.d/liquorix.list
        curl -s 'https://liquorix.net/linux-liquorix-keyring.gpg' | gpg --dearmor -o /etc/apt/keyrings/liquorix-keyring.gpg
        echo "deb [signed-by=/etc/apt/keyrings/liquorix-keyring.gpg] https://liquorix.net/debian stable main" | tee /etc/apt/sources.list.d/liquorix.list
    fi
}

# Kernel und kritische Systempakete installieren
install_kernel() {
    echo "[INFO] Installiere Kernel-Pakete..."
    
    # Kernel-Pakete basierend auf Auswahl
    if [ "${INSTALL_DESKTOP}" != "1" ]; then
        if [ "${KERNEL_TYPE}" = "standard" ]; then
            apt install -y --no-install-recommends linux-image-generic linux-headers-generic
        elif [ "${KERNEL_TYPE}" = "lowlatency" ]; then
            apt install -y --no-install-recommends linux-image-lowlatency linux-headers-lowlatency
        elif [ "${KERNEL_TYPE}" = "liquorix" ]; then
            apt install -y --no-install-recommends linux-image-liquorix-amd64 linux-headers-liquorix-amd64    
        fi
    fi
}

# LUKS-Verschlüsselung einrichten
setup_luks_encryption() {
    echo "[INFO] Konfiguriere LUKS-Verschlüsselung..."
    
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
    echo "${LUKS_BOOT_NAME} UUID=$(blkid -s UUID -o value ${DEVP}1) /etc/luks/boot_os.keyfile luks,discard,initramfs" > /etc/crypttab
    echo "${LUKS_ROOT_NAME} UUID=$(blkid -s UUID -o value ${DEVP}5) /etc/luks/boot_os.keyfile luks,discard,initramfs" >> /etc/crypttab
    
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
}

# GRUB-Bootloader konfigurieren
setup_grub() {
    echo "[INFO] Konfiguriere GRUB-Bootloader..."
    
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
GRUB_CMDLINE_LINUX="cryptdevice=UUID=\$(blkid -s UUID -o value ${DEVP}5):${LUKS_ROOT_NAME} root=/dev/mapper/vg-root resume=/dev/mapper/vg-swap"
GRUB_ENABLE_CRYPTODISK=y
GRUB_GFXMODE=1280x1024
GRUBCFG
    
    # GRUB Konfigurationsdatei-Rechte setzen
    chmod 644 /etc/default/grub
    
    # GRUB Hauptkonfiguration aktualisieren
    sed -i 's/GRUB_ENABLE_CRYPTODISK=.*/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub
    
    # Initramfs aktualisieren und GRUB installieren
    update-initramfs -u -k all
    grub-install --no-nvram --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck
    update-grub
}

# Zram für Swap konfigurieren
setup_zram_swap() {
    echo "[INFO] Konfiguriere Zram für Swap..."
    
    cat > /etc/default/zramswap <<EOZ
# Konfiguration für zramswap
PERCENT=200
ALLOCATION=lz4
EOZ
}

# Benutzer anlegen
setup_users() {
    echo "[INFO] Erstelle Benutzer..."
    
    useradd -m -s /bin/bash -G sudo ${USERNAME}
    echo "${USERNAME}:${USER_PASSWORD}" | chpasswd
}

# GNOME Desktop installieren
install_gnome_desktop() {
    # WICHTIG: Hier wird \$ verwendet, damit die Variablen erst im chroot ausgewertet werden!
    GNOME_PACKAGES="
        xserver-xorg
        xorg
        x11-common
        x11-xserver-utils
        xdotool
        dbus-x11
        gnome-session
        gnome-shell
        gdm3
        libpam-gnome-keyring
        gsettings-desktop-schemas
        gparted
        gnome-disk-utility
        gnome-text-editor
        gnome-terminal
        gnome-tweaks
        gnome-shell-extensions
        gnome-shell-extension-manager
        gnome-system-monitor
        chrome-gnome-shell
        gufw
        gir1.2-gtop-2.0
        libgtop-2.0-11
        dconf-editor
        dconf-cli
        nautilus
        nautilus-hide
        nautilus-admin
        ubuntu-gnome-wallpapers
        yad
        bleachbit
        stacer
        vlc
        deluge
        virtualbox-guest-additions-iso
        virtualbox-guest-utils
        virtualbox-guest-x11
    "
    
    # GNOME-spezifische Sprachpakete
    echo "[INFO] Installiere GNOME Desktop mit Sprachpaketen für ${UI_LANGUAGE}..."
    
    # Kernel-Pakete basierend auf Auswahl
    if [ "${KERNEL_TYPE}" = "standard" ]; then
        KERNEL="linux-image-generic linux-headers-generic"
    elif [ "${KERNEL_TYPE}" = "lowlatency" ]; then
        KERNEL="linux-image-lowlatency linux-headers-lowlatency"
    elif [ "${KERNEL_TYPE}" = "liquorix" ]; then
        KERNEL="linux-image-liquorix-amd64 linux-headers-liquorix-amd64"
    else
        KERNEL="linux-image-generic linux-headers-generic"
    fi
    
    # Sprachpakete
    LANGUAGE_BASE="language-pack-${UI_LANGUAGE%_*} language-selector-common"
    LANGUAGE_GNOME="language-pack-gnome-${UI_LANGUAGE%_*} language-selector-gnome"
    
    # Installation durchführen
    apt install -y --no-install-recommends $KERNEL $LANGUAGE_BASE $LANGUAGE_GNOME $GNOME_PACKAGES
    
    echo "[INFO] GNOME Desktop-Installation abgeschlossen"
}

# KDE Desktop installieren
install_kde_desktop() {
    echo "[INFO] Installiere KDE Plasma..."
    
    # Kernel-Pakete basierend auf Auswahl
    if [ "${KERNEL_TYPE}" = "standard" ]; then
        KERNEL="linux-image-generic linux-headers-generic"
    elif [ "${KERNEL_TYPE}" = "lowlatency" ]; then
        KERNEL="linux-image-lowlatency linux-headers-lowlatency"
    elif [ "${KERNEL_TYPE}" = "liquorix" ]; then
        KERNEL="linux-image-liquorix-amd64 linux-headers-liquorix-amd64"
    else
        KERNEL="linux-image-generic linux-headers-generic"
    fi
    
    # Sprachpakete
    LANGUAGE_BASE="language-pack-${UI_LANGUAGE%_*} language-selector-common"
    LANGUAGE_KDE="language-pack-kde-${UI_LANGUAGE%_*}"
    
    # Füge kde-l10n nur hinzu wenn verfügbar (ist in neueren Versionen nicht mehr vorhanden)
    if apt-cache show kde-l10n-${UI_LANGUAGE%_*} >/dev/null 2>&1; then
        LANGUAGE_KDE="$LANGUAGE_KDE kde-l10n-${UI_LANGUAGE%_*}"
    fi
    
    # Minimal-Installation für VMs
    KDE_PACKAGES="
        virtualbox-guest-additions-iso
        virtualbox-guest-utils
        virtualbox-guest-x11
    "
    
    # Installation durchführen
    apt install -y --no-install-recommends $KERNEL $LANGUAGE_BASE $LANGUAGE_KDE $KDE_PACKAGES
    
    echo "[INFO] KDE Desktop-Installation abgeschlossen"
}

# Xfce Desktop installieren
install_xfce_desktop() {
    echo "[INFO] Installiere Xfce..."
    
    # Kernel-Pakete basierend auf Auswahl
    if [ "${KERNEL_TYPE}" = "standard" ]; then
        KERNEL="linux-image-generic linux-headers-generic"
    elif [ "${KERNEL_TYPE}" = "lowlatency" ]; then
        KERNEL="linux-image-lowlatency linux-headers-lowlatency"
    elif [ "${KERNEL_TYPE}" = "liquorix" ]; then
        KERNEL="linux-image-liquorix-amd64 linux-headers-liquorix-amd64"
    else
        KERNEL="linux-image-generic linux-headers-generic"
    fi
    
    # Sprachpakete
    LANGUAGE_BASE="language-pack-${UI_LANGUAGE%_*} language-selector-common"
    LANGUAGE_XFCE="language-pack-${UI_LANGUAGE%_*}-base"
    
    # Füge xfce4-session-l10n nur hinzu wenn verfügbar
    if apt-cache show xfce4-session-l10n >/dev/null 2>&1; then
        LANGUAGE_XFCE="$LANGUAGE_XFCE xfce4-session-l10n"
    fi
    
    # Minimal-Installation für VMs
    XFCE_PACKAGES="
        virtualbox-guest-additions-iso
        virtualbox-guest-utils
        virtualbox-guest-x11
    "
    
    # Installation durchführen
    apt install -y --no-install-recommends $KERNEL $LANGUAGE_BASE $LANGUAGE_XFCE $XFCE_PACKAGES
    
    echo "[INFO] Xfce Desktop-Installation abgeschlossen"
}

# Desktop-Umgebung installieren
install_desktop_environment() {
    if [ "${INSTALL_DESKTOP}" != "1" ]; then
        echo "[INFO] Keine Desktop-Installation gewählt, überspringe..."
        return 0
    fi
    
    echo "[INFO] Installiere Desktop-Umgebung..."
    
    case "${DESKTOP_ENV}" in
        # GNOME Desktop
        1)
            install_gnome_desktop
            ;;
            
        # KDE Plasma Desktop
        2)
            echo "[INFO] KDE Plasma wird derzeit noch nicht vollständig unterstützt."
            install_kde_desktop
            ;;
            
        # Xfce Desktop
        3)
            echo "[INFO] Xfce wird derzeit noch nicht vollständig unterstützt."
            install_xfce_desktop
            ;;
            
        # Fallback
        *)
            echo "[INFO] Unbekannte Desktop-Umgebung. Installiere GNOME..."
            install_gnome_desktop
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
}

# Installiere zusätzliche Software
install_additional_software() {
    echo "[INFO] Prüfe auf zusätzliche Software-Installation..."
    
    # Thorium Browser installieren
    if [ "${INSTALL_DESKTOP}" = "1" ] && [ -f /tmp/thorium.deb ]; then
        echo "[INFO] Thorium-Browser-Paket gefunden, installiere..."
        
        # Installation mit apt
        if apt install -y --fix-broken /tmp/thorium.deb; then
            echo "[INFO] Thorium wurde erfolgreich installiert."
        else
            echo "[WARNUNG] Thorium-Installation über apt fehlgeschlagen, versuche alternativen Ansatz..."
            # Abhängigkeiten beheben und erneut versuchen
            apt -f install -y
            if dpkg -i /tmp/thorium.deb; then
                echo "[INFO] Thorium wurde im zweiten Versuch erfolgreich installiert."
            else
                echo "[WARNUNG] Thorium-Installation fehlgeschlagen."
            fi
        fi
        
        # Aufräumen
        rm -f /tmp/thorium.deb
    fi
}

# Systemd-Dienste konfigurieren
configure_systemd_services() {
    echo "[INFO] Konfiguriere Systemd-Dienste..."
    
    # Deaktiviere unerwünschte Systemd-Dienste
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
}

# System-Cleanup
cleanup_system() {
    echo "[INFO] Bereinige temporäre Dateien..."
    apt clean
    apt autoremove -y
    rm -f /setup_system.sh
}

# Hauptfunktion
main() {
    echo "===== Starte System-Setup: $(date) ====="
    
    # Grundlegende Systemkonfiguration
    setup_network 
    setup_localization
    setup_automatic_updates
    update_system
    setup_external_repositories
    
    # Kerninstallation, wenn kein Desktop ausgewählt ist
    install_kernel
    
    # LUKS und Boot-Setup
    setup_luks_encryption
    setup_grub
    setup_zram_swap
    
    # Benutzer einrichten
    setup_users
    
    # Desktop-Umgebung installieren
    install_desktop_environment
    
    # Zusätzliche Software
    install_additional_software
    
    # Systemd-Dienste
    configure_systemd_services
    
    # Bereinigung
    cleanup_system
    
    echo "===== System-Setup erfolgreich abgeschlossen: $(date) ====="
    return 0
}

# Skript ausführen
main "$@"