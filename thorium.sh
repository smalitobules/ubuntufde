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
    
    echo -e "${YELLOW}Versuche Download von: $THORIUM_URL${NC}"
    if ! wget --spider "$THORIUM_URL" 2>/dev/null; then
        echo -e "${RED}URL nicht erreichbar, versuche generische Version...${NC}"
        # Versuche generische Version ohne CPU-Erweiterung
        THORIUM_URL="https://github.com/Alex313031/Thorium/releases/download/M${THORIUM_VERSION}/thorium-browser_${THORIUM_VERSION}_amd64.deb"
        
        if ! wget --spider "$THORIUM_URL" 2>/dev/null; then
            echo -e "${RED}Generische URL auch nicht erreichbar, verwende Fallback-Links...${NC}"
            FALLBACK_VERSION="130.0.6723.174"
            FALLBACK_URL="https://github.com/Alex313031/thorium/releases/download/M${FALLBACK_VERSION}/thorium-browser_${FALLBACK_VERSION}_${CPU_EXT}.deb"
            echo -e "${YELLOW}Prüfe Fallback URL: $FALLBACK_URL${NC}"
            
            if ! wget --spider "$FALLBACK_URL" 2>/dev/null; then
                echo -e "${RED}Auch Fallback URL nicht erreichbar.${NC}"
            else
                echo -e "${GREEN}Fallback URL erreichbar!${NC}"
                THORIUM_URL="$FALLBACK_URL"
            fi
        } else {
            echo -e "${GREEN}Generische URL erreichbar!${NC}"
        }
    } else {
        echo -e "${GREEN}URL erreichbar!${NC}"
    }
else
    # Bei Fehler bei der Versionsermittlung direkt zu Fallback-Links
    echo -e "${RED}Versionsermittlung fehlgeschlagen, verwende Fallback-Links...${NC}"
    FALLBACK_VERSION="130.0.6723.174"
    FALLBACK_URL="https://github.com/Alex313031/thorium/releases/download/M${FALLBACK_VERSION}/thorium-browser_${FALLBACK_VERSION}_${CPU_EXT}.deb"
    echo -e "${YELLOW}Prüfe Fallback URL: $FALLBACK_URL${NC}"
    
    if ! wget --spider "$FALLBACK_URL" 2>/dev/null; then
        echo -e "${RED}Fallback URL nicht erreichbar.${NC}"
    else
        echo -e "${GREEN}Fallback URL erreichbar!${NC}"
        THORIUM_URL="$FALLBACK_URL"
    fi
fi

echo -e "${YELLOW}Finale Download URL: $THORIUM_URL${NC}"

# Im Test-Modus den tatsächlichen Download und die Installation überspringen
read -p "Möchtest du Thorium tatsächlich herunterladen und installieren? (j/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Jj]$ ]]; then
    echo -e "${YELLOW}Lade Thorium herunter...${NC}"
    wget -O /tmp/thorium.deb "$THORIUM_URL"
    
    if [ -f /tmp/thorium.deb ]; then
        echo -e "${GREEN}Download erfolgreich, installiere Thorium...${NC}"
        apt-get install -y /tmp/thorium.deb
        rm /tmp/thorium.deb
        echo -e "${GREEN}Installation abgeschlossen.${NC}"
    else
        echo -e "${RED}Download fehlgeschlagen.${NC}"
    fi
else
    echo -e "${YELLOW}Test abgeschlossen ohne Download/Installation.${NC}"
fi