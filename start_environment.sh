#!/bin/bash
# UbuntuFDE Umgebung
# Dieses Skript startet die UbuntuFDE Umgebung

# Erweiterte Debug-Konfiguration
set -x  # Tracing aktivieren
set -euo pipefail  # Strikte Fehlerbehandlung

# Explizite Locale-Konfiguration
export LC_ALL=de_DE.UTF-8
export LANG=de_DE.UTF-8
export LANGUAGE=de_DE.UTF-8

# Debug-Logging-Funktion
debug_log() {
    local message="$1"
    echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - $message" >&2
}

# Erweiterte Fehlerbehandlung
trap 'debug_log "Fehler in Zeile $LINENO"' ERR

# Shell-Konfiguration vereinheitlichen
set -o posix       # POSIX-Kompatibilitätsmodus
set -u             # Behandle nicht gesetzte Variablen als Fehler
set -e             # Beende Skript bei Fehlern
shopt -s nocaseglob  # Case-insensitive Globbing
shopt -s extglob     # Erweiterte Globbing-Funktionen

# Explizite Locale-Einstellungen
export LC_ALL=de_DE.UTF-8
export LANG=de_DE.UTF-8
export LANGUAGE=de_DE.UTF-8

# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Standardwerte
INSTALLATION_URL="https://zenayastudios.com/fde"
SELECTED_LANGUAGE="de_DE.UTF-8"
SELECTED_KEYBOARD="de"

# Sprachauswahl-Dialog
select_language() {
  clear
  echo -e "${CYAN}=======================================${NC}"
  echo -e "${CYAN}       UbuntuFDE Umgebung              ${NC}"
  echo -e "${CYAN}=======================================${NC}"
  echo
  echo -e "${YELLOW}Bitte wähle die Anzeigesprache / Please select display language:${NC}"
  echo
  echo "1) Deutsch (Standard)"
  echo "2) English"
  echo
  echo -n "Auswahl/Choice [1]: "
  read -n 1 lang_choice
  echo
  
  case ${lang_choice:-1} in
    1|""|"Deutsch"|"deutsch")
      SELECTED_LANGUAGE="de_DE.UTF-8"
      echo -e "${GREEN}Deutsch ausgewählt${NC}"
      ;;
    2|"English"|"english")
      SELECTED_LANGUAGE="en_US.UTF-8"
      echo -e "${GREEN}English selected${NC}"
      ;;
    *)
      SELECTED_LANGUAGE="de_DE.UTF-8"
      echo -e "${YELLOW}Unbekannte Auswahl, Deutsch wird verwendet${NC}"
      ;;
  esac
  
  # Sprache temporär setzen
  export LANG=$SELECTED_LANGUAGE
  sleep 1
}

