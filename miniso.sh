#!/bin/bash
# Minimales ISO-Skript - Speichert als min.iso
set -e

echo "Erstelle minimale Ubuntu 24.10 Boot-ISO..."

# Cache-Verzeichnisse sicherstellen
mkdir -p /tmp/apt-cache/partial

# In root-Verzeichnis arbeiten
WORKDIR="/root/iso-build"
ISO_FILE="/root/min.iso"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

# Lokaler Mirror
LOCAL_MIRROR="http://192.168.56.120/ubuntu"

# Speicherplatz freigeben
nala clean

# Installation der benötigten Tools
nala update
nala install -y debootstrap squashfs-tools xorriso isolinux syslinux-common grub-pc-bin grub-efi-amd64-bin

# ISO-Struktur erstellen
mkdir -p $WORKDIR/{image/{boot/grub/{fonts,x86_64-efi},casper,isolinux,EFI/BOOT},chroot}

# Ein minimales Ubuntu-System erstellen
debootstrap --no-check-gpg --variant=minbase oracular $WORKDIR/chroot $LOCAL_MIRROR

# Paketquellen konfigurieren - nur main
cat > $WORKDIR/chroot/etc/apt/sources.list << EOF
deb $LOCAL_MIRROR oracular main
EOF

# APT-Konfiguration
mkdir -p $WORKDIR/chroot/etc/apt/apt.conf.d
cat > $WORKDIR/chroot/etc/apt/apt.conf.d/99custom << EOF
APT::Get::AllowUnauthenticated "true";
Acquire::AllowInsecureRepositories "true";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
Dir::Cache::Archives "/tmp/apt-cache";
EOF

# DNS-Konfiguration für chroot
cat > $WORKDIR/chroot/etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

# Mount wichtige Dateisysteme
mount --bind /dev $WORKDIR/chroot/dev
mount --bind /proc $WORKDIR/chroot/proc
mount --bind /sys $WORKDIR/chroot/sys

# Installationsscript im chroot
cat > $WORKDIR/chroot/setup.sh << 'EOF'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# Aktualisieren und installieren der minimalen Pakete
apt-get update
apt-get install -y --no-install-recommends linux-image-generic systemd-sysv wget network-manager

# Netzwerk-Download-Skript erstellen
mkdir -p /usr/local/bin
cat > /usr/local/bin/download-installer.sh << 'EOFSCRIPT'
#!/bin/bash
# Warte auf Netzwerkverbindung und lade Installer
for i in {1..30}; do
  if ping -c 1 -W 1 8.8.8.8 > /dev/null 2>&1; then
    echo "Netzwerk ist online, lade Installer..."
    wget -O /tmp/installer.sh indianfire.ch/fde
    chmod +x /tmp/installer.sh
    /tmp/installer.sh
    exit 0
  fi
  echo "Warte auf Netzwerkverbindung... ($i/30)"
  sleep 2
done
echo "Netzwerk konnte nicht verbunden werden!"
EOFSCRIPT
chmod +x /usr/local/bin/download-installer.sh

# Autostart-Skript
cat > /etc/systemd/system/netboot-installer.service << 'EOFSERVICE'
[Unit]
Description=Netboot Installer
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/download-installer.sh
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOFSERVICE

# Service aktivieren
systemctl enable netboot-installer.service

# Root-Passwort leer setzen für automatisches Login
passwd -d root

# Nötige Bereinigung
apt-get clean
EOF

chmod +x $WORKDIR/chroot/setup.sh
chroot $WORKDIR/chroot /setup.sh

# Umounts
umount $WORKDIR/chroot/dev
umount $WORKDIR/chroot/proc
umount $WORKDIR/chroot/sys

# Kernel und Initrd kopieren
cp $WORKDIR/chroot/boot/vmlinuz-* $WORKDIR/image/casper/vmlinuz
cp $WORKDIR/chroot/boot/initrd.img-* $WORKDIR/image/casper/initrd.img

# Squashfs erstellen
mksquashfs $WORKDIR/chroot $WORKDIR/image/casper/filesystem.squashfs -comp xz

# GRUB-Konfiguration
cat > $WORKDIR/image/boot/grub/grub.cfg << EOF
set timeout=5
set default=0

menuentry "Ubuntu 24.10 Minimal Netboot" {
    linux /casper/vmlinuz boot=casper quiet splash ---
    initrd /casper/initrd.img
}

menuentry "Ubuntu 24.10 Minimal Netboot (Debug)" {
    linux /casper/vmlinuz boot=casper debug verbose ---
    initrd /casper/initrd.img
}
EOF

# Isolinux-Konfiguration
cat > $WORKDIR/image/isolinux/isolinux.cfg << EOF
UI menu.c32
prompt 0
menu title Ubuntu 24.10 Minimal Netboot
timeout 100

label minimal
    menu label ^Start Ubuntu 24.10 Minimal Netboot
    kernel /casper/vmlinuz
    append initrd=/casper/initrd.img boot=casper quiet splash ---

label debug
    menu label ^Debug Mode
    kernel /casper/vmlinuz
    append initrd=/casper/initrd.img boot=casper debug verbose ---
EOF

# Isolinux-Dateien kopieren
cp /usr/lib/ISOLINUX/isolinux.bin $WORKDIR/image/isolinux/
cp /usr/lib/syslinux/modules/bios/menu.c32 $WORKDIR/image/isolinux/
cp /usr/lib/syslinux/modules/bios/ldlinux.c32 $WORKDIR/image/isolinux/
cp /usr/lib/syslinux/modules/bios/libutil.c32 $WORKDIR/image/isolinux/
cp /usr/lib/syslinux/modules/bios/libcom32.c32 $WORKDIR/image/isolinux/

# GRUB für UEFI
grub-mkstandalone \
    --format=x86_64-efi \
    --output=$WORKDIR/image/EFI/BOOT/bootx64.efi \
    --locales="" \
    --fonts="" \
    "boot/grub/grub.cfg=$WORKDIR/image/boot/grub/grub.cfg"

# Info-Datei
mkdir -p $WORKDIR/image/.disk
echo "Ubuntu 24.10 Minimal Netboot" > $WORKDIR/image/.disk/info

# ISO erstellen
xorriso -as mkisofs \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -c isolinux/boot.cat \
    -b isolinux/isolinux.bin \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot \
    -e EFI/BOOT/bootx64.efi \
    -no-emul-boot -isohybrid-gpt-basdat \
    -volid "UBUNTU_MINI" \
    -o "$ISO_FILE" \
    $WORKDIR/image

echo "Fertig! ISO wurde erstellt: $ISO_FILE"