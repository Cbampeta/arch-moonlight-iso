# ~/.bash_profile
[[ -f ~/.bashrc ]] && . ~/.bashrc

if [[ "$(tty)" == "/dev/tty1" && -z "${DISPLAY:-}" ]]; then
    clear
    echo "=========================================="
    echo "   Arch Moonlight ThinClient (USB/IP)     "
    echo "=========================================="
    echo "Tip: Ctrl+Alt+F2 -> terminal (Wi-Fi, Tailscale, USB/IP, archinstall)"
    echo ""

    sudo /usr/local/bin/thin-unlock-state || true

    echo ""
    echo "Starting Moonlight on TTY1..."
    sleep 1

    while true; do
        startx /usr/local/bin/thin-xsession -- :0 vt1 -keeptty >/tmp/xorg-thin.log 2>&1
        echo ""
        echo "Moonlight exited."
        echo "  [Enter] Relaunch Moonlight"
        echo "  [n]     Network / Wi-Fi (nmtui)"
        echo "  [t]     Tailscale status (tailscale status)"
        echo "  [u]     USB/IP status (usbip-status)"
        echo "  [s]     Open a bash shell"
        echo "  [p]     Power off"
        read -rp "Choice: " choice
        case "${choice}" in
            n|N) nmtui ;;
            t|T) tailscale status; read -rp "Press Enter to continue..." _ ;;
            u|U) sudo /usr/local/bin/usbip-status; read -rp "Press Enter to continue..." _ ;;
            s|S) break ;;
            p|P) systemctl poweroff; break ;;
            *) ;;
        esac
    done
fi
