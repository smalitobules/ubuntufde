# Desktop-Umgebung installieren wenn gewünscht
echo "DEBUG: INSTALL_DESKTOP=${INSTALL_DESKTOP}, DESKTOP_ENV=${DESKTOP_ENV}, DESKTOP_SCOPE=${DESKTOP_SCOPE}" >> /var/log/install-debug.log
if [ "${INSTALL_DESKTOP}" = "1" ]; then
    case "${DESKTOP_ENV}" in
        # GNOME Desktop
        1)
            echo "Installiere GNOME-Desktop-Umgebung..."
            if [ "${DESKTOP_SCOPE}" = "1" ]; then
                # Standard-Installation
                apt-get install -y --no-install-recommends gnome-session gnome-shell gdm3 nautilus nautilus-hide gnome-terminal gnome-text-editor ubuntu-gnome-wallpapers gnome-tweaks virtualbox-guest-additions-iso virtualbox-guest-utils virtualbox-guest-x11
                echo "DEBUG: Desktop-Installation abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            else
                # Minimale Installation
                apt-get install -y --no-install-recommends gnome-session gnome-shell gdm3 nautilus nautilus-hide gnome-terminal gnome-text-editor ubuntu-gnome-wallpapers gnome-tweaks virtualbox-guest-additions-iso virtualbox-guest-utils virtualbox-guest-x11
                echo "DEBUG: Desktop-Installation abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            fi
            ;;
            
        # KDE Plasma Desktop (momentan nur Platzhalter)
        2)
            echo "KDE Plasma wird derzeit noch nicht unterstützt. Installiere GNOME stattdessen..."
            if [ "${DESKTOP_SCOPE}" = "1" ]; then
                apt-get install -y --no-install-recommends gnome-session gnome-shell gdm3 nautilus nautilus-hide gnome-terminal gnome-text-editor ubuntu-gnome-wallpapers gnome-tweaks virtualbox-guest-additions-iso virtualbox-guest-utils virtualbox-guest-x11
                echo "DEBUG: Desktop-Installation abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            else
                apt-get install -y --no-install-recommends gnome-session gnome-shell gdm3 nautilus nautilus-hide gnome-terminal gnome-text-editor ubuntu-gnome-wallpapers gnome-tweaks virtualbox-guest-additions-iso virtualbox-guest-utils virtualbox-guest-x11
                echo "DEBUG: Desktop-Installation abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            fi
            ;;
            
        # Xfce Desktop (momentan nur Platzhalter)
        3)
            echo "Xfce wird derzeit noch nicht unterstützt. Installiere GNOME stattdessen..."
            if [ "${DESKTOP_SCOPE}" = "1" ]; then
                apt-get install -y --no-install-recommends gnome-session gnome-shell gdm3 nautilus nautilus-hide gnome-terminal gnome-text-editor ubuntu-gnome-wallpapers gnome-tweaks virtualbox-guest-additions-iso virtualbox-guest-utils virtualbox-guest-x11
                echo "DEBUG: Desktop-Installation abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            else
                apt-get install -y --no-install-recommends gnome-session gnome-shell gdm3 nautilus nautilus-hide gnome-terminal gnome-text-editor ubuntu-gnome-wallpapers gnome-tweaks virtualbox-guest-additions-iso virtualbox-guest-utils virtualbox-guest-x11
                echo "DEBUG: Desktop-Installation abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            fi
            ;;
            
        # Fallback
        *)
            echo "Unbekannte Desktop-Umgebung. Installiere GNOME..."
            apt-get install -y --no-install-recommends gnome-session gnome-shell gdm3 nautilus nautilus-hide gnome-terminal gnome-text-editor ubuntu-gnome-wallpapers gnome-tweaks virtualbox-guest-additions-iso virtualbox-guest-utils virtualbox-guest-x11
            echo "DEBUG: Desktop-Installation abgeschlossen, exit code: $?" >> /var/log/install-debug.log
            ;;
    esac
fi