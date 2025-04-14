#!/bin/bash
# UbuntuFDE-Backup - Volume Backup & Restore Tool
# Version: 0.1.0
# Datum: $(date +%Y-%m-%d)

###################
# Konfiguration   #
SCRIPT_VERSION="0.1.0"
LOG_FILE="$(pwd)/UbuntuFDE_Backup_$(date +%Y%m%d_%H%M%S).log"
BACKUP_TOOL="partclone"
COMPRESSION="zstd"
CHECKSUM_ALGO="sha512sum"
# Konfiguration   #
###################

###################
# DESIGN UND LOG  #
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logdatei einrichten
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Backup/Restore Tool startet am $(date) ===" | tee -a "$LOG_FILE"
echo "=== Alle Ausgaben werden in $LOG_FILE protokolliert ===" | tee -a "$LOG_FILE"

# Hilfsfunktionen für Logging
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARNUNG]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[FEHLER]${NC} $1" | tee -a "$LOG_FILE"
    return 1
}

log_progress() {
    echo -e "${BLUE}[FORTSCHRITT]${NC} $1" | tee -a "$LOG_FILE"
}

# Fortschrittsbalken mit Restzeitanzeige
show_progress() {
    local percent=$1
    local elapsed=$2
    local total_size=$3
    local processed=$4
    local width=60
    local num_bars=$((percent * width / 100))
    local remaining="Verbleibend: Berechne..."
    
    # Berechne verbleibende Zeit, wenn genug Daten vorhanden
    if [ "$percent" -gt 5 ] && [ "$elapsed" -gt 2 ]; then
        local bytes_per_sec=$(bc <<< "scale=2; $processed / $elapsed")
        local remaining_bytes=$(bc <<< "$total_size - $processed")
        local seconds_left=$(bc <<< "scale=0; $remaining_bytes / $bytes_per_sec")
        
        if [ "$seconds_left" -gt 0 ]; then
            # Formatiere Zeit
            if [ "$seconds_left" -gt 3600 ]; then
                remaining="Verbleibend: $(($seconds_left / 3600))h $(($seconds_left % 3600 / 60))m"
            elif [ "$seconds_left" -gt 60 ]; then
                remaining="Verbleibend: $(($seconds_left / 60))m $(($seconds_left % 60))s"
            else
                remaining="Verbleibend: ${seconds_left}s"
            fi
        fi
    fi
    
    # Baue Fortschrittsbalken
    local progress="["
    for ((i=0; i<num_bars; i++)); do
        progress+="█"
    done
    
    for ((i=num_bars; i<width; i++)); do
        progress+=" "
    done
    
    # Zeige Fortschritt in MB/GB an
    local processed_hr=""
    local total_hr=""
    
    if [ "$processed" -gt 1073741824 ]; then  # > 1GB
        processed_hr="$(bc <<< "scale=2; $processed / 1073741824") GB"
        total_hr="$(bc <<< "scale=2; $total_size / 1073741824") GB"
    else
        processed_hr="$(bc <<< "scale=2; $processed / 1048576") MB"
        total_hr="$(bc <<< "scale=2; $total_size / 1048576") MB"
    fi
    
    progress+="] ${percent}% ($processed_hr von $total_hr) | $remaining"
    
    echo -ne "\r${BLUE}${progress}${NC}"
}
# DESIGN UND LOG  #
###################

###################
#   Systemcheck   #
# Überprüfe die Ausführung mit erhöhten Rechten
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${YELLOW}[HINWEIS]${NC} Dieses Skript benötigt Root-Rechte. Starte neu mit sudo..."
        exec sudo "$0" "$@"  # Starte das Skript neu mit sudo und behalte alle Argumente bei
    fi
}

# Abhängigkeiten prüfen und installieren
check_dependencies() {
    log_info "Prüfe Abhängigkeiten..."
    
    local deps=("partclone" "cryptsetup" "dialog" "lvm2" "zstd" "veracrypt" "e2fsprogs" "dosfstools" "gdisk")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_info "Aktualisiere Paketquellen..."
        apt-get update
        log_info "Installiere fehlende Abhängigkeiten: ${missing_deps[*]}..."
        apt-get install -y "${missing_deps[@]}"
    fi
}
#   Systemcheck   #
###################

