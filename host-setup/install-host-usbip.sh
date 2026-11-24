#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_LANG="${SCRIPT_LANG:-en}"

msg() {
    local en="$1"
    local fr="$2"
    if [[ "${SCRIPT_LANG}" == "fr" ]]; then
        printf '%s\n' "${fr}"
    else
        printf '%s\n' "${en}"
    fi
}

msg \
    "[*] Installing automatic USB/IP receiver on this host PC..." \
    "[*] Installation du recepteur USB/IP automatique sur ce PC hote..."
sudo pacman -S --needed --noconfirm usbip

sudo install -Dm644 "${SCRIPT_DIR}/usbip-client.conf" /etc/modules-load.d/usbip-client.conf
if [[ ! -f /etc/usbip-auto-attach.conf ]]; then
    sudo install -Dm644 "${SCRIPT_DIR}/usbip-auto-attach.conf" /etc/usbip-auto-attach.conf
else
    msg \
        "[*] /etc/usbip-auto-attach.conf already exists (kept as-is)." \
        "[*] /etc/usbip-auto-attach.conf existe deja (conserve)."
fi
sudo install -Dm755 "${SCRIPT_DIR}/usbip-auto-attach.sh" /usr/local/bin/usbip-auto-attach.sh
sudo install -Dm644 "${SCRIPT_DIR}/usbip-auto-attach.service" /etc/systemd/system/usbip-auto-attach.service

sudo modprobe vhci-hcd
sudo systemctl daemon-reload
sudo systemctl enable --now usbip-auto-attach.service

msg \
    "[OK] USB/IP receiver installed and active!" \
    "[OK] Recepteur USB/IP installe et actif !"
msg \
    "     Status : systemctl status usbip-auto-attach.service" \
    "     Statut : systemctl status usbip-auto-attach.service"
msg \
    "     Logs   : journalctl -u usbip-auto-attach.service -f" \
    "     Logs   : journalctl -u usbip-auto-attach.service -f"
