#!/bin/bash
# Thorium Browser Installer
# Ein Standalone-Skript zur Installation des Thorium Browsers

# Logdatei einrichten im aktuellen Verzeichnis
LOG_FILE="$(pwd)/thorium_install_$(date +%Y%m%d_%H%M%S).log"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

# Alle Ausgaben in die Logdatei umleiten und gleichzeitig im Terminal anzeigen
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
    exit 1
}

# Überprüfe die Ausführung mit erhöhten Rechten
if [ "$(id -u)" -ne 0 ]; then
    echo "[HINWEIS] Dieses Skript benötigt Administrative-Rechte. Starte neu mit erhöhten Rechten..."
    exec sudo "$0" "$@"  # Starte das Skript neu mit erhöhten Rechten...
fi

log_info "Thorium Browser Installation startet am $(date)"
log_info "Alle Ausgaben werden in $LOG_FILE protokolliert"
echo ""

# CPU-Erweiterungen prüfen
log_info "Prüfe CPU-Erweiterungen..."
if grep -q " avx2 " /proc/cpuinfo; then
    CPU_EXT="AVX2"
elif grep -q " avx " /proc/cpuinfo; then
    CPU_EXT="AVX"
elif grep -q " sse4_1 " /proc/cpuinfo; then
    CPU_EXT="SSE4"
else
    CPU_EXT="SSE3"
fi
log_info "CPU-Erweiterung erkannt: ${CPU_EXT}"

# Thorium-Version und direkter Download
THORIUM_VERSION="130.0.6723.174"
THORIUM_URL="https://github.com/Alex313031/thorium/releases/download/M${THORIUM_VERSION}/thorium-browser_${THORIUM_VERSION}_${CPU_EXT}.deb"
log_info "Download-URL: ${THORIUM_URL}"

# Download des Thorium-Pakets
log_info "Downloade Thorium Browser..."
TMP_DIR="/tmp/thorium-installer"
mkdir -p "$TMP_DIR"
THORIUM_DEB="$TMP_DIR/thorium.deb"

if wget -q --show-progress --progress=bar:force:noscroll --tries=3 --timeout=10 -O "$THORIUM_DEB" "${THORIUM_URL}"; then
    log_info "Download erfolgreich"
    chmod 644 "$THORIUM_DEB"

    # Installation
    log_info "Installiere Thorium Browser..."
    if dpkg -i "$THORIUM_DEB"; then
        log_info "Thorium wurde erfolgreich installiert."
    else
        log_info "Behebe fehlende Abhängigkeiten..."
        apt update
        apt install -f -y
        
        # Erneuter Installationsversuch
        if dpkg -i "$THORIUM_DEB"; then
            log_info "Thorium wurde erfolgreich installiert."
        else
            log_error "Thorium-Installation fehlgeschlagen!"
        fi
    fi
    
    # Aufräumen
    rm -f "$THORIUM_DEB"
    rmdir "$TMP_DIR" || true
    
    log_info "Installation abgeschlossen!"
else
    log_error "Download fehlgeschlagen!"
fi