###################
# Volume Management
# Liste verfügbare Volumes auf
list_available_volumes() {
    log_info "Suche nach verfügbaren Volumes..."
    
    echo -e "\n${CYAN}Verfügbare Volumes:${NC}"
    echo -e "${YELLOW}NR   GERÄT             GRÖSSE      TYP         LABEL        STATUS${NC}"
    echo -e "------------------------------------------------------------------------"
    
    # Liste von Geräten erstellen
    local devices=()
    local device_types=()
    local i=0
    
    # Partitionen auflisten
    while read -r device size type label; do
        if [[ "$device" == "NAME" || -z "$device" ]]; then
            continue
        fi
        
        # Volume-Typ erkennen
        local volume_type="Standard"
        local status="Verfügbar"
        
        # LUKS-Volumes erkennen
        if cryptsetup isLuks "$device" 2>/dev/null; then
            volume_type="LUKS"
        fi
        
        # LVM-Volumes erkennen
        if lvs 2>/dev/null | grep -q "$device"; then
            volume_type="LVM"
        fi
        
        # EFI-Partition erkennen
        if [ "$type" == "vfat" ] && blkid "$device" | grep -qi "EFI"; then
            volume_type="EFI-SP"
        fi
        
        # GRUB-Partition erkennen
        if blkid "$device" | grep -qi "GRUB"; then
            volume_type="GRUB"
        fi
        
        # Boot-Partition erkennen
        if [ "$label" == "boot" ] || mountpoint -q /boot && findmnt -n -o SOURCE /boot | grep -q "$device"; then
            volume_type="Boot"
        fi
        
        # Root-Partition erkennen
        if mountpoint -q / && findmnt -n -o SOURCE / | grep -q "$device"; then
            volume_type="Root"
            status="Gemountet (Root)"
        fi
        
        # Veracrypt-Volumes erkennen
        # Dies ist schwieriger, da keine direkte Erkennung möglich ist
        # Hier nur eine Schätzung basierend auf Partitionstyp und LUKS-Abwesenheit
        if [ "$volume_type" == "Standard" ] && [ "$type" == "ntfs" ] && ! cryptsetup isLuks "$device" 2>/dev/null; then
            volume_type="mögl. VeraCrypt"
        fi
        
        devices+=("$device")
        device_types+=("$volume_type")
        
        ((i++))
        printf "%-4s %-18s %-11s %-12s %-12s %s\n" "[$i]" "$device" "$size" "$volume_type" "$label" "$status"
        
    done < <(lsblk -p -o NAME,SIZE,FSTYPE,LABEL | grep -v loop)
    
    echo -e "------------------------------------------------------------------------"
    
    # Speichere die Arrays für spätere Verwendung
    declare -g AVAILABLE_DEVICES=("${devices[@]}")
    declare -g DEVICE_TYPES=("${device_types[@]}")
    
    if [ ${#devices[@]} -eq 0 ]; then
        log_error "Keine Volumes gefunden!"
        return 1
    fi
    
    return 0
}

# Funktion zum Entschlüsseln eines Volumes
decrypt_volume() {
    local device=$1
    local volume_type=$2
    local map_name="${device##*/}_decrypted"
    
    log_info "Entschlüsselung für $device ($volume_type)..."
    
    case "$volume_type" in
        "LUKS")
            log_info "LUKS-Volume erkannt. Bitte Passwort eingeben:"
            if cryptsetup open "$device" "$map_name"; then
                log_info "LUKS-Volume erfolgreich entschlüsselt als /dev/mapper/$map_name"
                echo "/dev/mapper/$map_name"
                return 0
            else
                log_error "LUKS-Entschlüsselung fehlgeschlagen"
                return 1
            fi
            ;;
            
        "mögl. VeraCrypt")
            log_info "Mögliches VeraCrypt-Volume erkannt. Bitte Passwort eingeben:"
            mkdir -p /mnt/veracrypt_temp
            
            if veracrypt -t --non-interactive -p "" "$device" /mnt/veracrypt_temp; then
                log_info "VeraCrypt-Volume erfolgreich eingehängt unter /mnt/veracrypt_temp"
                echo "/mnt/veracrypt_temp"
                return 0
            else
                log_error "VeraCrypt-Entschlüsselung fehlgeschlagen"
                return 1
            fi
            ;;
            
        *)
            # Kein verschlüsseltes Volume
            echo "$device"
            return 0
            ;;
    esac
}

