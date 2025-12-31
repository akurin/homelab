#!/bin/bash
set -euo pipefail

# Configuration
TPROXY_MARK="0x1"
TPROXY_TABLE="100"
NFT_FILE="xray_tproxy.nft"

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

set_on() {
    echo "Starting TProxy setup..."

    # Check for rule - we use '|| true' or an 'if' to prevent 'set -e' from killing the script
    if ! ip rule show | grep -q "fwmark ${TPROXY_MARK} lookup ${TPROXY_TABLE}"; then
        ip rule add fwmark "$TPROXY_MARK" lookup "$TPROXY_TABLE"
        ip route add local default dev lo table "$TPROXY_TABLE"
    fi

    if ! ip -6 rule show | grep -q "fwmark ${TPROXY_MARK} lookup ${TPROXY_TABLE}"; then
        ip -6 rule add fwmark "$TPROXY_MARK" lookup "$TPROXY_TABLE"
        ip -6 route add local default dev lo table "$TPROXY_TABLE"
    fi

    if [ -f "$NFT_FILE" ]; then
        nft -f "$NFT_FILE"
    else
        echo "Error: $NFT_FILE missing"
        exit 1
    fi

    echo "TProxy is now ON"
}

set_off() {
    echo "Cleaning up..."
    # '|| true' allows the script to finish even if rules were already gone
    ip rule del fwmark "$TPROXY_MARK" lookup "$TPROXY_TABLE" 2>/dev/null || true
    ip route flush table "$TPROXY_TABLE" 2>/dev/null || true
    
    ip -6 rule del fwmark "$TPROXY_MARK" lookup "$TPROXY_TABLE" 2>/dev/null || true
    ip -6 route flush table "$TPROXY_TABLE" 2>/dev/null || true

    nft delete table inet xray_tproxy 2>/dev/null || true
    nft delete table inet xray_tproxy_local 2>/dev/null || true

    echo "TProxy is now OFF"
}

case "${1:-}" in
    on)  set_on ;;
    off) set_off ;;
    *)   echo "Usage: $0 {on|off}"; exit 1 ;;
esac