# Tastaturlayout-Auswahl
select_keyboard() {
  clear
  echo -e "${CYAN}=======================================${NC}"
  echo -e "${CYAN}       UbuntuFDE Umgebung              ${NC}"
  echo -e "${CYAN}=======================================${NC}"
  echo
  
  if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
    echo -e "${YELLOW}Bitte wähle dein Tastaturlayout:${NC}"
    echo
    echo "1) Deutsch - Deutschland (Standard)"
    echo "2) Deutsch - Schweiz"
    echo "3) Deutsch - Österreich"
    echo "4) Englisch - US"
    echo
    echo -n "Auswahl [1]: "
    read -n 1 kb_choice
    echo
    
    case ${kb_choice:-1} in
      1|"")
        SELECTED_KEYBOARD="de"
        echo -e "${GREEN}Tastaturlayout: Deutsch (Deutschland)${NC}"
        ;;
      2)
        SELECTED_KEYBOARD="ch"
        echo -e "${GREEN}Tastaturlayout: Deutsch (Schweiz)${NC}"
        ;;
      3)
        SELECTED_KEYBOARD="at"
        echo -e "${GREEN}Tastaturlayout: Deutsch (Österreich)${NC}"
        ;;
      4)
        SELECTED_KEYBOARD="us"
        echo -e "${GREEN}Tastaturlayout: Englisch (US)${NC}"
        ;;
      *)
        SELECTED_KEYBOARD="de"
        echo -e "${YELLOW}Unbekannte Auswahl, Deutsch (Deutschland) wird verwendet${NC}"
        ;;
    esac
  else
    echo -e "${YELLOW}Please select your keyboard layout:${NC}"
    echo
    echo "1) English - US (Default)"
    echo "2) German - Germany" 
    echo "3) German - Switzerland"
    echo "4) German - Austria"
    echo
    echo -n "Selection [1]: "
    read -n 1 kb_choice
    echo
    
    case ${kb_choice:-1} in
      1|"")
        SELECTED_KEYBOARD="us"
        echo -e "${GREEN}Keyboard layout: English (US)${NC}"
        ;;
      2)
        SELECTED_KEYBOARD="de"
        echo -e "${GREEN}Keyboard layout: German (Germany)${NC}"
        ;;
      3)
        SELECTED_KEYBOARD="ch"
        echo -e "${GREEN}Keyboard layout: German (Switzerland)${NC}"
        ;;
      4)
        SELECTED_KEYBOARD="at"
        echo -e "${GREEN}Keyboard layout: German (Austria)${NC}"
        ;;
      *)
        SELECTED_KEYBOARD="us"
        echo -e "${YELLOW}Unknown selection, using English (US)${NC}"
        ;;
    esac
  fi
  
  # Tastaturlayout sofort aktivieren
  loadkeys ${SELECTED_KEYBOARD} 2>/dev/null
  sleep 1
}

