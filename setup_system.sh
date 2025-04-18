#!/bin/bash
# Systemeinrichtung in chroot-Umgebung

set -e

# Globale Variablen
export DEBIAN_FRONTEND=noninteractive
LOG_FILE="/var/log/setup-system.log"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

# Hilfsfunktionen für Logging
log_info() {
    echo "[INFO] $1"
}

log_warn() {
    echo "[WARNUNG] $1"
}

log_error() {
    echo "[FEHLER] $1"
    return 1
}

# Wrapper-Funktionen für Paketoperationen
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

# Netzwerkkonfiguration
setup_network() {
    log_info "Konfiguriere Netzwerk..."
    
    # SSH-Server deaktivieren
    systemctl disable ssh
    
    # Firewall einrichten
    ufw default deny incoming
    ufw default allow outgoing
    ufw enable
    
    return 0
}

# Lokalisierung und Zeitzone
setup_localization() {
    log_info "Konfiguriere Lokalisierung und Zeitzone..."
    
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
        log_info "Setze Tastaturlayout auf ${KEYBOARD_LAYOUT}"
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
    
    return 0
}

# Nala Spiegelserver-Optimierung
setup_nala_mirrors() {
    log_info "Konfiguriere Nala Spiegelserver..."
    
    # Falls Nala verfügbar ist, konfiguriere es
    if command -v nala &> /dev/null; then
        log_info "Konfiguriere nala im neuen System..."
        
        # Falls wir bereits optimierte Spiegelserver haben, nutze diese
        if [ -f /etc/apt/sources.list.d/nala-sources.list ]; then
            log_info "Übernehme optimierte Spiegelserver-Konfiguration, überspringe erneute Suche..."
        else
            # Ermittle Land basierend auf IP-Adresse
            log_info "Keine optimierte Spiegelserver-Konfiguration gefunden, starte Suche..."
            COUNTRY_CODE=$(curl -s https://ipapi.co/country_code)
            
            if [ -z "$COUNTRY_CODE" ]; then
                # Fallback
                COUNTRY_CODE=$(curl -s https://ipinfo.io/country)
            fi
            
            if [ -z "$COUNTRY_CODE" ]; then
                # Letzter Fallback
                COUNTRY_CODE="${COUNTRY_CODE:-all}"
            else
                log_info "Erkanntes Land: $COUNTRY_CODE"
            fi
            
            log_info "Suche nach schnellsten Spiegelservern für das neue System..."
            nala fetch --ubuntu plucky --auto --fetches 3 --country "$COUNTRY_CODE"
        fi
    fi
    
    return 0
}

# Automatische Aktualisierungen aktivieren
setup_automatic_updates() {
    log_info "Richte automatische Aktualisierungen ein..."
    
    # Automatische Updates konfigurieren
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<AUTOUPDATE
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "${UPDATE_OPTION}";
AUTOUPDATE
    
    return 0
}

# System-Aktualisierung durchführen
update_system() {
    log_info "Importiere Repository-Schlüssel..."
    
    # GPG-Schlüssel für lokales Repository importieren
    if [ ! -f "/etc/apt/trusted.gpg.d/local-mirror.gpg" ]; then
        curl -fsSL http://192.168.56.120/repo-key.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/local-mirror.gpg
    fi
    
    log_info "Aktualisiere Paketquellen und System..."

    # Systemaktualisierung durchführen
    pkg_update
    pkg_upgrade
    
    return 0
}

# Externe Repositories einrichten
setup_external_repositories() {
    log_info "Richte externe Repositories ein..."
    
    mkdir -p /etc/apt/keyrings
    
    # Liquorix-Kernel Repository
    if [ "${KERNEL_TYPE}" = "liquorix" ]; then
        log_info "Füge Liquorix-Kernel-Repository hinzu..."
        echo "deb http://liquorix.net/debian stable main" > /etc/apt/sources.list.d/liquorix.list
        curl -s 'https://liquorix.net/linux-liquorix-keyring.gpg' | gpg --dearmor -o /etc/apt/keyrings/liquorix-keyring.gpg
        echo "deb [signed-by=/etc/apt/keyrings/liquorix-keyring.gpg] https://liquorix.net/debian stable main" | tee /etc/apt/sources.list.d/liquorix.list
    fi
        
    return 0
}

# Kernel und kritische Systempakete installieren
install_kernel() {
    log_info "Installiere Kernel-Pakete..."
    
    # Kernel-Pakete basierend auf Auswahl
    local KERNEL_PACKAGES=""
    if [ "${KERNEL_TYPE}" = "standard" ]; then
        KERNEL_PACKAGES="linux-image-generic linux-headers-generic"
    elif [ "${KERNEL_TYPE}" = "lowlatency" ]; then
        KERNEL_PACKAGES="linux-image-lowlatency linux-headers-lowlatency"
    elif [ "${KERNEL_TYPE}" = "liquorix" ]; then
        KERNEL_PACKAGES="linux-image-liquorix-amd64 linux-headers-liquorix-amd64"    
    fi
    
    # Grundlegende Programme für Desktopfreie-Umgebung installieren
    if [ "${INSTALL_DESKTOP}" != "1" ]; then
        pkg_install --no-install-recommends ${KERNEL_PACKAGES}
    fi
    
    return 0
}

# LUKS-Verschlüsselung einrichten
setup_luks_encryption() {
    log_info "Konfiguriere LUKS-Verschlüsselung..."
    
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
    
    return 0
}

# GRUB-Bootloader konfigurieren
setup_grub() {
    log_info "Konfiguriere GRUB-Bootloader..."
    
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
    
    # GRUB Konfigurationsdatei-Rechte setzen
    chmod 644 /etc/default/grub
    
    # GRUB Hauptkonfiguration aktualisieren
    sed -i 's/GRUB_ENABLE_CRYPTODISK=.*/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub
    
    # Initramfs aktualisieren und GRUB installieren
    update-initramfs -u -k all
    grub-install --no-nvram --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck
    update-grub
    
    return 0
}

# Zram für Swap konfigurieren
setup_zram_swap() {
    log_info "Konfiguriere Zram für Swap..."
    
    cat > /etc/default/zramswap <<EOZ
# Konfiguration für zramswap
PERCENT=200
ALLOCATION=lz4
EOZ
    
    return 0
}

# Benutzer anlegen
setup_users() {
    log_info "Erstelle Benutzer..."
    
    useradd -m -s /bin/bash -G sudo ${USERNAME}
    echo "${USERNAME}:${USER_PASSWORD}" | chpasswd
    
    return 0
}

# Desktop-Umgebung installieren
install_desktop_environment() {
    if [ "${INSTALL_DESKTOP}" != "1" ]; then
        log_info "Keine Desktop-Installation gewählt, überspringe..."
        return 0
    fi
    
    log_info "Installiere Desktop-Umgebung..."
    
    # Basis-Sprachpakete für alle Desktop-Umgebungen
    BASE_LANGUAGE_PACKAGES="language-pack-${UI_LANGUAGE%_*} language-selector-common"
    
    case "${DESKTOP_ENV}" in
        # GNOME Desktop
        1)
            log_info "Installiere GNOME Desktop mit Sprachpaketen für ${UI_LANGUAGE}..."
            install_gnome_desktop
            ;;
            
        # KDE Plasma Desktop
        2)
            log_info "KDE Plasma wird derzeit noch nicht unterstützt. Installiere GNOME stattdessen..."
            install_kde_desktop
            ;;
            
        # Xfce Desktop
        3)
            log_info "Xfce wird derzeit noch nicht unterstützt. Installiere GNOME stattdessen..."
            install_xfce_desktop
            ;;
            
        # Fallback
        *)
            log_info "Unbekannte Desktop-Umgebung. Installiere GNOME..."
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
    
    return 0
}