# Funktion zum Durchsuchen und Auswählen eines Backup-Speicherorts
select_backup_location() {
    log_info "Wähle Speicherort für Backup..."
    
    # Liste alle verfügbaren Geräte und Mountpoints
    local mounts=()
    while read -r device mountpoint fstype; do
        if [[ "$mountpoint" == "/" || "$mountpoint" == "/boot" || "$mountpoint" == "/boot/efi" ]]; then
            continue  # System-Mountpoints überspringen
        fi
        if [[ -d "$mountpoint" && -w "$mountpoint" ]]; then
            mounts+=("$mountpoint")
        fi
    done < <(findmnt -n -o SOURCE,TARGET,FSTYPE)
    
    # Füge die Option hinzu, ein neues Gerät zu mounten
    mounts+=("-- Neues Gerät mounten --")
    
    # Dialog zur Auswahl des Mountpoints
    local selected_mount=""
    local options=""
    for i in "${!mounts[@]}"; do
        options="$options $i ${mounts[$i]} "
    done
    
    selected_mount=$(dialog --title "Backup-Speicherort" \
                         --menu "Wähle einen Speicherort für die Backup-Dateien:" 20 70 12 \
                         $options \
                         3>&1 1>&2 2>&3)
    
    clear
    
    if [ "$selected_mount" == "$((${#mounts[@]}-1))" ]; then
        # Benutzer will ein neues Gerät mounten
        mount_new_device
        # Rekursiver Aufruf nach Mounten eines neuen Geräts
        select_backup_location
        return
    elif [ -n "$selected_mount" ]; then
        selected_dir="${mounts[$selected_mount]}"
        
        # Erlaube dem Benutzer, durch das Dateisystem zu navigieren
        while true; do
            local files=()
            local dirs=()
            
            # Lese Verzeichnisinhalt
            while IFS= read -r item; do
                if [ -d "$selected_dir/$item" ]; then
                    dirs+=("$item")
                else
                    files+=("$item")
                fi
            done < <(ls -A "$selected_dir")
            
            # Erstelle Menüoptionen
            local menu_options=""
            menu_options=".. [Zurück] "
            menu_options+="+ [Neuer Ordner] "
            
            for dir in "${dirs[@]}"; do
                menu_options+="d_$dir $dir/ "
            done
            
            local choice=$(dialog --title "Navigation: $selected_dir" \
                               --menu "Wähle ein Verzeichnis:" 20 70 12 \
                               $menu_options \
                               3>&1 1>&2 2>&3)
            
            clear
            
            if [ -z "$choice" ]; then
                # Abgebrochen
                return 1
            elif [ "$choice" == ".." ]; then
                # Ein Verzeichnis nach oben
                selected_dir=$(dirname "$selected_dir")
            elif [ "$choice" == "+" ]; then
                # Neuen Ordner erstellen
                local new_dir=$(dialog --inputbox "Gib einen Namen für den neuen Ordner ein:" 8 50 \
                                   3>&1 1>&2 2>&3)
                clear
                if [ -n "$new_dir" ]; then
                    mkdir -p "$selected_dir/$new_dir"
                    selected_dir="$selected_dir/$new_dir"
                fi
            elif [[ "$choice" == d_* ]]; then
                # In ausgewähltes Verzeichnis navigieren
                local dir_name="${choice#d_}"
                selected_dir="$selected_dir/$dir_name"
            else
                # Datei ausgewählt
                log_info "Datei ausgewählt: $selected_dir/$choice"
            fi
            
            # Fragen, ob aktuelles Verzeichnis verwendet werden soll
            if dialog --title "Verzeichnis bestätigen" \
                   --yesno "Möchtest du dieses Verzeichnis verwenden?\n$selected_dir" 8 60; then
                break
            fi
            clear
        done
        
        echo "$selected_dir"
        return 0
    else
        log_error "Keine Auswahl getroffen"
        return 1
    fi
}

