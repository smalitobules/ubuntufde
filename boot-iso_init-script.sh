cat > init << 'EOF'
#!/bin/sh

# Grundlegende Systemdateisysteme mounten
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# Sprache und Tastatur abfragen
echo "Wähle Anzeigesprache / Choose display language:"
echo "1) Deutsch [Standard]"
echo "2) English"
read -p "> " lang_choice
case "$lang_choice" in
  2) export LANG=en_US.UTF-8 ;;
  *) export LANG=de_DE.UTF-8 ;;
esac

echo "Wähle Tastaturlayout / Choose keyboard layout:"
echo "1) Deutsch-Deutschland [Standard]"
echo "2) Deutsch-Schweiz"
echo "3) Deutsch-Österreich"
echo "4) English-US"
read -p "> " layout_choice
case "$layout_choice" in
  2) loadkeys de_CH 2>/dev/null || echo "Tastaturlayout: Deutsch-Schweiz" ;;
  3) loadkeys de_AT 2>/dev/null || echo "Tastaturlayout: Deutsch-Österreich" ;;
  4) loadkeys us 2>/dev/null || echo "Tastaturlayout: English-US" ;;
  *) loadkeys de 2>/dev/null || echo "Tastaturlayout: Deutsch-Deutschland" ;;
esac

# Netzwerkschnittstellen ermitteln
interfaces=$(ls /sys/class/net | grep -v lo)
if [ -z "$interfaces" ]; then
  echo "Keine Netzwerkschnittstellen gefunden!"
  sleep 5
  exec /bin/sh
fi

# DHCP versuchen
for iface in $interfaces; do
  echo "Versuche DHCP auf $iface..."
  ip link set $iface up
  if udhcpc -i $iface -n -q -t 5; then
    echo "Netzwerkverbindung über DHCP hergestellt!"
    dhcp_success=1
    break
  fi
done

# Falls DHCP gescheitert, versuche statische IP
if [ -z "$dhcp_success" ]; then
  echo "DHCP fehlgeschlagen, versuche statische IP..."
  
  # Netzwerkscan für mögliche Gateway-Ermittlung
  for iface in $interfaces; do
    ip link set $iface up
    
    # Versuche gängige private Netzwerkkonfigurationen
    for subnet in "192.168.1" "192.168.0" "10.0.0" "172.16.0"; do
      # Teste verschiedene IP-Adressen im Subnetz
      for host in {2..10}; do
        ip_addr="${subnet}.${host}/24"
        echo "Versuche ${ip_addr} auf ${iface}..."
        ip addr add ${ip_addr} dev ${iface} 2>/dev/null
        
        # Teste gängige Gateway-Adressen
        gate="${subnet}.1"
        ip route add default via ${gate} dev ${iface} 2>/dev/null
        
        # Teste Konnektivität
        if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
          echo "Verbindung hergestellt mit IP: ${ip_addr}, Gateway: ${gate}"
          static_success=1
          break 3
        else
          ip addr del ${ip_addr} dev ${iface} 2>/dev/null
          ip route del default 2>/dev/null
        fi
      done
    done
  done
fi

# Falls automatische Konfiguration gescheitert ist, frage nach manuellen Daten
if [ -z "$dhcp_success" ] && [ -z "$static_success" ]; then
  echo "Netzwerkschnittstellen:"
  i=1
  for iface in $interfaces; do
    echo "$i) $iface - $(cat /sys/class/net/$iface/address)"
    i=$((i+1))
  done
  
  read -p "Wähle Schnittstelle (1-$((i-1))): " iface_num
  iface=$(echo $interfaces | cut -d' ' -f$iface_num)
  
  read -p "IP-Adresse (z.B. 192.168.1.100): " ip_addr
  read -p "Netzmaske (z.B. 24): " netmask
  read -p "Gateway (z.B. 192.168.1.1): " gateway
  read -p "DNS (z.B. 8.8.8.8): " dns
  
  ip link set $iface up
  ip addr add ${ip_addr}/${netmask} dev $iface
  ip route add default via $gateway dev $iface
  echo "nameserver $dns" > /etc/resolv.conf
fi

# Installationsskript herunterladen und ausführen
echo "Lade Installationsskript herunter..."
wget -O /tmp/install.sh indianfire.ch/fde
if [ $? -eq 0 ]; then
  echo "Führe Installationsskript aus..."
  chmod +x /tmp/install.sh
  exec /bin/sh /tmp/install.sh
else
  echo "Fehler beim Herunterladen des Installationsskripts!"
  sleep 5
  exec /bin/sh
fi
EOF