# GNOME Desktop installieren
install_gnome_desktop() {
    # GNOME-spezifische Sprachpakete
    GNOME_LANGUAGE_PACKAGES="language-pack-gnome-${UI_LANGUAGE%_*} language-selector-gnome"
    
    # Basis-Kernpaket ermitteln
    local KERNEL_PACKAGES=""
    if [ "${KERNEL_TYPE}" = "standard" ]; then
        KERNEL_PACKAGES="linux-image-generic linux-headers-generic"
    elif [ "${KERNEL_TYPE}" = "lowlatency" ]; then
        KERNEL_PACKAGES="linux-image-lowlatency linux-headers-lowlatency"
    elif [ "${KERNEL_TYPE}" = "liquorix" ]; then
        KERNEL_PACKAGES="linux-image-liquorix-amd64 linux-headers-liquorix-amd64"    
    fi
    
    if [ "${DESKTOP_SCOPE}" = "1" ]; then
        # Standard-Installation mit Sprachpaketen
        pkg_install --no-install-recommends \
            ${KERNEL_PACKAGES} \
            ${BASE_LANGUAGE_PACKAGES} \
            ${GNOME_LANGUAGE_PACKAGES} \
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
    else
        # Minimale Installation mit Sprachpaketen
        pkg_install --no-install-recommends \
            ${KERNEL_PACKAGES} \
            ${BASE_LANGUAGE_PACKAGES} \
            ${GNOME_LANGUAGE_PACKAGES} \
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
    fi
    
    log_info "GNOME Desktop-Installation abgeschlossen"
}

