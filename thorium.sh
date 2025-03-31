#!/bin/bash

# Farbdefinitionen für bessere Lesbarkeit
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Teste Thorium Browser Installation...${NC}"

# CPU-Erweiterungen prüfen
echo -e "${YELLOW}Prüfe CPU-Erweiterungen...${NC}"
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

# Prüfe, ob wichtige Tools installiert sind
for cmd in curl wget jq; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}$cmd ist nicht installiert. Installiere...${NC}"
        apt-get update && apt-get install -y $cmd
    fi
done

# Versuche automatisch die neueste Version zu ermitteln
echo -e "${YELLOW}Ermittle neueste Thorium-Version...${NC}"
THORIUM_VERSION=$(curl -s https://api.github.com/repos/Alex313031/Thorium/releases/latest | jq -r '.tag_name' | sed 's/^M//')
echo "Ermittelte Version: $THORIUM_VERSION"

# Falls jq fehlschlägt, nutze einen Fallback-Ansatz
if [ -z "$THORIUM_VERSION" ]; then
    echo -e "${YELLOW}Versuche alternativen Ansatz zur Ermittlung der Version...${NC}"
    # Prüfe direkt die Releases-Seite
    THORIUM_VERSION=$(curl -s https://github.com/Alex313031/Thorium/releases/latest | grep -o 'M[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1 | sed 's/^M//')
    echo "Ermittelte Version mit Fallback-Methode: $THORIUM_VERSION"
fi

# Download und Installation mit aktueller Version versuchen
if [ -n "$THORIUM_VERSION" ]; then
    echo -e "${GREEN}Verwende Thorium-Version: $THORIUM_VERSION${NC}"
    THORIUM_URL="https://github.com/Alex313031/Thorium/releases/download/M${THORIUM_VERSION}/thorium-browser_${THORIUM_VERSION}_${CPU_EXT}.deb"
    
    echo -e "${YELLOW}Lade Thorium herunter: $THORIUM_URL${NC}"
    if ! wget -O /tmp/thorium.deb "$THORIUM_URL"; then
        echo -e "${RED}Download fehlgeschlagen, versuche generische Version...${NC}"
        # Versuche generische Version ohne CPU-Erweiterung
        THORIUM_URL="https://github.com/Alex313031/Thorium/releases/download/M${THORIUM_VERSION}/thorium-browser_${THORIUM_VERSION}_amd64.deb"
        
        if ! wget -O /tmp/thorium.deb "$THORIUM_URL"; then
            echo -e "${RED}Generischer Download fehlgeschlagen, verwende Fallback-Links...${NC}"
            FALLBACK_VERSION="130.0.6723.174"
            FALLBACK_URL="https://github.com/Alex313031/thorium/releases/download/M${FALLBACK_VERSION}/thorium-browser_${FALLBACK_VERSION}_${CPU_EXT}.deb"
            echo -e "${YELLOW}Versuche Fallback URL: $FALLBACK_URL${NC}"
            
            if ! wget -O /tmp/thorium.deb "$FALLBACK_URL"; then
                echo -e "${RED}Auch Fallback fehlgeschlagen, Installation von Thorium übersprungen.${NC}"
                exit 1
            fi
        fi
    fi
else
    # Bei Fehler bei der Versionsermittlung direkt zu Fallback-Links
    echo -e "${RED}Versionsermittlung fehlgeschlagen, verwende Fallback-Links...${NC}"
    FALLBACK_VERSION="130.0.6723.174"
    FALLBACK_URL="https://github.com/Alex313031/thorium/releases/download/M${FALLBACK_VERSION}/thorium-browser_${FALLBACK_VERSION}_${CPU_EXT}.deb"
    echo -e "${YELLOW}Versuche Fallback URL: $FALLBACK_URL${NC}"
    
    if ! wget -O /tmp/thorium.deb "$FALLBACK_URL"; then
        echo -e "${RED}Fallback-Download fehlgeschlagen, Installation von Thorium übersprungen.${NC}"
        exit 1
    fi
fi

# Installation ausführen
if [ -f /tmp/thorium.deb ]; then
    echo -e "${GREEN}Download erfolgreich, installiere Thorium...${NC}"
    apt-get install -y /tmp/thorium.deb
    rm /tmp/thorium.deb
    echo -e "${GREEN}Installation abgeschlossen.${NC}"
else
    echo -e "${RED}Download fehlgeschlagen, keine Thorium-Datei zum Installieren.${NC}"
    exit 1
fi