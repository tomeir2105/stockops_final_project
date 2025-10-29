#!/usr/bin/env bash
######################################
# Created by : Meir
# Purpose : Stage 3 — Configure hostapd (AP) and dnsmasq (DHCP/DNS) for the LAN interface
# Date : 2025-10-29
# Version : 1
######################################

# Fail on errors, unset vars, and pipeline failures
set -euo pipefail

# Load helpers and environment (expects utils.sh next to this script)
. "$(dirname "$0")/utils.sh"

# Ensure root for network/service operations
require_root

# Load environment (expects ROOT_DIR, LAN_IFACE, LAN_CIDR, COUNTRY_CODE, etc.)
load_env

echo "== Stage 3: Configure hostapd + dnsmasq =="

# Resolve interface variable locally for clarity
LAN="${LAN_IFACE:-wlan1}"

# Unblock Wi-Fi if RF-kill is enabled
if command -v rfkill >/dev/null 2>&1; then
  if rfkill list 2>/dev/null | grep -qi "soft blocked: yes\|hard blocked: yes"; then
    log_warn "RF-kill detected — unblocking Wi-Fi"
    rfkill unblock wifi || rfkill unblock all || true
  fi
fi

# Apply regulatory domain if provided (no failure if iw is missing)
apply_regdom "${COUNTRY_CODE:-}"

# Stop services first to avoid binding conflicts while we rewrite configs
stop_service_if_running "hostapd"
stop_service_if_running "dnsmasq"

# Ensure the LAN interface is free from client-mode processes and not the active WAN
ensure_iface_free_for_ap "$LAN" || true

# Bring the LAN interface up and assign the static IP before dnsmasq binds
ip link set "$LAN" up || true
[ -n "${LAN_CIDR:-}" ] && ip addr replace "${LAN_CIDR}" dev "$LAN" || true

# Render hostapd configuration from template to its canonical path
render "${ROOT_DIR}/config/hostapd.conf.tmpl" "/etc/hostapd/hostapd.conf"

# Tighten permissions because the passphrase resides here
chmod 600 /etc/hostapd/hostapd.conf || true

# Ensure hostapd service points at our config and suppress empty DAEMON_OPTS warnings
if [[ -f /etc/default/hostapd ]]; then
  sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
  grep -q '^DAEMON_OPTS=' /etc/default/hostapd || echo 'DAEMON_OPTS=""' >> /etc/default/hostapd
fi

# Render dnsmasq configuration for LAN and ensure dnsmasq includes /etc/dnsmasq.d
render "${ROOT_DIR}/config/dnsmasq.conf.tmpl" "/etc/dnsmasq.d/wlan1.conf"
grep -q 'conf-dir=/etc/dnsmasq.d,*.conf' /etc/dnsmasq.conf 2>/dev/null || \
  echo 'conf-dir=/etc/dnsmasq.d,*.conf' >> /etc/dnsmasq.conf

# Reload unit files in case templates dropped any new services or overrides
systemctl daemon-reload || true

# Informational port checks (help diagnose conflicts with systemd-resolved, bind9, etc.)
echo "UDP/53:"; port_in_use udp 53 || echo "(free)"
echo "TCP/53:"; port_in_use tcp 53 || echo "(free)"
echo "UDP/67:"; port_in_use udp 67 || echo "(free)"

# Start services with helper if available, else fallback to plain systemctl
if declare -F start_service_and_verify >/dev/null 2>&1; then
  start_service_and_verify "dnsmasq"
  start_service_and_verify "hostapd"
else
  log_warn "start_service_and_verify not found; using plain systemctl"
  systemctl start dnsmasq
  systemctl start hostapd
  sleep 1
  systemctl is-active dnsmasq && echo "dnsmasq: active" || (echo "dnsmasq: failed"; exit 1)
  systemctl is-active hostapd && echo "hostapd: active" || (echo "hostapd: failed"; journalctl -xeu hostapd -n 50 --no-pager || true; exit 1)
fi

echo "Done Stage 3."