# KDE Desktop installieren
install_kde_desktop() {
    # KDE-spezifische Sprachpakete
    KDE_LANGUAGE_PACKAGES="language-pack-kde-${UI_LANGUAGE%_*}"
    
    # Füge kde-l10n nur hinzu wenn verfügbar (ist in neueren Versionen nicht mehr vorhanden)
    if apt-cache show kde-l10n-${UI_LANGUAGE%_*} >/dev/null 2>&1; then
        KDE_LANGUAGE_PACKAGES+=" kde-l10n-${UI_LANGUAGE%_*}"
    fi
    
    # Basis-Kernpaket ermitteln
    local KERNEL_PACKAGES=""
    if [ "${KERNEL_TYPE}" = "standard" ]; then
        KERNEL_PACKAGES="linux-image-generic linux-headers-generic"
    elif [ "${KERNEL_TYPE}" = "lowlatency" ]; then
        KERNEL_PACKAGES="linux-image-lowlatency linux-headers-lowlatency"
    elif [ "${KERNEL_TYPE}" = "liquorix" ]; then
        KERNEL_PACKAGES="linux-image-liquorix-amd64 linux-headers-liquorix-amd64"    
    fi
    
    if [ "${DESKTOP_SCOPE}" = "1" ]; then
        pkg_install --no-install-recommends \
            ${KERNEL_PACKAGES} \
            ${BASE_LANGUAGE_PACKAGES} \
            ${KDE_LANGUAGE_PACKAGES} \
            virtualbox-guest-additions-iso \
            virtualbox-guest-utils \
            virtualbox-guest-x11
    else
        pkg_install --no-install-recommends \
            ${KERNEL_PACKAGES} \
            ${BASE_LANGUAGE_PACKAGES} \
            ${KDE_LANGUAGE_PACKAGES} \
            virtualbox-guest-additions-iso \
            virtualbox-guest-utils \
            virtualbox-guest-x11                
    fi
    
    log_info "KDE Desktop-Installation abgeschlossen"
}

# Xfce Desktop installieren
install_xfce_desktop() {
    # Xfce-spezifische Sprachpakete
    XFCE_LANGUAGE_PACKAGES="language-pack-${UI_LANGUAGE%_*}-base"
    
    # Füge xfce4-session-l10n nur hinzu wenn verfügbar
    if apt-cache show xfce4-session-l10n >/dev/null 2>&1; then
        XFCE_LANGUAGE_PACKAGES+=" xfce4-session-l10n"
    fi
    
    # Basis-Kernpaket ermitteln
    local KERNEL_PACKAGES=""
    if [ "${KERNEL_TYPE}" = "standard" ]; then
        KERNEL_PACKAGES="linux-image-generic linux-headers-generic"
    elif [ "${KERNEL_TYPE}" = "lowlatency" ]; then
        KERNEL_PACKAGES="linux-image-lowlatency linux-headers-lowlatency"
    elif [ "${KERNEL_TYPE}" = "liquorix" ]; then
        KERNEL_PACKAGES="linux-image-liquorix-amd64 linux-headers-liquorix-amd64"    
    fi
    
    if [ "${DESKTOP_SCOPE}" = "1" ]; then
        pkg_install --no-install-recommends \
            ${KERNEL_PACKAGES} \
            ${BASE_LANGUAGE_PACKAGES} \
            ${XFCE_LANGUAGE_PACKAGES} \
            virtualbox-guest-additions-iso \
            virtualbox-guest-utils \
            virtualbox-guest-x11
    else
        pkg_install --no-install-recommends \
            ${KERNEL_PACKAGES} \
            ${BASE_LANGUAGE_PACKAGES} \
            ${XFCE_LANGUAGE_PACKAGES} \
            virtualbox-guest-additions-iso \
            virtualbox-guest-utils \
            virtualbox-guest-x11
    fi
    
    log_info "Xfce Desktop-Installation abgeschlossen"
}