# Funktion zum Mounten eines neuen Geräts
mount_new_device() {
    log_info "Mounten eines neuen Geräts..."
    
    # Liste verfügbare Geräte auf
    list_available_volumes
    
    # Lasse Benutzer ein Gerät auswählen
    echo -e "\n${CYAN}Geräteauswahl zum Mounten:${NC}"
    read -p "Wähle ein Gerät (Nummer): " device_num
    
    if ! [[ "$device_num" =~ ^[0-9]+$ ]] || [ "$device_num" -lt 1 ] || [ "$device_num" -gt "${#AVAILABLE_DEVICES[@]}" ]; then
        log_error "Ungültige Auswahl"
        return 1
    fi
    
    local selected_device="${AVAILABLE_DEVICES[$((device_num-1))]}"
    local device_type="${DEVICE_TYPES[$((device_num-1))]}"
    
    # Prüfe, ob das Gerät verschlüsselt ist und entschlüssele es
    local mount_device=$(decrypt_volume "$selected_device" "$device_type")
    if [ $? -ne 0 ]; then
        log_error "Entschlüsselung fehlgeschlagen"
        return 1
    fi
    
    # Mountpoint erstellen und einbinden
    local mount_point="/mnt/backup_disk_${selected_device##*/}"
    mkdir -p "$mount_point"
    
    if mount "$mount_device" "$mount_point"; then
        log_info "Gerät erfolgreich gemountet unter $mount_point"
        return 0
    else
        log_error "Mounten fehlgeschlagen"
        return 1
    fi
}
# Volume Management #
###################

###################
# Backup-Funktionalität
# Führt Dateisystemprüfung durch
check_filesystem() {
    local device=$1
    local fs_type=$2
    
    log_progress "Führe Dateisystemprüfung für $device durch..."
    
    case "$fs_type" in
        "ext2"|"ext3"|"ext4")
            # Für ext2/3/4 Dateisysteme
            e2fsck -f -p "$device"
            return $?
            ;;
        "vfat")
            # Für FAT Dateisysteme
            fsck.vfat -a "$device"
            return $?
            ;;
        "ntfs")
            # Für NTFS
            ntfsfix "$device"
            return $?
            ;;
        *)
            log_warn "Unbekannter Dateisystemtyp $fs_type, überspringe Prüfung"
            return 0
            ;;
    esac
}

# Sichert ein Volume mit partclone
backup_volume() {
    local device=$1
    local backup_path=$2
    local volume_type=$3
    local fs_type=$4
    
    log_progress "Starte Backup von $device ($volume_type, $fs_type) nach $backup_path..."
    
    # Dateisystemprüfung vor dem Backup
    check_filesystem "$device" "$fs_type"
    if [ $? -ne 0 ]; then
        log_warn "Dateisystemprüfung ergab Fehler. Backup wird trotzdem fortgesetzt."
    fi
    
    # Entsprechendes partclone-Tool auswählen
    local partclone_cmd=""
    case "$fs_type" in
        "ext2"|"ext3"|"ext4")
            partclone_cmd="partclone.ext4"
            ;;
        "vfat")
            partclone_cmd="partclone.fat"
            ;;
        "ntfs")
            partclone_cmd="partclone.ntfs"
            ;;
        *)
            # Fallback auf Disk Image
            partclone_cmd="partclone.dd"
            ;;
    esac
    
    local backup_file="${backup_path}/${volume_type}_$(basename $device)_$(date +%Y%m%d_%H%M%S).img"
    local compressed_file="${backup_file}.zst"
    local checksum_file="${compressed_file}.sha512"
    
    # Größe des Volumes ermitteln
    local total_size=$(blockdev --getsize64 "$device")
    local start_time=$(date +%s)
    
    # Fortschrittsanzeige-Funktion für pv
    progress_monitor() {
        local elapsed=0
        local processed=0
        local percent=0
        
        while read -r line; do
            # Versuche Fortschritt aus partclone zu extrahieren
            if [[ "$line" =~ ([0-9]+)% ]]; then
                percent="${BASH_REMATCH[1]}"
                elapsed=$(($(date +%s) - start_time))
                processed=$((total_size * percent / 100))
                show_progress "$percent" "$elapsed" "$total_size" "$processed"
            fi
            echo "$line" >> "$LOG_FILE"
        done
    }
    
    # Backup mit partclone, on-the-fly-Kompression und Prüfsumme
    log_info "Erzeuge Backup mit $partclone_cmd und $COMPRESSION-Kompression..."
    
    # Pipeline: partclone -> zstd -> sha512sum
    $partclone_cmd -c -s "$device" 2>&1 | \
    tee >(progress_monitor) | \
    $COMPRESSION -T0 > "$compressed_file"
    
    if [ $? -ne 0 ]; then
        log_error "Backup fehlgeschlagen"
        return 1
    fi
    
    # Prüfsumme berechnen
    log_info "Berechne Prüfsumme..."
    $CHECKSUM_ALGO "$compressed_file" > "$checksum_file"
    
    log_info "Backup abgeschlossen: $compressed_file"
    log_info "Prüfsumme: $checksum_file"
    
    # Integritätsprüfung
    verify_backup "$compressed_file" "$checksum_file"
    
    return $?
}

