# Frage nach Systemneustart mit nur einem Tastendruck
log "Installation abgeschlossen."
echo -e "\nMöchtest du das System jetzt neu starten, um alle Änderungen zu aktivieren? (j/n)"
read -n 1 -r restart_system
echo # Neue Zeile für bessere Lesbarkeit

if [[ "$restart_system" =~ ^[Jj]$ ]]; then
    log "Systemneustart wird durchgeführt..."
    echo "Das System wird jetzt neu gestartet..."
    sleep 2
    reboot
else
    echo "Bitte starte das System später neu, um alle Änderungen vollständig zu aktivieren."
fi