# Netzwerkverbindungseinrichtung
setup_network() {
  local return_to_menu=0
  
  while [ $return_to_menu -eq 0 ]; do
    clear
    echo -e "${CYAN}=======================================${NC}"
    echo -e "${CYAN}       UbuntuFDE Umgebung              ${NC}"
    echo -e "${CYAN}=======================================${NC}"
    echo
    
    if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
      echo -e "${YELLOW}Netzwerkverbindung einrichten:${NC}"
      echo "1) Automatische Konfiguration versuchen (DHCP)"
      echo "2) Manuell konfigurieren"
      echo
      echo -n "Auswahl [1]: "
    else
      echo -e "${YELLOW}Configure network connection:${NC}"
      echo "1) Try automatic configuration (DHCP)"
      echo "2) Configure manually"
      echo
      echo -n "Selection [1]: "
    fi
    
    read -n 1 config_method
    echo
    
    case ${config_method:-1} in
      2)
        # Manuelle Konfiguration
        manual_network_setup
        local manual_result=$?
        
        # Wenn ESC gedrückt wurde (manual_result=1), zurück zum Menü
        if [ $manual_result -eq 1 ]; then
          continue  # Zurück zum Anfang der Schleife
        elif [ $manual_result -eq 0 ]; then
          # Erfolgreiche Konfiguration
          return 0
        else
          # Fehlerfall
          if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
            echo -e "${YELLOW}Netzwerkkonfiguration unvollständig.${NC}"
            echo -e "${YELLOW}Möchtest du es erneut versuchen? (j/n) [j]:${NC}"
          else
            echo -e "${YELLOW}Network configuration incomplete.${NC}"
            echo -e "${YELLOW}Would you like to try again? (y/n) [y]:${NC}"
          fi
          read -n 1 retry
          echo
          
          case ${retry:-j} in
            j|J|y|Y|"")
              continue  # Zurück zum Menü
              ;;
            *)
              # Trotz Absage wieder zurück zum Menü
              if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
                echo -e "${RED}Ohne Netzwerkverbindung ist diese ISO-Umgebung nicht funktionsfähig.${NC}"
                echo -e "${YELLOW}Kehre zum Netzwerkmenü zurück...${NC}"
              else
                echo -e "${RED}Without network connection, this ISO environment is not functional.${NC}"
                echo -e "${YELLOW}Returning to network menu...${NC}"
              fi
              sleep 2
              continue  # Zurück zum Menü statt Beenden
              ;;
          esac
        fi
        ;;
      *)
        # Automatische Konfiguration
        if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
          echo -e "${YELLOW}Richte Netzwerkverbindung ein...${NC}"
        else
          echo -e "${YELLOW}Setting up network connection...${NC}"
        fi
        echo
        
        # Führe das Netzwerk-Setup-Skript aus
        bash /opt/ubuntufde/network_setup.sh
        NETWORK_SETUP_RESULT=$?
        
        # Überprüfe, ob die Netzwerkverbindung hergestellt wurde
        if [ $NETWORK_SETUP_RESULT -ne 0 ] || ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
          if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
            echo -e "${RED}Automatische Netzwerkkonfiguration fehlgeschlagen.${NC}"
            echo -e "${YELLOW}Möchtest du das Netzwerk manuell konfigurieren?${NC}"
            echo -n "Manuelle Konfiguration starten? (j/n) [j]: "
            read -n 1 manual_config
            echo
          else
            echo -e "${RED}Automatic network configuration failed.${NC}"
            echo -e "${YELLOW}Would you like to configure the network manually?${NC}"
            read -p "Start manual configuration? (y/n) [y]: " manual_config
          fi
          
          case ${manual_config:-j} in
            j|J|y|Y|"")
              manual_network_setup
              local manual_result=$?
              
              # Wenn ESC gedrückt wurde, zurück zum Menü
              if [ $manual_result -eq 1 ]; then
                continue  # Zurück zum Anfang der Schleife
              elif [ $manual_result -eq 0 ]; then
                # Erfolgreiche Konfiguration
                return 0
              else
                # Fehlerfall - trotzdem zum Menü zurückkehren
                if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
                  echo -e "${YELLOW}Netzwerkkonfiguration nicht abgeschlossen.${NC}"
                  echo -e "${YELLOW}Kehre zum Netzwerkmenü zurück...${NC}"
                else
                  echo -e "${YELLOW}Network configuration not completed.${NC}"
                  echo -e "${YELLOW}Returning to network menu...${NC}"
                fi
                sleep 2
                continue  # Zurück zum Menü, nie beenden
              fi
              ;;
            *)
              # Benutzer hat "n" gewählt - Erklärung und erneute Chance bieten
              if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
                echo -e "${RED}Achtung: Ohne Netzwerkverbindung kann UbuntuFDE nicht heruntergeladen werden.${NC}"
                echo -e "${YELLOW}Möchtest du zur Netzwerkauswahl zurückkehren? (j/n) [j]: ${NC}"
              else
                echo -e "${RED}Warning: Without network connection, UbuntuFDE cannot be downloaded.${NC}"
                echo -e "${YELLOW}Would you like to return to the network selection? (y/n) [y]: ${NC}"
              fi
              read -n 1 return_choice
              echo
              
              case ${return_choice:-j} in
                j|J|y|Y|"")
                  continue  # Zurück zum Menü
                  ;;
                *)
                  # Selbst bei endgültiger Ablehnung noch eine letzte Chance geben
                  if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
                    echo -e "${RED}Ohne Netzwerkverbindung ist diese ISO-Umgebung nicht funktionsfähig.${NC}"
                    echo -e "${YELLOW}Drücke eine beliebige Taste, um zum Netzwerkmenü zurückzukehren...${NC}"
                  else
                    echo -e "${RED}Without network connection, this ISO environment cannot function.${NC}"
                    echo -e "${YELLOW}Press any key to return to the network menu...${NC}"
                  fi
                  read -n 1
                  continue  # Immer zurück zum Menü, nie beenden
                  ;;
              esac
              ;;
          esac
        else
          # Netzwerk erfolgreich konfiguriert
          return 0
        fi
        ;;
    esac
    
    # Schleife beenden, wenn wir hierher gelangen
    return_to_menu=1
  done
}