# Verifiziert die Integrität eines Backups
verify_backup() {
    local backup_file=$1
    local checksum_file=$2
    
    log_progress "Prüfe Backup-Integrität..."
    
    # Prüfsummenverifikation
    local verify_result=$($CHECKSUM_ALGO -c "$checksum_file")
    if [ $? -ne 0 ]; then
        log_error "Integritätsprüfung fehlgeschlagen: $verify_result"
        return 1
    fi
    
    log_info "${GREEN}✓ Integritätsprüfung erfolgreich!${NC}"
    echo -e "\n${GREEN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Backup-Verifizierung erfolgreich!          ║${NC}"
    echo -e "${GREEN}║  SHA512-Prüfsumme stimmt überein            ║${NC}"
    echo -e "${GREEN}║  Backup ist bereit zur Wiederherstellung    ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
    
    return 0
}
# Backup-Funktionalität #
###################

###################
# Wiederherstellungs-Funktionalität
# Findet verfügbare Backups
find_available_backups() {
    local backup_path=$1
    
    log_info "Suche nach vorhandenen Backups in $backup_path..."
    
    local found=0
    declare -g BACKUP_FILES=()
    declare -g BACKUP_TYPES=()
    
    while IFS= read -r file; do
        if [[ $file == *.img.zst ]]; then
            # Extrahiere Volume-Typ aus Dateinamen
            local volume_type=$(basename "$file" | cut -d '_' -f 1)
            BACKUP_FILES+=("$file")
            BACKUP_TYPES+=("$volume_type")
            ((found++))
        fi
    done < <(find "$backup_path" -type f -name "*.img.zst" | sort)
    
    if [ $found -eq 0 ]; then
        log_error "Keine Backup-Dateien in $backup_path gefunden"
        return 1
    fi
    
    echo -e "\n${CYAN}Gefundene Backups:${NC}"
    echo -e "${YELLOW}NR   DATEI                                             TYP         DATUM${NC}"
    echo -e "------------------------------------------------------------------------------------------"
    
    for i in "${!BACKUP_FILES[@]}"; do
        local file="${BACKUP_FILES[$i]}"
        local type="${BACKUP_TYPES[$i]}"
        local date_str=$(stat -c %y "$file" | cut -d '.' -f 1)
        
        local file_display=$(basename "$file")
        printf "%-4s %-50s %-12s %s\n" "[$(($i+1))]" "$file_display" "$type" "$date_str"
    done
    
    echo -e "------------------------------------------------------------------------------------------"
    
    return 0
}

# Prüft ein Backup vor der Wiederherstellung
verify_backup_before_restore() {
    local backup_file=$1
    
    log_progress "Prüfe Backup vor der Wiederherstellung..."
    
    # Prüfe, ob Prüfsummendatei existiert
    local checksum_file="${backup_file}.sha512"
    if [ ! -f "$checksum_file" ]; then
        log_error "Keine Prüfsummendatei gefunden: $checksum_file"
        return 1
    fi
    
    # Verifiziere Prüfsumme
    if ! $CHECKSUM_ALGO -c "$checksum_file"; then
        log_error "Prüfsummenverifizierung fehlgeschlagen!"
        return 1
    fi
    
    echo -e "\n${GREEN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Backup-Integrität bestätigt!               ║${NC}"
    echo -e "${GREEN}║  SHA512-Prüfsumme stimmt überein            ║${NC}"
    echo -e "${GREEN}║  Backup kann sicher wiederhergestellt werden ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
    
    return 0
}

