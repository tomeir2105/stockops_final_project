#!/usr/bin/env bash
######################################
# Created by : Meir
# Purpose : Stage 1 — Verify WAN interface gets IPv4 via DHCP and show quick diagnostics
# Date : 2025-10-29
# Version : 1
######################################

# Exit on errors, unset vars, and any failing command in a pipeline
set -euo pipefail

# Load shared helpers and environment (expects utils.sh next to this script)
. "$(dirname "$0")/utils.sh"

# Ensure root permissions for network queries that may require them
require_root

# Load environment defaults (e.g., WAN_IFACE)
load_env

# Prefer provided WAN_IFACE; default to wlan0 if not set
WAN="${WAN_IFACE:-wlan0}"

echo "== Stage 1: WAN check (DHCP on ${WAN}) =="

# Ensure the interface exists at the kernel level
ip link show "$WAN" > /dev/null

echo "Detected interface: $WAN"

# Run extended interface diagnostics if helper exists
# iface_diag is expected to print link state, carrier, speed, and addresses
if declare -F iface_diag >/dev/null 2>&1; then
  iface_diag "$WAN" || true
fi

# Capture IPv4 address (CIDR form) if present
IPV4_CIDR="$(ip -4 -o addr show dev "$WAN" | awk '{print $4}' | head -n1 || true)"
IPV4="${IPV4_CIDR%%/*}"

# Determine default gateway associated with this interface if any
GATEWAY="$(ip route show dev "$WAN" | awk '/^default/ {print $3}' | head -n1 || true)"
[ -z "${GATEWAY:-}" ] && GATEWAY="$(ip route | awk '/^default/ {print $3}' | head -n1 || true)"

# Extract DNS servers from resolvectl if available, otherwise from resolv.conf
if command -v resolvectl >/dev/null 2>&1; then
  DNS="$(resolvectl dns "$WAN" 2>/dev/null | awk '{for(i=2;i<=NF;i++) printf (i==NF?$i:$i", ")}' || true)"
else
  DNS="$(awk '/^nameserver/ {print $2}' /etc/resolv.conf 2>/dev/null | paste -sd, - || true)"
fi

echo "IPv4 address: ${IPV4:-none}"
echo "Gateway     : ${GATEWAY:-none}"
echo "DNS         : ${DNS:-none}"

# Provide actionable guidance if no IPv4 is assigned
if [ -z "${IPV4:-}" ]; then
  echo "No IPv4 address detected on ${WAN}."
  echo "If this is Wi-Fi, connect ${WAN} to your home network before continuing."
  echo "Examples:"
  echo "  nmcli dev wifi connect \"<SSID>\" password \"<PASS>\" ifname ${WAN}    # NetworkManager"
  echo "  wpa_cli -i ${WAN} reconfigure                                         # wpa_supplicant"
fi

echo "Done Stage 1."