# Manuelle Netzwerkkonfiguration
manual_network_setup() {
  # Hauptschleife für die gesamte manuelle Konfiguration
  while true; do
    clear
    echo -e "${CYAN}=======================================${NC}"
    echo -e "${CYAN}     UbuntuFDE Netzwerkkonfiguration   ${NC}"
    echo -e "${CYAN}=======================================${NC}"
    echo
    
    if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
      echo -e "${YELLOW}Verfügbare Netzwerkschnittstellen:${NC}"
    else
      echo -e "${YELLOW}Available network interfaces:${NC}"
    fi
    echo "--------------------------------------------"
    
    local interfaces=()
    local i=0
    
    # Alle Netzwerkschnittstellen ermitteln (außer lo)
    while read -r iface _; do
      if [[ "$iface" != "lo" && "$iface" != "lo:"* ]]; then
        # Interface-Name extrahieren
        local if_name=${iface%:}
        
        # IP-Adresse und Status ermitteln
        local ip_info=$(ip -o -4 addr show $if_name 2>/dev/null | awk '{print $4}')
        if [ -z "$ip_info" ]; then ip_info="keine"; fi
        
        local status=$(ip -o link show $if_name | grep -o "state [A-Z]*" | cut -d' ' -f2)
        
        # MAC-Adresse ermitteln
        local mac=$(ip link show $if_name | grep -o 'link/ether [^ ]*' | cut -d' ' -f2)
        if [ -z "$mac" ]; then mac="unbekannt"; fi
        
        interfaces+=("$if_name")
        
        # Zeige erweiterte Informationen
        if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
          echo "$((i+1))) $if_name - Status: $status, IP: $ip_info, MAC: $mac"
        else
          echo "$((i+1))) $if_name - Status: $status, IP: $ip_info, MAC: $mac"
        fi
        ((i++))
      fi
    done < <(ip -o link show | awk -F': ' '{print $2}')
    
    if [ "${#interfaces[@]}" -eq 0 ]; then
      if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
        echo -e "${RED}Keine Netzwerkschnittstellen gefunden!${NC}"
      else
        echo -e "${RED}No network interfaces found!${NC}"
      fi
      sleep 3
      return 1
    fi
    
    echo "--------------------------------------------"
    if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
      echo -e "${YELLOW}Wähle eine Schnittstelle (1-$i) oder ESC für zurück:${NC}"
    else
      echo -e "${YELLOW}Select an interface (1-$i) or ESC to go back:${NC}"
    fi
    
    # Direktes Einlesen ohne Enter
    local iface_choice
    read -n 1 -s iface_choice
    echo
    
    # ESC-Taste abfangen
    if [[ $iface_choice == $'\e' ]]; then
      if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
        echo -e "${YELLOW}Zurück zum Hauptmenü...${NC}"
      else
        echo -e "${YELLOW}Back to main menu...${NC}"
      fi
      return 1
    fi
    
    # Überprüfe, ob die Eingabe gültig ist
    if ! [[ "$iface_choice" =~ ^[0-9]+$ ]] || [ "$iface_choice" -lt 1 ] || [ "$iface_choice" -gt "${#interfaces[@]}" ]; then
      if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
        echo -e "${RED}Ungültige Auswahl. Bitte erneut versuchen.${NC}"
      else
        echo -e "${RED}Invalid selection. Please try again.${NC}"
      fi
      sleep 1
      continue
    fi
    
    local selected_iface="${interfaces[$((iface_choice-1))]}"
    
    # Schnittstelle aktivieren
    echo
    if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
      echo -e "${GREEN}Schnittstelle ${selected_iface} ausgewählt.${NC}"
    else
      echo -e "${GREEN}Interface ${selected_iface} selected.${NC}"
    fi
    
    # Aktiviere die Schnittstelle, falls sie nicht bereits aktiv ist
    ip link set "$selected_iface" up
    sleep 1
    
    # Unterschleife für Konfigurationsoptionen
    while true; do
      clear
      echo -e "${CYAN}=======================================${NC}"
      echo -e "${CYAN}     UbuntuFDE Netzwerkkonfiguration   ${NC}"
      echo -e "${CYAN}=======================================${NC}"
      echo
      
      if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
        echo -e "${GREEN}Schnittstelle: ${selected_iface}${NC}"
        echo
        echo -e "${YELLOW}Konfigurationsoptionen:${NC}"
        echo "1) DHCP (automatische IP-Konfiguration)"
        echo "2) Statische IP-Konfiguration"
        echo
        echo -e "${YELLOW}Wähle eine Option (1-2) oder ESC für zurück:${NC}"
      else
        echo -e "${GREEN}Interface: ${selected_iface}${NC}"
        echo
        echo -e "${YELLOW}Configuration options:${NC}"
        echo "1) DHCP (automatic IP configuration)"
        echo "2) Static IP configuration"
        echo
        echo -e "${YELLOW}Select an option (1-3) or ESC to go back:${NC}"
      fi
      
      # Direktes Einlesen ohne Enter
      local config_choice
      read -n 1 -s config_choice
      echo
      
      # ESC-Taste abfangen
      if [[ $config_choice == $'\e' ]]; then
        break
      fi
      
      case $config_choice in
        1) # DHCP
          if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
            echo -e "${YELLOW}Prüfe bestehende Internetverbindung...${NC}"
          else
            echo -e "${YELLOW}Checking existing internet connection...${NC}"
          fi
          
          # Zuerst prüfen, ob bereits eine Internetverbindung besteht
          if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
            if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
              echo -e "${GREEN}Internetverbindung bereits vorhanden!${NC}"
              echo -e "${GREEN}Keine DHCP-Konfiguration notwendig.${NC}"
            else
              echo -e "${GREEN}Internet connection already exists!${NC}"
              echo -e "${GREEN}No DHCP configuration necessary.${NC}"
            fi
            sleep 2
            return 0
          else
            # Nur wenn keine Verbindung besteht, DHCP konfigurieren
            if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
              echo -e "${YELLOW}Versuche DHCP-Konfiguration für ${selected_iface}...${NC}"
            else
              echo -e "${YELLOW}Trying DHCP configuration for ${selected_iface}...${NC}"
            fi
            
            # Alte IP-Konfiguration entfernen
            ip addr flush dev "$selected_iface"
            
            # DHCP starten (verbesserte Version)
            if command -v dhclient >/dev/null 2>&1; then
              # Beende vorherige Prozesse
              pkill -f "dhclient.*$selected_iface" 2>/dev/null || true
              sleep 1
              # Starte mit Timeout
              timeout 15s dhclient -v -1 "$selected_iface" || true
            elif command -v dhcpcd >/dev/null 2>&1; then
              # Beende vorherige dhcpcd-Prozesse
              pkill -f "dhcpcd.*$selected_iface" 2>/dev/null || true
              sleep 1
              # Starte mit Timeout
              timeout 15s dhcpcd -t 5 "$selected_iface" || true
            else
              # Alternative: IP direkt konfigurieren
              if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
                echo -e "${YELLOW}Kein DHCP-Client gefunden, versuche Fallback-Methode...${NC}"
              else
                echo -e "${YELLOW}No DHCP client found, trying fallback method...${NC}"
              fi
              ip address add 0.0.0.0/0 dev "$selected_iface" 2>/dev/null
              ip link set "$selected_iface" up
            fi
            
            # Warte kurz und prüfe die Verbindung
            sleep 3
            
            if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
              if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
                echo -e "${GREEN}DHCP erfolgreich für $selected_iface, Internetverbindung hergestellt.${NC}"
              else
                echo -e "${GREEN}DHCP successful for $selected_iface, Internet connection established.${NC}"
              fi
              sleep 2
              return 0
            else
              if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
                echo -e "${RED}DHCP für $selected_iface war nicht erfolgreich.${NC}"
                echo -e "${YELLOW}Drücke eine Taste, um fortzufahren...${NC}"
              else
                echo -e "${RED}DHCP for $selected_iface was not successful.${NC}"
                echo -e "${YELLOW}Press any key to continue...${NC}"
              fi
              read -n 1 -s
            fi
          fi
          ;;
          
        2) # Statische IP
          # Unterschleife für statische IP-Konfiguration
          while true; do
            clear
            echo -e "${CYAN}=======================================${NC}"
            echo -e "${CYAN}   Statische IP-Konfiguration für ${selected_iface}   ${NC}"
            echo -e "${CYAN}=======================================${NC}"
            echo
            
            if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
              echo -e "${YELLOW}Bitte gib die statischen Netzwerkparameter ein:${NC}"
              echo -e "${YELLOW}(Drücke ESC während der Eingabe, um zur vorherigen Seite zurückzukehren)${NC}"
              echo
              
              # Verwende read -e für bearbeitbare Eingabe
              read -p "IP-Adresse (z.B. 192.168.1.100): " -e ip_addr
              
              # Prüfe auf ESC
              if [[ $? -eq 1 ]]; then
                break
              fi
              
              read -p "Netzmaske (z.B. 24 für /24): " -e netmask
              if [[ $? -eq 1 ]]; then
                break
              fi
              
              read -p "Gateway (z.B. 192.168.1.1): " -e gateway
              if [[ $? -eq 1 ]]; then
                break
              fi
              
              read -p "DNS-Server (z.B. 8.8.8.8): " -e dns
              if [[ $? -eq 1 ]]; then
                break
              fi
            else
              echo -e "${YELLOW}Please enter the static network parameters:${NC}"
              echo -e "${YELLOW}(Press ESC during input to return to the previous page)${NC}"
              echo
              
              read -p "IP address (e.g. 192.168.1.100): " -e ip_addr
              if [[ $? -eq 1 ]]; then
                break
              fi
              
              read -p "Netmask (e.g. 24 for /24): " -e netmask
              if [[ $? -eq 1 ]]; then
                break
              fi
              
              read -p "Gateway (e.g. 192.168.1.1): " -e gateway
              if [[ $? -eq 1 ]]; then
                break
              fi
              
              read -p "DNS server (e.g. 8.8.8.8): " -e dns
              if [[ $? -eq 1 ]]; then
                break
              fi
            fi
            
            # Überprüfe, ob alle erforderlichen Parameter eingegeben wurden
            if [ -z "$ip_addr" ] || [ -z "$netmask" ] || [ -z "$gateway" ] || [ -z "$dns" ]; then
              if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
                echo -e "${RED}Unvollständige Netzwerkparameter. Bitte erneut versuchen.${NC}"
              else
                echo -e "${RED}Incomplete network parameters. Please try again.${NC}"
              fi
              sleep 2
              continue
            fi
            
            # Alte IP-Konfiguration entfernen
            ip addr flush dev "$selected_iface"
            
            # Konfiguriere die Netzwerkschnittstelle
            ip link set "$selected_iface" up
            ip addr add "$ip_addr/$netmask" dev "$selected_iface"
            ip route add default via "$gateway" dev "$selected_iface"
            
            # DNS-Server konfigurieren
            echo "nameserver $dns" > /etc/resolv.conf
            
            # Überprüfe die Verbindung
            if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
              if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
                echo -e "${GREEN}Netzwerkverbindung erfolgreich hergestellt.${NC}"
              else
                echo -e "${GREEN}Network connection successfully established.${NC}"
              fi
              sleep 2
              return 0
            else
              if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
                echo -e "${RED}Netzwerkverbindung fehlgeschlagen.${NC}"
                echo -e "${YELLOW}Möchtest du es erneut versuchen? (j/n)${NC}"
              else
                echo -e "${RED}Network connection failed.${NC}"
                echo -e "${YELLOW}Would you like to try again? (y/n)${NC}"
              fi
              
              read -n 1 -s retry
              echo
              
              if [[ "$retry" != "j" && "$retry" != "J" && "$retry" != "y" && "$retry" != "Y" ]]; then
                break
              fi
            fi
          done
          ;;
          
        *)
          if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
            echo -e "${RED}Ungültige Auswahl. Bitte erneut versuchen.${NC}"
          else
            echo -e "${RED}Invalid selection. Please try again.${NC}"
          fi
          sleep 1
          ;;
      esac
    done
  done
}