# Stellt ein Volume wieder her
restore_volume() {
    local backup_file=$1
    local target_device=$2
    
    log_progress "Stelle Backup wieder her: $backup_file auf $target_device..."
    
    # Prüfe Backup vor der Wiederherstellung
    if ! verify_backup_before_restore "$backup_file"; then
        log_error "Verifikation fehlgeschlagen, Wiederherstellung abgebrochen"
        return 1
    fi
    
    # Bestätigung vom Benutzer einholen
    echo -e "\n${RED}WARNUNG: Alle Daten auf $target_device werden überschrieben!${NC}"
    read -p "Bist du sicher, dass du fortfahren möchtest? (j/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Jj]$ ]]; then
        log_info "Wiederherstellung abgebrochen"
        return 1
    fi
    
    # Start time für Fortschrittsanzeige
    local start_time=$(date +%s)
    local total_size=$(stat -c %s "$backup_file")
    
    # Fortschrittsanzeige-Funktion
    progress_monitor() {
        local elapsed=0
        local processed=0
        local percent=0
        
        while read -r line; do
            # Versuche Fortschritt zu extrahieren
            if [[ "$line" =~ ([0-9]+)% ]]; then
                percent="${BASH_REMATCH[1]}"
                elapsed=$(($(date +%s) - start_time))
                processed=$((total_size * percent / 100))
                show_progress "$percent" "$elapsed" "$total_size" "$processed"
            fi
            echo "$line" >> "$LOG_FILE"
        done
    }
    
    # Entpacke und stelle das Backup wieder her
    log_info "Entpacke und stelle Backup wieder her..."
    $COMPRESSION -dc "$backup_file" 2>&1 | \
    tee >(progress_monitor) | \
    partclone.restore -o "$target_device"
    
    if [ $? -ne 0 ]; then
        log_error "Wiederherstellung fehlgeschlagen"
        return 1
    fi
    
    # Synchronisiere Schreibcache
    sync
    
    log_info "Wiederherstellung erfolgreich abgeschlossen"
    echo -e "\n${GREEN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Wiederherstellung erfolgreich!             ║${NC}"
    echo -e "${GREEN}║  Volume wurde wiederhergestellt.            ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
    
    return 0
}
# Wiederherstellungs-Funktionalität #
###################

###################
# Hauptskript
# Hauptmenü anzeigen
show_main_menu() {
    clear
    echo -e "${CYAN}===== UbuntuFDE Backup & Restore Tool =====${NC}"
    echo -e "${CYAN}Version: $SCRIPT_VERSION | Datum: $(date +%Y-%m-%d)${NC}\n"
    
    echo "1) Volumes sichern"
    echo "2) Volumes wiederherstellen"
    echo "0) Beenden"
    
    read -p "Wähle eine Option: " main_choice
    
    case $main_choice in
        1)
            backup_workflow
            ;;
        2)
            restore_workflow
            ;;
        0)
            exit 0
            ;;
        *)
            log_error "Ungültige Auswahl"
            show_main_menu
            ;;
    esac
}

# Workflow für das Backup
backup_workflow() {
    log_info "Starte Backup-Workflow..."
    
    # Verfügbare Volumes auflisten
    if ! list_available_volumes; then
        log_error "Keine Volumes zum Sichern gefunden!"
        return 1
    fi
    
    # Volume-Auswahl
    echo -e "\n${CYAN}Volumeauswahl zum Sichern:${NC}"
    echo "Wähle die zu sichernden Volumes (Nummern durch Komma getrennt, z.B. 1,3,5):"
    read -p "Auswahl: " volume_selection
    
    # Konvertiere Auswahl in Array
    IFS=',' read -ra selected_volumes <<< "$volume_selection"
    
    # Speicherort für Backups auswählen
    local backup_dir=$(select_backup_location)
    if [ -z "$backup_dir" ]; then
        log_error "Kein Backup-Speicherort ausgewählt"
        return 1
    fi
    
    # Verzeichnis für dieses Backup erstellen
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${backup_dir}/UbuntuFDE_Backup_${timestamp}"
    mkdir -p "$backup_path"
    
    log_info "Backup-Verzeichnis: $backup_path"
    
    # Jedes ausgewählte Volume sichern
    for vol_num in "${selected_volumes[@]}"; do
        if ! [[ "$vol_num" =~ ^[0-9]+$ ]] || [ "$vol_num" -lt 1 ] || [ "$vol_num" -gt "${#AVAILABLE_DEVICES[@]}" ]; then
            log_warn "Ungültige Volume-Nummer: $vol_num, überspringe"
            continue
        fi
        
        local device="${AVAILABLE_DEVICES[$((vol_num-1))]}"
        local device_type="${DEVICE_TYPES[$((vol_num-1))]}"
        
        # Dateisystemtyp ermitteln
        local fs_type=$(lsblk -no FSTYPE "$device")
        
        # Wenn verschlüsselt, entschlüsseln
        local backup_device="$device"
        if [ "$device_type" == "LUKS" ] || [ "$device_type" == "mögl. VeraCrypt" ]; then
            backup_device=$(decrypt_volume "$device" "$device_type")
            if [ $? -ne 0 ]; then
                log_warn "Entschlüsselung fehlgeschlagen für $device, überspringe"
                continue
            fi
        fi
        
        # Volume sichern
        backup_volume "$backup_device" "$backup_path" "$device_type" "$fs_type"
    done
    
    log_info "Backup-Workflow abgeschlossen"
    
    # Zurück zum Hauptmenü nach kurzer Pause
    read -p "Drücke Enter, um fortzufahren..."
    show_main_menu
}

