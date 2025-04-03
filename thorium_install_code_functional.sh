# Thorium Browser installieren
if [[ "${ADDITIONAL_PACKAGES}" == *"thorium"* ]] || [ "${INSTALL_DESKTOP}" = "1" ]; then
    echo "Installiere Thorium Browser..." > /var/log/thorium_install.log
    
    # Entferne eventuell vorhandene alte Repository-Einträge
    rm -fv /etc/apt/sources.list.d/thorium.list >> /var/log/thorium_install.log 2>&1
    
    # Füge das offizielle Repository hinzu
    echo "Füge Thorium-Repository hinzu..." >> /var/log/thorium_install.log
    wget --no-hsts -P /etc/apt/sources.list.d/ http://dl.thorium.rocks/debian/dists/stable/thorium.list >> /var/log/thorium_install.log 2>&1
    
    # Aktualisiere Paketquellen
    echo "Aktualisiere Paketquellen..." >> /var/log/thorium_install.log
    apt-get update >> /var/log/thorium_install.log 2>&1
    
    # Installiere Thorium
    echo "Installiere Thorium Browser..." >> /var/log/thorium_install.log
    apt-get install -y thorium-browser >> /var/log/thorium_install.log 2>&1
    
    if [ $? -eq 0 ]; then
        echo "Thorium Browser erfolgreich installiert." >> /var/log/thorium_install.log
    else
        echo "Fehler bei der Installation von Thorium Browser." >> /var/log/thorium_install.log
    fi
fi

# Weitere zusätzliche Pakete installieren
if [ -n "${ADDITIONAL_PACKAGES}" ]; then
    echo "Installiere zusätzliche Pakete: ${ADDITIONAL_PACKAGES}"
    apt-get install -y ${ADDITIONAL_PACKAGES}
fi