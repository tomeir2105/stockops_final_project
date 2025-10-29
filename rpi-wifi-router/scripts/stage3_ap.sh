#!/usr/bin/env bash
######################################
# Created by : Meir
# Purpose : Stage 3 — Configure hostapd (AP) and dnsmasq (DHCP/DNS) for wlan1 LAN
# Date : 2025-10-29
# Version : 1
######################################

# Fail on errors/undefined vars and propagate pipeline failures
set -euo pipefail

# Load shared helpers and environment (expects utils.sh next to this script)
. "$(dirname "$0")/utils.sh"

# Require root privileges for network/service operations
require_root

# Load environment (expects ROOT_DIR, LAN_IFACE, LAN_CIDR, etc.)
load_env

echo "== Stage 3: Configure hostapd + dnsmasq =="

# Stop services first to avoid binding conflicts while we rewrite configs
stop_service_if_running "hostapd"
stop_service_if_running "dnsmasq"

# Ensure the LAN interface exists and has the static IP prior to starting dnsmasq
# dnsmasq binds to the interface and will fail if it is down or lacks an address
ip link set "$LAN_IFACE" up || true
ip addr replace "${LAN_CIDR}" dev "$LAN_IFACE" || true

# Render hostapd configuration from template to its canonical path
render "${ROOT_DIR}/config/hostapd.conf.tmpl" "/etc/hostapd/hostapd.conf"

# Ensure hostapd service points at our config and suppress empty DAEMON_OPTS warnings
if [[ -f /etc/default/hostapd ]]; then
  sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
  grep -q '^DAEMON_OPTS=' /etc/default/hostapd || echo 'DAEMON_OPTS=""' >> /etc/default/hostapd
fi

# Render dnsmasq configuration for wlan1 and ensure dnsmasq reads from /etc/dnsmasq.d
render "${ROOT_DIR}/config/dnsmasq.conf.tmpl" "/etc/dnsmasq.d/wlan1.conf"
echo 'conf-dir=/etc/dnsmasq.d,*.conf' > /etc/dnsmasq.conf

# Reload unit files in case templates dropped any new services or overrides
systemctl daemon-reload

# Quick, informative port checks (not fatal). Helps diagnose conflicts with systemd-resolved, bind9, etc.
echo "UDP/53:"; port_in_use udp 53 || echo "(free)"
echo "TCP/53:"; port_in_use tcp 53 || echo "(free)"
echo "UDP/67:"; port_in_use udp 67 || echo "(free)"

# Start services in safe order: DNS/DHCP first, then AP
start_service_and_verify "dnsmasq"
start_service_and_verify "hostapd"

echo "Done Stage 3."
