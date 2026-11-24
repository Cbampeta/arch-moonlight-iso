#!/usr/bin/env bash
set -uo pipefail

LOG_FILE="/var/log/usbip-auto.log"

log() {
    local msg="[$(date '+%H:%M:%S')] $*"
    echo "${msg}" >> "${LOG_FILE}" 2>/dev/null || true
    logger -t usbip-auto "$*" 2>/dev/null || true
}

is_ignored_vidpid() {
    local vidpid="$1"
    for cfg in /etc/thinclient/usbip-ignore.conf /etc/thinclient/custom/usbip-ignore.conf; do
        if [[ -f "${cfg}" ]] && grep -iqE "^[[:space:]]*${vidpid}[[:space:]]*(#.*)?$" "${cfg}"; then
            return 0
        fi
    done
    return 1
}

is_protected_storage() {
    local dev_real="$1"
    for blk in /sys/class/block/*; do
        [[ -e "${blk}" ]] || continue
        local blk_real
        blk_real="$(readlink -f "${blk}" 2>/dev/null || true)"
        if [[ "${blk_real}" == "${dev_real}"/* ]]; then
            local blk_name
            blk_name="$(basename "${blk}")"

            # Currently mounted?
            if findmnt -rn -S "/dev/${blk_name}" >/dev/null 2>&1; then
                return 0
            fi

            # Held by device-mapper (e.g. Ventoy dm-linear)?
            if [[ -d "${blk}/holders" ]] && [[ -n "$(ls -A "${blk}/holders" 2>/dev/null)" ]]; then
                return 0
            fi

            # Ventoy / VTOYEFI partition?
            local lbl
            lbl="$(blkid -o value -s LABEL "/dev/${blk_name}" 2>/dev/null || true)"
            if [[ "${lbl}" == "Ventoy" || "${lbl}" == "VTOYEFI" ]]; then
                return 0
            fi
        fi
    done
    return 1
}

should_skip_device() {
    local busid="$1"
    local sysdev="/sys/bus/usb/devices/${busid}"

    # Must be a valid USB device (not an interface or root hub)
    [[ -d "${sysdev}" && -f "${sysdev}/idVendor" && -f "${sysdev}/idProduct" ]] || return 0
    [[ "${busid}" == usb* ]] && return 0

    local dev_class vid pid vidpid
    dev_class="$(cat "${sysdev}/bDeviceClass" 2>/dev/null || true)"
    vid="$(cat "${sysdev}/idVendor" 2>/dev/null || true)"
    pid="$(cat "${sysdev}/idProduct" 2>/dev/null || true)"
    vidpid="${vid}:${pid}"

    # 1. Skip USB hubs
    if [[ "${dev_class}" == "09" ]]; then
        return 0
    fi

    # 2. Custom ignore list
    if is_ignored_vidpid "${vidpid}"; then
        log "SKIP ${busid} (${vidpid}): custom ignore list"
        return 0
    fi

    # 3. Protect Ventoy USB drive / mounted storage / device-mapper holders
    local dev_real
    dev_real="$(readlink -f "${sysdev}" 2>/dev/null || true)"
    if [[ -n "${dev_real}" ]] && is_protected_storage "${dev_real}"; then
        log "SKIP ${busid} (${vidpid}): protected storage (Ventoy / mounted)"
        return 0
    fi

    # 4. Inspect interfaces: skip local keyboard/mouse (HID Boot) and USB network adapters
    for iface in "${sysdev}/${busid}:"*; do
        [[ -d "${iface}" ]] || continue
        local iclass iproto
        iclass="$(cat "${iface}/bInterfaceClass" 2>/dev/null || true)"
        iproto="$(cat "${iface}/bInterfaceProtocol" 2>/dev/null || true)"

        # HID Keyboard (03/01) or HID Mouse (03/02)
        if [[ "${iclass}" == "03" && ( "${iproto}" == "01" || "${iproto}" == "02" ) ]]; then
            log "SKIP ${busid} (${vidpid}): local keyboard/mouse (HID proto=${iproto})"
            return 0
        fi

        # USB network adapter (Wi-Fi / Ethernet / Tethering)
        if [[ -d "${iface}/net" ]]; then
            log "SKIP ${busid} (${vidpid}): USB network interface"
            return 0
        fi
    done

    return 1
}

bind_device() {
    local busid="$1"
    local sysdev="/sys/bus/usb/devices/${busid}"

    # Give the kernel time to enumerate interfaces and block devices (important for Ventoy/HID detection)
    sleep 1

    [[ -d "${sysdev}" ]] || return 0

    if should_skip_device "${busid}"; then
        return 0
    fi

    # Already bound to usbip-host?
    local drv
    drv="$(basename "$(readlink -f "${sysdev}/driver" 2>/dev/null || true)" 2>/dev/null || true)"
    if [[ "${drv}" == "usbip-host" ]]; then
        return 0
    fi

    local vid pid prod
    vid="$(cat "${sysdev}/idVendor" 2>/dev/null || echo "????")"
    pid="$(cat "${sysdev}/idProduct" 2>/dev/null || echo "????")"
    prod="$(cat "${sysdev}/product" 2>/dev/null || echo "USB Device")"

    modprobe usbip-core 2>/dev/null || true
    modprobe usbip-host 2>/dev/null || true

    if usbip bind -b "${busid}" >/dev/null 2>&1; then
        log "EXPORT ${busid} (${vid}:${pid} - ${prod}) -> ready for USB/IP"
    else
        log "ERR ${busid} (${vid}:${pid}): usbip bind failed"
    fi
}

ACTION="${1:-}"
BUSID="${2:-}"

case "${ACTION}" in
    add)
        [[ -n "${BUSID}" ]] && bind_device "${BUSID}"
        ;;
    remove)
        [[ -n "${BUSID}" ]] && log "REMOVE ${BUSID}: unplugged"
        ;;
    scan)
        log "SCAN: scanning already-connected USB devices..."
        for dev in /sys/bus/usb/devices/*; do
            [[ -f "${dev}/idVendor" ]] || continue
            b="$(basename "${dev}")"
            bind_device "${b}"
        done
        ;;
    *)
        echo "Usage: $0 {add <busid>|remove <busid>|scan}" >&2
        exit 1
        ;;
esac
