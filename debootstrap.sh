#!/bin/bash

# Farben für Ausgaben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Hilfsfunktionen
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNUNG]${NC} $1"
}

log_error() {
    echo -e "${RED}[FEHLER]${NC} $1"
    exit 1
}

log_progress() {
    echo -e "${BLUE}[FORTSCHRITT]${NC} $1"
}

# Prüfe Netzwerkverbindung
log_info "Prüfe Netzwerkverbindung..."
if ! ping -c 1 -W 2 192.168.56.120 &> /dev/null; then
    log_error "Keine Verbindung zum lokalen Mirror (192.168.56.120)"
fi

# Mountpoint definieren
MOUNTPOINT="/mnt/ubuntu"
[ -d "$MOUNTPOINT" ] || mkdir -p "$MOUNTPOINT"

# GPG-Schlüssel für lokalen Mirror importieren
log_info "Importiere GPG-Schlüssel für lokalen Mirror..."
mkdir -p "$MOUNTPOINT/etc/apt/trusted.gpg.d/"
if ! curl -fsSL http://192.168.56.120/repo-key.gpg | gpg --dearmor -o "$MOUNTPOINT/etc/apt/trusted.gpg.d/local-mirror.gpg"; then
    log_warn "Konnte GPG-Schlüssel nicht importieren. Installation wird trotzdem fortgesetzt."
fi

# Zu inkludierende Pakete definieren
log_info "Definiere Paketliste..."
PACKAGES=(
    curl gnupg ca-certificates sudo locales cryptsetup lvm2 nano vim wget
    apt-transport-https console-setup bash-completion systemd-resolved
    initramfs-tools cryptsetup-initramfs grub-efi-amd64 grub-efi-amd64-signed
    coreutils efibootmgr
)

# Pakete zu kommagetrennter Liste zusammenfügen
PACKAGELIST=$(IFS=,; echo "${PACKAGES[*]}")

# Ubuntu-Version
UBUNTU_CODENAME="oracular"

# Installation durchführen
log_progress "Installiere Ubuntu $UBUNTU_CODENAME Basissystem..."
echo "Installiere Ubuntu $UBUNTU_CODENAME mit debootstrap..."

log_info "Ausführen: debootstrap --include=\"$PACKAGELIST\" --arch=amd64 $UBUNTU_CODENAME $MOUNTPOINT http://192.168.56.120/ubuntu"

debootstrap \
    --include="$PACKAGELIST" \
    --arch=amd64 \
    "$UBUNTU_CODENAME" \
    "$MOUNTPOINT" \
    "http://192.168.56.120/ubuntu"

if [ $? -ne 0 ]; then
    log_error "debootstrap fehlgeschlagen für $UBUNTU_CODENAME"
else
    log_info "debootstrap erfolgreich abgeschlossen"
fi

# Inhalt von debootstrap.log anzeigen, wenn vorhanden
if [ -f "$MOUNTPOINT/debootstrap/debootstrap.log" ]; then
    log_info "Inhalt der debootstrap.log:"
    cat "$MOUNTPOINT/debootstrap/debootstrap.log"
fi

log_info "Installation abgeschlossen."