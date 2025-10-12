#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/utils.sh"
require_root
load_env

echo "== Stage 5: Health & Troubleshooting =="

echo "-- Interfaces --"
iface_diag "$WAN_IFACE"
iface_diag "$LAN_IFACE"

echo "-- IP Forwarding --"
sysctl net.ipv4.ip_forward

echo "-- Services --"
systemctl is-active hostapd && echo "hostapd: active" || echo "hostapd: inactive"
systemctl is-active dnsmasq && echo "dnsmasq: active" || echo "dnsmasq: inactive"

echo "-- Ports --"
echo "UDP/53:"; port_in_use udp 53 || echo "(free)"
echo "TCP/53:"; port_in_use tcp 53 || echo "(free)"
echo "UDP/67:"; port_in_use udp 67 || echo "(free)"
echo "UDP/68:"; port_in_use udp 68 || echo "(free)"

echo "-- Last logs --"
echo "-- hostapd --"; journalctl -u hostapd -n 50 --no-pager || true
echo "-- dnsmasq --"; journalctl -u dnsmasq -n 50 --no-pager || true

echo "-- AP capability check --"
check_ap_capability || true

