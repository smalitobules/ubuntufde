#!/bin/bash

# Thorium Installation Test Skript
# Erstellt eine detaillierte Logdatei im aktuellen Verzeichnis

# Log-Datei einrichten
LOG_FILE="$(pwd)/thorium.log"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

# Alle Ausgaben in die Logdatei umleiten und gleichzeitig im Terminal anzeigen
exec > >(tee -a "$LOG_FILE") 2>&1

# Log-Funktion
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "===== Thorium Browser Installation Test ====="
log "Systeminformationen:"
log "$(uname -a)"
log "CPU-Info: $(grep "model name" /proc/cpuinfo | head -n1 | cut -d':' -f2 | sed 's/^ *//')"
log "Arbeitsspeicher: $(free -h | grep Mem | awk '{print $2}')"
log "Freier Speicher: $(df -h . | tail -n1 | awk '{print $4}')"

# CPU-Erweiterungen prüfen
log "Prüfe CPU-Erweiterungen..."
if grep -q " avx2 " /proc/cpuinfo; then
    CPU_EXT="AVX2"
elif grep -q " avx " /proc/cpuinfo; then
    CPU_EXT="AVX"
elif grep -q " sse4_1 " /proc/cpuinfo; then
    CPU_EXT="SSE4"
else
    CPU_EXT="SSE3"
fi
log "CPU-Erweiterung erkannt: ${CPU_EXT}"

# Thorium-Version und direkter Download
THORIUM_VERSION="130.0.6723.174"
THORIUM_URL="https://github.com/Alex313031/thorium/releases/download/M${THORIUM_VERSION}/thorium-browser_${THORIUM_VERSION}_${CPU_EXT}.deb"
log "Download-URL: ${THORIUM_URL}"

# Temp-Verzeichnis erstellen
TMP_DIR=$(mktemp -d)
log "Temporäres Verzeichnis: ${TMP_DIR}"

# Download mit reduzierter Ausgabe (wie in UbuntuFDE)
log "Starte Download..."
if wget -q --show-progress --progress=bar:force:noscroll --tries=3 --timeout=10 -O "${TMP_DIR}/thorium.deb" "${THORIUM_URL}"; then
    log "Download erfolgreich"
    chmod 644 "${TMP_DIR}/thorium.deb"
else
    log "FEHLER: Download fehlgeschlagen!"
    exit 1
fi

# Prüfe Dateiintegriät
log "Prüfe Dateiintegrität..."
log "Dateigröße: $(ls -lh ${TMP_DIR}/thorium.deb | awk '{print $5}')"
log "Datei-Hash: $(sha256sum ${TMP_DIR}/thorium.deb | awk '{print $1}')"

# Extrahiere Paketinformationen
log "Extrahiere Paketinformationen..."
dpkg-deb -I "${TMP_DIR}/thorium.deb" 2>&1

# Abhängigkeiten ermitteln
log "Ermittle Abhängigkeiten..."
DEPENDS=$(dpkg-deb -f "${TMP_DIR}/thorium.deb" Depends | tr ',' '\n')
log "Abhängigkeiten:"
log "$DEPENDS"

# Prüfe, ob alle Abhängigkeiten installiert sind
log "Prüfe, ob alle Abhängigkeiten installiert sind..."
for dep in $(echo "$DEPENDS" | sed -e 's/([^)]*)//g' -e 's/|/ /g' | tr -d ' '); do
    pkg=$(echo $dep | cut -d':' -f1)
    if dpkg -s "$pkg" 2>/dev/null | grep -q "Status: install ok installed"; then
        log "✓ $pkg ist installiert"
    else
        log "✗ $pkg ist NICHT installiert"
    fi
done

# Installation mit dpkg
log "===== INSTALLATION METHODE 1: DPKG direkt ====="
log "Führe Installation mit dpkg aus..."
dpkg -i "${TMP_DIR}/thorium.deb" 2>&1
DPKG_STATUS=$?
log "Installation mit dpkg Status: ${DPKG_STATUS}"

# Bereinige ggf. gescheiterte Installation
if [ $DPKG_STATUS -ne 0 ]; then
    log "Installation mit dpkg fehlgeschlagen. Bereinige..."
    dpkg --remove --force-remove-reinstreq thorium-browser 2>&1 || true
fi

# Installation mit apt
log "===== INSTALLATION METHODE 2: APT mit Pfad ====="
log "Führe Installation mit apt und Paketpfad aus..."
apt-get update
apt-get install -y "${TMP_DIR}/thorium.deb" 2>&1
APT_PATH_STATUS=$?
log "Installation mit apt (Pfad) Status: ${APT_PATH_STATUS}"

# Bereinige ggf. gescheiterte Installation
if [ $APT_PATH_STATUS -ne 0 ]; then
    log "Installation mit apt (Pfad) fehlgeschlagen. Bereinige..."
    apt-get remove -y thorium-browser 2>&1 || true
    apt-get autoremove -y 2>&1
fi

# Installation mit apt fix-broken
log "===== INSTALLATION METHODE 3: DPKG + APT fix-broken ====="
log "Führe Installation mit dpkg und apt fix-broken aus..."
dpkg -i "${TMP_DIR}/thorium.deb" 2>&1 || true
apt-get install -f -y 2>&1
FIX_BROKEN_STATUS=$?
log "Installation mit fix-broken Status: ${FIX_BROKEN_STATUS}"

# Prüfe das Endergebnis
log "===== INSTALLATION ERGEBNISSE ====="
if dpkg -s thorium-browser 2>/dev/null | grep -q "Status: install ok installed"; then
    log "✓ Thorium Browser ist erfolgreich installiert"
    log "Installierte Version: $(dpkg -s thorium-browser | grep Version | cut -d' ' -f2)"
    log "Installationspfad: $(whereis thorium-browser)"
    log "Desktop-Eintrag: $(ls -l /usr/share/applications/thorium-browser.desktop 2>/dev/null || echo 'Nicht gefunden')"
else
    log "✗ Thorium Browser ist NICHT installiert"
fi

# Aufräumen
log "Räume auf..."
rm -rf "${TMP_DIR}"
log "Test abgeschlossen."