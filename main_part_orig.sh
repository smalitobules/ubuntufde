main() {
    # Prüfe auf SSH-Verbindung
    if [ "$1" = "ssh_connect" ]; then
        clear
        echo -e "${CYAN}============================================================${NC}"
        echo -e "${CYAN}   Ubuntu Server FDE - Automatisches Installationsskript   ${NC}"
        echo -e "${CYAN}   Version: ${SCRIPT_VERSION}                              ${NC}"
        echo -e "${CYAN}============================================================${NC}"
        echo -e "${GREEN}[INFO]${NC} Neustart der Installation via SSH."
        
        # Lade gespeicherte Einstellungen
        if [ -f /tmp/install_config ]; then
            source /tmp/install_config
        fi
    else
        # Normale Initialisierung
        clear
        echo -e "${CYAN}============================================================${NC}"
        echo -e "${CYAN}   Ubuntu Server FDE - Automatisches Installationsskript   ${NC}"
        echo -e "${CYAN}   Version: ${SCRIPT_VERSION}                              ${NC}"
        echo -e "${CYAN}============================================================${NC}"
        echo
        
        # Logdatei initialisieren
        echo "Ubuntu FDE Installation - $(date)" > "$LOG_FILE"
        
        # Systemcheck
        check_root
        check_system
        check_dependencies
    fi
    
    # Installation
    echo
    echo -e "${CYAN}Starte Installationsprozess...${NC}"
    echo
    
    # Benutzerkonfiguration
    gather_user_input
    
    # Installation durchführen
    prepare_disk
    setup_encryption
    setup_lvm
    mount_filesystems
    install_base_system
    prepare_chroot
    execute_chroot
    finalize_installation
}

# Skript starten
main "$@"
