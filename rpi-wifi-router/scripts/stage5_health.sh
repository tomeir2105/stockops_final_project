#!/usr/bin/env bash
######################################
# Created by : Meir
# Purpose : Stage 5 — Health checks and quick troubleshooting for RPi router/AP
# Date : 2025-10-29
# Version : 1
######################################

# Fail on errors, unset variables, and failures in pipelines
set -euo pipefail

# Load shared helpers and environment (expects utils.sh next to this script)
. "$(dirname "$0")/utils.sh"

# Require root privileges for system queries that need them
require_root

# Load environment (expects WAN_IFACE, LAN_IFACE, etc.)
load_env

echo "== Stage 5: Health & Troubleshooting =="

# Show concise status for WAN and LAN interfaces (link, addresses, carrier)
echo "-- Interfaces --"
iface_diag "$WAN_IFACE"
iface_diag "$LAN_IFACE"

# Verify IPv4 forwarding is enabled (should be 'net.ipv4.ip_forward = 1')
echo "-- IP Forwarding --"
sysctl net.ipv4.ip_forward

# Confirm critical services are up
echo "-- Services --"
systemctl is-active hostapd && echo "hostapd: active" || echo "hostapd: inactive"
systemctl is-active dnsmasq && echo "dnsmasq: active" || echo "dnsmasq: inactive"

# Check for common port conflicts on DNS and DHCP
echo "-- Ports --"
echo "UDP/53:"; port_in_use udp 53 || echo "(free)"
echo "TCP/53:"; port_in_use tcp 53 || echo "(free)"
echo "UDP/67:"; port_in_use udp 67 || echo "(free)"
echo "UDP/68:"; port_in_use udp 68 || echo "(free)"

# Tail the last 50 log lines for quick triage
echo "-- Last logs --"
echo "-- hostapd --"; journalctl -u hostapd -n 50 --no-pager || true
echo "-- dnsmasq --"; journalctl -u dnsmasq -n 50 --no-pager || true

# Validate that the wireless hardware and driver support AP mode
echo "-- AP capability check --"
check_ap_capability || true

echo "Done Stage 5."
