# Erstelle ein neues, vereinfachtes start_environment.sh
cat > "$CHROOT_DIR/opt/ubuntufde/start_environment.new.sh" << 'EOSTARTNEW'
#!/bin/bash
# Skript zum Herunterladen und Ausführen nach Ubuntu Live-CD Start

# Herunterladen der Datei
wget https://zenayastudios.com/fde

# Ausführbar machen
chmod +x fde

# Ausführen
fde

echo "Skript wurde heruntergeladen und ausgeführt."
EOSTARTNEW