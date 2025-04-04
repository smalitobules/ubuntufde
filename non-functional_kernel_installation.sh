# Notwendige Pakete installieren 
echo "Installiere Basis-Pakete..."
KERNEL_PACKAGES=""
if [ "${KERNEL_TYPE}" = "standard" ]; then
    KERNEL_PACKAGES="linux-image-generic linux-headers-generic"
elif [ "${KERNEL_TYPE}" = "lowlatency" ]; then
    KERNEL_PACKAGES="linux-image-lowlatency linux-headers-lowlatency"
fi

# Grundlegende Tools installieren
TOOLS=(
    $KERNEL_PACKAGES # Wahrscheinlich ist das-> \${KERNEL_PACKAGES} \ <-die Lösung!
    #shim-signed timeshift bleachbit coreutils stacer
    #fastfetch gparted vlc deluge ufw zram-tools nala jq
)

apt-get install -y --no-install-recommends "${TOOLS[@]}"