# UbuntuFDE herunterladen und ausführen
download_and_run() {
  if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
    echo -e "${YELLOW}Lade UbuntuFDE herunter...${NC}"
  else
    echo -e "${YELLOW}Downloading UbuntuFDE script...${NC}"
  fi
  
  # Speichere die ausgewählten Einstellungen in einer temporären Datei
  echo "SELECTED_LANGUAGE=\"$SELECTED_LANGUAGE\"" > /tmp/install_settings.conf
  echo "SELECTED_KEYBOARD=\"$SELECTED_KEYBOARD\"" >> /tmp/install_settings.conf
  
  # Lade das Skript herunter
  if wget -O /tmp/UbuntuFDE.sh "$INSTALLATION_URL"; then
    chmod +x /tmp/UbuntuFDE.sh
    
    if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
      echo -e "${GREEN}Starte UbuntuFDE...${NC}"
    else
      echo -e "${GREEN}Starting UbuntuFDE...${NC}"
    fi
    
    # Führe das Skript mit den gewählten Einstellungen aus
    /tmp/UbuntuFDE.sh --language="$SELECTED_LANGUAGE" --keyboard="$SELECTED_KEYBOARD"
  else
    if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
      echo -e "${RED}Download fehlgeschlagen. Versuche Netzwerk neu einzurichten...${NC}"
    else
      echo -e "${RED}Download failed. Trying to reconfigure network...${NC}"
    fi
    sleep 3
    setup_network
    download_and_run
  fi
}