# Installiere zusätzliche Software
install_additional_software() {
    log_info "Prüfe auf zusätzliche Software-Installation..."
    
    # Thorium Browser installieren
    if [ "${INSTALL_DESKTOP}" = "1" ] && [ -f /tmp/thorium.deb ]; then
        log_info "Thorium-Browser-Paket gefunden, installiere..."
        
        # Installation mit apt, das Abhängigkeiten automatisch auflöst
        log_info "Installiere Thorium-Browser..."
        if apt install -y --fix-broken /tmp/thorium.deb; then
            log_info "Thorium wurde erfolgreich installiert."
        else
            log_warn "Thorium-Installation über apt fehlgeschlagen, versuche alternativen Ansatz..."
            # Abhängigkeiten beheben und erneut versuchen
            apt -f install -y
            if dpkg -i /tmp/thorium.deb; then
                log_info "Thorium wurde im zweiten Versuch erfolgreich installiert."
            else
                log_warn "Thorium-Installation fehlgeschlagen."
            fi
        fi
        
        # Überprüfen, ob die Installation tatsächlich erfolgreich war
        if [ -f /usr/bin/thorium-browser ]; then
            log_info "Thorium-Browser wurde erfolgreich installiert und ist unter /usr/bin/thorium-browser verfügbar."
        else
            log_warn "Thorium-Installation konnte nicht abgeschlossen werden."
        fi
        
        # Aufräumen
        rm -f /tmp/thorium.deb
    fi
    
    return 0
}

# Systemd-Dienste konfigurieren
configure_systemd_services() {
    log_info "Konfiguriere Systemd-Dienste..."
    
    # Deaktiviere unerwünschte Systemd-Dienste
    log_info "Deaktiviere unerwünschte Systemd-Dienste..."
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
    
    return 0
}

# System-Cleanup
cleanup_system() {
    log_info "Bereinige temporäre Dateien..."
    pkg_clean
    pkg_autoremove
    rm -f /setup_system.sh
    
    return 0
}

# Hauptfunktion
main() {
    log_info "===== Starte System-Setup: $(date) ====="
    
    # Grundlegende Systemkonfiguration
    setup_network || log_error "Netzwerkkonfiguration fehlgeschlagen"
    setup_localization || log_error "Lokalisierungskonfiguration fehlgeschlagen"
    # setup_nala_mirrors || log_error "Nala Spiegelserver-Optimierung fehlgeschlagen"
    setup_automatic_updates || log_error "Einrichten von automatischen Aktualisierungen fehlgeschlagen"
    update_system || log_error "System-Aktualisierung fehlgeschlagen"
    setup_external_repositories || log_error "Repository-Konfiguration fehlgeschlagen"
    
    # Kerninstallation, wenn kein Desktop ausgewählt ist
    install_kernel || log_error "Kernel-Installation fehlgeschlagen"
    
    # LUKS und Boot-Setup
    setup_luks_encryption || log_error "LUKS-Konfiguration fehlgeschlagen"
    setup_grub || log_error "GRUB-Konfiguration fehlgeschlagen"
    setup_zram_swap || log_error "ZRAM-Konfiguration fehlgeschlagen"
    
    # Benutzer einrichten
    setup_users || log_error "Benutzereinrichtung fehlgeschlagen"
    
    # Desktop-Umgebung installieren
    install_desktop_environment || log_error "Desktop-Installation fehlgeschlagen"
    
    # Zusätzliche Software
    install_additional_software || log_error "Software-Installation fehlgeschlagen"
    
    # Systemd-Dienste
    configure_systemd_services || log_error "Systemd-Konfiguration fehlgeschlagen"
    
    # Bereinigung
    cleanup_system || log_error "System-Bereinigung fehlgeschlagen"
    
    log_info "===== System-Setup erfolgreich abgeschlossen: $(date) ====="
    return 0
}

# Skript ausführen
main "$@" || log_error "System-Setup fehlgeschlagen, fahre trotzdem fort"