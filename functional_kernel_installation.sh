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