# Hauptablauf
main() {
  # Sprache und Tastatur wählen
  select_language
  select_keyboard
  
  # Internetverbindung prüfen
  if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
    echo -e "${YELLOW}Prüfe Internetverbindung...${NC}"
  else
    echo -e "${YELLOW}Checking internet connection...${NC}"
  fi
  
  # Test auf bestehende Verbindung
  if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 || ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
    if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
      echo -e "${GREEN}Internetverbindung gefunden!${NC}"
      echo -e "${YELLOW}Fahre mit Download fort...${NC}"
    else
      echo -e "${GREEN}Internet connection found!${NC}"
      echo -e "${YELLOW}Proceeding with download...${NC}"
    fi
    sleep 1
    # Download und Start der UbuntuFDE Umgebung
    download_and_run
  else
    # Keine Verbindung gefunden, Netzwerkkonfiguration starten
    if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
      echo -e "${YELLOW}Keine Internetverbindung gefunden.${NC}"
      echo -e "${YELLOW}Netzwerkkonfiguration wird gestartet...${NC}"
    else
      echo -e "${YELLOW}No internet connection found.${NC}"
      echo -e "${YELLOW}Starting network configuration...${NC}"
    fi
    sleep 1
    
    # Netzwerk einrichten
    setup_network
    NETWORK_RESULT=$?
    
    # Nur wenn Netzwerk konfiguriert wurde
    if [ $NETWORK_RESULT -eq 0 ]; then
      # UbuntuFDE ausführen
      download_and_run
    else
      if [ "$SELECTED_LANGUAGE" = "de_DE.UTF-8" ]; then
        echo -e "${YELLOW}Installation ohne Netzwerkverbindung nicht möglich.${NC}"
        echo -e "${YELLOW}Bitte später erneut versuchen.${NC}"
      else
        echo -e "${YELLOW}Installation without network connection not possible.${NC}"
        echo -e "${YELLOW}Please try again later.${NC}"
      fi
      sleep 3
    fi
  fi
}

# Starte den Hauptablauf
main