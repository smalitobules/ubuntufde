#!/bin/bash
# Netzwerk-Setup-Skript für UbuntuFDE
# Dieses Skript richtet die Netzwerkverbindung intelligent ein

# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Netzwerkschnittstellen ermitteln
get_network_interfaces() {
  local interfaces=()
  local i=0
  
  echo -e "${YELLOW}Verfügbare Netzwerkschnittstellen:${NC}"
  echo "--------------------------------------------"
  
  while read -r iface flags; do
    if [[ "$iface" != "lo:" && "$iface" != "lo" ]]; then
      # Interface-Name extrahieren
      local if_name=${iface%:}
      
      # IP-Adresse und Status ermitteln
      local ip_info=$(ip -o -4 addr show $if_name 2>/dev/null | awk '{print $4}')
      local status=$(ip -o link show $if_name | grep -o "state [A-Z]*" | cut -d' ' -f2)
      
      # MAC-Adresse ermitteln
      local mac=$(ip -o link show $if_name | awk '{print $17}')
      
      interfaces+=("$if_name")
      echo "$((i+1))) $if_name - Status: $status, IP: ${ip_info:-keine}, MAC: $mac"
      ((i++))
    fi
  done < <(ip -o link show | awk -F': ' '{print $2}')
  
  echo "--------------------------------------------"
  echo -e "${YELLOW}Wähle eine Schnittstelle (1-$i) oder ESC für zurück:${NC}"
  
  # Direktes Einlesen ohne Enter
  local choice
  read -n 1 -s choice
  
  # ESC-Taste abfangen (ASCII 27)
  if [[ $choice == $'\e' ]]; then
    return 255  # Spezialwert für "zurück"
  elif [[ $choice =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$i" ]; then
    echo "${interfaces[$((choice-1))]}"
    return 0
  else
    echo -e "${RED}Ungültige Auswahl${NC}"
    sleep 1
    return 1
  fi
}

# Test ob Internetverbindung besteht
check_internet() {
  if ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Versuche NetworkManager für eine Schnittstelle
try_networkmanager() {
  echo -e "${GREEN}[INFO]${NC} Versuche NetworkManager für automatische Konfiguration..."
  
  # Prüfen, ob NetworkManager läuft
  if ! systemctl is-active NetworkManager >/dev/null 2>&1; then
    systemctl start NetworkManager || service network-manager start
    sleep 3
  fi
  
  # Warte auf automatische Verbindung
  for i in {1..3}; do
    if check_internet; then
      echo -e "${GREEN}[INFO]${NC} NetworkManager hat erfolgreich eine Verbindung hergestellt."
      return 0
    fi
    echo -e "${GREEN}[INFO]${NC} Warte auf NetworkManager Verbindung... ($i/3)"
    sleep 2
  done
  
  echo -e "${YELLOW}[WARN]${NC} NetworkManager konnte keine automatische Verbindung herstellen."
  return 1
}

# Versuche DHCP für eine Schnittstelle
try_dhcp() {
  local iface=$1
  echo -e "${GREEN}[INFO]${NC} Versuche DHCP auf Schnittstelle $iface..."
  
  # Alte IP-Konfiguration und Leases entfernen
  ip addr flush dev "$iface"
  rm -f /var/lib/dhcp/dhclient."$iface".leases 2>/dev/null
  rm -f /var/lib/dhcpcd/"$iface".lease 2>/dev/null
  
  # Interface aktivieren
  ip link set $iface up
  sleep 1
  
  # Bessere Fehlerbehandlung für dhclient
  if command -v dhclient >/dev/null 2>&1; then
    # Versuche dhclient mit Timeout
    timeout 10s dhclient -v -1 $iface || true
  elif command -v dhcpcd >/dev/null 2>&1; then
    # Versuche dhcpcd mit Timeout
    timeout 10s dhcpcd -t 5 $iface || true
  else
    # Fallback: Versuche ip mit DHCP
    echo -e "${YELLOW}[WARN]${NC} Kein DHCP-Client gefunden, versuche direktes ip-DHCP..."
    ip address add 0.0.0.0/0 dev $iface
    timeout 5s ip dhcp client -v start $iface || true
  fi
  
  # Warte kurz und prüfe die Verbindung
  sleep 2
  
  if check_internet; then
    echo -e "${GREEN}[INFO]${NC} DHCP erfolgreich für $iface, Internetverbindung hergestellt."
    return 0
  else
    echo -e "${YELLOW}[WARN]${NC} DHCP für $iface war nicht erfolgreich."
    return 1
  fi
}

# Intelligenter Scan für Netzwerkparameter
scan_network_for_settings() {
  local iface=$1
  echo -e "${GREEN}[INFO]${NC} Führe intelligenten Netzwerkscan für $iface durch..."
  
  # Aktiviere die Schnittstelle
  ip link set $iface up
  sleep 1
  
  # Versuche, Netzwerkinformationen durch passive Überwachung zu erhalten
  # Starte tcpdump im Hintergrund und fange Pakete für 10 Sekunden ab
  if command -v tcpdump >/dev/null 2>&1; then
    echo -e "${GREEN}[INFO]${NC} Überwache Netzwerkverkehr für potenzielle Konfiguration..."
    tcpdump -i $iface -n -v -c 30 2>/dev/null | tee /tmp/tcpdump_output &
    tcpdump_pid=$!
    
    # Warte bis zu 10 Sekunden
    for i in {1..10}; do
      sleep 1
      
      # Überprüfe, ob tcpdump noch läuft
      if ! kill -0 $tcpdump_pid 2>/dev/null; then
        break
      fi
    done
    
    # Töte tcpdump, falls es noch läuft
    kill $tcpdump_pid 2>/dev/null || true
    
    # Versuche, Gateway und Netzmaske zu extrahieren
    potential_gateways=$(grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" /tmp/tcpdump_output | sort | uniq -c | sort -nr | head -5)
    
    # Wenn wir potenzielle Gateways haben, versuche die häufigste IP
    if [ -n "$potential_gateways" ]; then
      gateway=$(echo "$potential_gateways" | head -1 | awk '{print $2}')
      
      # Bestimme den Netzwerkpräfix (erste 3 Oktette)
      network_prefix=$(echo $gateway | cut -d. -f1-3)
      
      # Generiere eine freie IP-Adresse im selben Netzwerk
      for i in {100..200}; do
        potential_ip="${network_prefix}.$i"
        
        # Überprüfe, ob diese IP bereits verwendet wird
        if ! ping -c 1 -W 1 $potential_ip >/dev/null 2>&1; then
          # Diese IP ist wahrscheinlich frei
          echo -e "${GREEN}[INFO]${NC} Potenzielle freie IP gefunden: $potential_ip"
          
          # Konfiguriere mit dieser IP
          ip addr add "${potential_ip}/24" dev $iface
          ip route add default via $gateway dev $iface
          echo "nameserver 8.8.8.8" > /etc/resolv.conf
          echo "nameserver 1.1.1.1" >> /etc/resolv.conf
          
          # Überprüfe, ob wir jetzt eine Verbindung haben
          if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            echo -e "${GREEN}[INFO]${NC} Intelligente Konfiguration erfolgreich!"
            return 0
          else
            # Entferne die Konfiguration wieder
            ip addr del "${potential_ip}/24" dev $iface
          fi
        fi
      done
    fi
  fi
  
  echo -e "${YELLOW}[WARN]${NC} Intelligenter Scan konnte keine passende Konfiguration finden."
  return 1
}

# Hauptfunktion
setup_network() {
  echo -e "${GREEN}[INFO]${NC} Starte Netzwerkkonfiguration..."

  # Prüfe zuerst, ob bereits Internet vorhanden ist
  echo -e "${GREEN}[INFO]${NC} Prüfe ob bereits Internetverbindung besteht..."
  if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
    echo -e "${GREEN}[INFO]${NC} Internetverbindung bereits vorhanden, keine Konfiguration nötig!"
    return 0
  fi
  
  # Versuche erst NetworkManager
  if command -v nmcli >/dev/null 2>&1; then
    if try_networkmanager; then
      return 0
    fi
  fi
  
  # Scannen aller Schnittstellen
  local interfaces=()
  while read -r iface _; do
    if [[ "$iface" != "lo" && "$iface" != "lo:"* ]]; then
      interfaces+=("${iface%:}")
    fi
  done < <(ip -o link show | awk -F': ' '{print $2}')
  
  if [ ${#interfaces[@]} -eq 0 ]; then
    echo -e "${RED}[ERROR]${NC} Keine Netzwerkschnittstellen gefunden."
    return 1
  fi
  
  # Versuche DHCP auf allen Schnittstellen
  for iface in "${interfaces[@]}"; do
    echo -e "${GREEN}[INFO]${NC} Versuche automatisches DHCP auf $iface..."
    if try_dhcp "$iface"; then
      return 0
    fi
  done
  
  echo -e "${YELLOW}[WARN]${NC} Automatische Netzwerkkonfiguration fehlgeschlagen. Bitte manuell konfigurieren."
  return 1
}

# Führe die Netzwerkkonfiguration durch
setup_network