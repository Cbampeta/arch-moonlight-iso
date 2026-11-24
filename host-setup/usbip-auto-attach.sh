#!/usr/bin/env bash
set -uo pipefail

CONF_FILE="/etc/usbip-auto-attach.conf"
THINCLIENT_HOST="arch-thinclient"
POLL_INTERVAL=2

[[ -f "${CONF_FILE}" ]] && source "${CONF_FILE}"

modprobe vhci-hcd 2>/dev/null || true

resolve_ip() {
    local host="$1"
    # Already an IPv4 address?
    if [[ "${host}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "${host}"
        return 0
    fi
    # Resolve via Tailscale first
    local ip
    ip="$(tailscale ip -4 "${host}" 2>/dev/null | head -n1 || true)"
    if [[ -n "${ip}" ]]; then
        echo "${ip}"
        return 0
    fi
    # Fallback to DNS / MagicDNS
    ip="$(getent ahostsv4 "${host}" 2>/dev/null | awk 'NR==1 {print $1}' || true)"
    [[ -n "${ip}" ]] && echo "${ip}"
}

logger -t usbip-auto-attach "Starting USB/IP receiver (target: ${THINCLIENT_HOST}, interval: ${POLL_INTERVAL}s)"

while true; do
    TARGET_IP="$(resolve_ip "${THINCLIENT_HOST}" || true)"

    if [[ -n "${TARGET_IP}" ]]; then
        # List devices exported by the thin client (short 3s timeout)
        REMOTE_LIST="$(timeout 3 usbip list -r "${TARGET_IP}" 2>/dev/null || true)"
        if [[ -n "${REMOTE_LIST}" ]]; then
            # Extract exported busids (format: "   1-2: Vendor : Product (xxxx:yyyy)")
            BUSIDS="$(echo "${REMOTE_LIST}" | awk -F':' '/^[[:space:]]+[0-9]+-[0-9]+(\.[0-9]+)*:/ {gsub(/^[[:space:]]+/, "", $1); print $1}')"
            if [[ -n "${BUSIDS}" ]]; then
                ATTACHED_PORTS="$(usbip port 2>/dev/null || true)"
                for busid in ${BUSIDS}; do
                    # Skip if already attached from this IP and busid
                    if echo "${ATTACHED_PORTS}" | grep -qF "usbip://${TARGET_IP}:3240/${busid}"; then
                        continue
                    fi
                    logger -t usbip-auto-attach "Auto-attaching ${TARGET_IP}/${busid}..."
                    if timeout 5 usbip attach -r "${TARGET_IP}" -b "${busid}" >/dev/null 2>&1; then
                        logger -t usbip-auto-attach "OK: ${TARGET_IP}/${busid} attached locally"
                    else
                        logger -t usbip-auto-attach "Failed to attach ${TARGET_IP}/${busid}"
                    fi
                done
            fi
        fi
    fi

    sleep "${POLL_INTERVAL}"
done
