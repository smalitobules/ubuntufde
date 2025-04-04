prepare_disk() {
    log_progress "Beginne mit der Partitionierung..."
    show_progress 10
    
    # Letzte Warnung mit Möglichkeit zur Rückkehr
    echo -e "${YELLOW}[WARNUNG]${NC} ALLE DATEN AUF $DEV WERDEN GELÖSCHT!"
    read -p "Bist du sicher? (j/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Jj]$ ]]; then
        log_warn "Partitionierung abgebrochen. Kehre zur Laufwerksauswahl zurück."
        
        # Zurück zur Laufwerksauswahl
        # Hier zeigen wir erneut die verfügbaren Laufwerke an
        available_devices=()
        echo -e "\n${CYAN}Verfügbare Laufwerke:${NC}"
        echo -e "${YELLOW}NR   GERÄT                GRÖSSE      MODELL${NC}"
        echo -e "-------------------------------------------------------"
        i=0
        while read device size model; do
            # Überspringe Überschriften oder leere Zeilen
            if [[ "$device" == "NAME" || -z "$device" ]]; then
                continue
            fi
            available_devices+=("$device")
            ((i++))
            printf "%-4s %-20s %-12s %s\n" "[$i]" "$device" "$size" "$model"
        done < <(lsblk -d -p -o NAME,SIZE,MODEL | grep -v loop)
        echo -e "-------------------------------------------------------"
        
        # Wenn keine Geräte gefunden wurden
        if [ ${#available_devices[@]} -eq 0 ]; then
            log_error "Keine Laufwerke gefunden!"
        fi
        
        # Standardwert ist das erste Gerät
        DEFAULT_DEV="1"
        DEFAULT_DEV_PATH="${available_devices[0]}"
        
        # Laufwerksauswahl
        read -p "Wähle ein Laufwerk (Nummer oder vollständiger Pfad) [1]: " DEVICE_CHOICE
        DEVICE_CHOICE=${DEVICE_CHOICE:-1}
        
        # Verarbeite die Auswahl
        if [[ "$DEVICE_CHOICE" =~ ^[0-9]+$ ]] && [ "$DEVICE_CHOICE" -ge 1 ] && [ "$DEVICE_CHOICE" -le "${#available_devices[@]}" ]; then
            # Nutzer hat Nummer ausgewählt
            DEV="${available_devices[$((DEVICE_CHOICE-1))]}"
        else
            # Nutzer hat möglicherweise einen Pfad eingegeben
            if [ -b "$DEVICE_CHOICE" ]; then
                DEV="$DEVICE_CHOICE"
            else
                # Ungültige Eingabe - verwende erstes Gerät als Fallback
                DEV="${available_devices[0]}"
                log_info "Ungültige Eingabe. Verwende Standardgerät: $DEV"
            fi
        fi
        
        # Rekursiver Aufruf, um die Funktion mit dem neuen Gerät erneut zu starten
        prepare_disk
        return
    fi
    
    # Grundlegende Variablen einrichten
    DM="${DEV##*/}"
    if [[ "$DEV" =~ "nvme" ]]; then
        DEVP="${DEV}p"
        DM="${DM}p"
    else
        DEVP="${DEV}"
    fi
    
    # Export für spätere Verwendung
    export DEV DEVP DM
    
    # Partitionierung
    log_info "Partitioniere $DEV..."
    sgdisk --zap-all "$DEV"
    sgdisk --new=1:0:+1024M "$DEV"   # boot
    sgdisk --new=2:0:+2M "$DEV"      # GRUB
    sgdisk --new=3:0:+256M "$DEV"    # EFI-SP
    sgdisk --new=5:0:0 "$DEV"        # rootfs
    sgdisk --typecode=1:8301 --typecode=2:ef02 --typecode=3:ef00 --typecode=5:8301 "$DEV"
    sgdisk --change-name=1:/boot --change-name=2:GRUB --change-name=3:EFI-SP --change-name=5:rootfs "$DEV"
    sgdisk --hybrid 1:2:3 "$DEV"
    sgdisk --print "$DEV"
    
    log_info "Partitionierung abgeschlossen"
    show_progress 20
}