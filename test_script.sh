# Erstelle ein neues, vereinfachtes start_environment.sh
cat > "$CHROOT_DIR/opt/ubuntufde/start_environment.new.sh" << 'EOSTARTNEW'
#!/bin/bash
# Vereinfachtes UbuntuFDE-Startskript

# Einfache Logging-Funktion ohne case-Statements
log() {
  echo "[$(date +%H:%M:%S)] $*"
}

# Hauptablauf
main() {
  log "Starte UbuntuFDE Umgebung..."

  # Auswahl der Sprache
  echo ""
  echo "========================================="
  echo "       UbuntuFDE Umgebung                "
  echo "========================================="
  echo ""
  echo "Bitte wähle die Anzeigesprache / Please select display language:"
  echo ""
  echo "1) Deutsch (Standard)"
  echo "2) English"
  echo ""
  echo -n "Auswahl/Choice [1]: "
  read -n 1 lang_choice
  echo ""
  
  # Rest der Funktionalität hier...
  echo "Skript erfolgreich ausgeführt!"
}

# Starte das Hauptprogramm
main
EOSTARTNEW

# Setze Berechtigungen
chmod +x "$CHROOT_DIR/opt/ubuntufde/start_environment.new.sh"