# Workflow für die Wiederherstellung
restore_workflow() {
    log_info "Starte Wiederherstellungs-Workflow..."
    
    # Speicherort mit Backups auswählen
    local backup_dir=$(select_backup_location)
    if [ -z "$backup_dir" ]; then
        log_error "Kein Backup-Speicherort ausgewählt"
        return 1
    fi
    
    # Verfügbare Backups suchen
    if ! find_available_backups "$backup_dir"; then
        log_error "Keine Backups zum Wiederherstellen gefunden!"
        return 1
    fi
    
    # Backup-Auswahl
    echo -e "\n${CYAN}Backup-Auswahl zum Wiederherstellen:${NC}"
    read -p "Wähle ein Backup (Nummer): " backup_num
    
    if ! [[ "$backup_num" =~ ^[0-9]+$ ]] || [ "$backup_num" -lt 1 ] || [ "$backup_num" -gt "${#BACKUP_FILES[@]}" ]; then
        log_error "Ungültige Backup-Nummer"
        return 1
    fi
    
    local selected_backup="${BACKUP_FILES[$((backup_num-1))]}"
    local backup_type="${BACKUP_TYPES[$((backup_num-1))]}"
    
    # Verfügbare Volumes auflisten für die Wiederherstellung
    if ! list_available_volumes; then
        log_error "Keine Volumes zur Wiederherstellung gefunden!"
        return 1
    fi
    
    # Ziel-Volume auswählen
    echo -e "\n${CYAN}Ziel-Volume für die Wiederherstellung:${NC}"
    echo -e "Typ des ausgewählten Backups: ${YELLOW}$backup_type${NC}"
    read -p "Wähle ein Ziel-Volume (Nummer): " target_num
    
    if ! [[ "$target_num" =~ ^[0-9]+$ ]] || [ "$target_num" -lt 1 ] || [ "$target_num" -gt "${#AVAILABLE_DEVICES[@]}" ]; then
        log_error "Ungültige Volume-Nummer"
        return 1
    fi
    
    local target_device="${AVAILABLE_DEVICES[$((target_num-1))]}"
    local target_type="${DEVICE_TYPES[$((target_num-1))]}"
    
    # Warnung, wenn Typen nicht übereinstimmen
    if [ "$backup_type" != "$target_type" ]; then
        log_warn "Backup-Typ ($backup_type) stimmt nicht mit Ziel-Typ ($target_type) überein!"
        read -p "Trotzdem fortfahren? (j/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Jj]$ ]]; then
            log_info "Wiederherstellung abgebrochen"
            return 1
        fi
    fi
    
    # Volume wiederherstellen
    restore_volume "$selected_backup" "$target_device"
    
    log_info "Wiederherstellungs-Workflow abgeschlossen"
    
    # Zurück zum Hauptmenü nach kurzer Pause
    read -p "Drücke Enter, um fortzufahren..."
    show_main_menu
}

# Hauptfunktion
main() {
    # Systemcheck
    check_root
    check_dependencies
    
    # Dialog installieren, falls nicht vorhanden
    if ! command -v dialog &> /dev/null; then
        apt-get update
        apt-get install -y dialog
    fi
    
    # Tastaturlayout und Sprache hier einstellen (später zu implementieren)
    # set_keyboard_layout
    # set_language
    
    # Hauptmenü anzeigen
    show_main_menu
}

# Skript starten
main "$@"
# Hauptskript #
###################