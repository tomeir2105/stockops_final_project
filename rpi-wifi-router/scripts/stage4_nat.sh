#!/usr/bin/env bash
######################################
# Created by : Meir
# Purpose : Stage 4 — Configure IPv4 forwarding, NAT, and persist iptables rules
# Date : 2025-10-29
# Version : 1
######################################

# Exit on errors, unset variables, and failures within pipelines
set -euo pipefail

# Load helpers and environment (expects utils.sh next to this script)
. "$(dirname "$0")/utils.sh"

# Ensure root privileges for sysctl and iptables operations
require_root

# Load configuration variables (expects ROOT_DIR, LAN_SUBNET, WAN_IFACE, etc.)
load_env

echo "== Stage 4: Routing & NAT =="

# Persist forwarding and other router-related sysctls via drop-in file
# The source may be a template or a static file under config/
render "${ROOT_DIR}/config/sysctl_router.conf" "/etc/sysctl.d/99-rpi-router.conf"

# Enable IPv4 forwarding immediately to avoid requiring a reboot
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true

# Reload all sysctl drop-ins so persistence takes effect for current boot
sysctl --system > /dev/null

# Prepare and apply iptables NAT rules
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
render "${ROOT_DIR}/config/iptables.rules.v4.tmpl" "$TMP"

# Restore rules atomically from the rendered file
iptables-restore < "$TMP"

# Persist rules for iptables-persistent to load on boot
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4

# Informational summary of the NAT mapping
echo "NAT set: ${LAN_SUBNET}/24 -> ${WAN_IFACE}"
echo "Done Stage 4."
