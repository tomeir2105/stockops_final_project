#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/utils.sh"
require_root
load_env

echo "== Stage 4: Routing & NAT =="

# Persist forwarding (and any other router sysctls) then apply
render "${ROOT_DIR}/config/sysctl_router.conf" "/etc/sysctl.d/99-rpi-router.conf"

# Enable IPv4 forwarding immediately (no reboot needed)
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true

# Reload all sysctl drop-ins to ensure persistence is active
sysctl --system > /dev/null

# Apply iptables NAT rules from template
TMP="$(mktemp)"
render "${ROOT_DIR}/config/iptables.rules.v4.tmpl" "$TMP"
iptables-restore < "$TMP"

# Persist iptables rules (for iptables-persistent)
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4

echo "NAT set: ${LAN_SUBNET}/24 -> ${WAN_IFACE}"
echo "Done Stage 4."

