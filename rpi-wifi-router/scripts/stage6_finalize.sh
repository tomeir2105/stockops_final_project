#!/usr/bin/env bash
######################################
# Created by : Meir
# Purpose : Stage 6 — Finalize router/AP setup: enable services and persist NAT rules
# Date : 2025-10-29
# Version : 1
######################################

# Fail on errors, undefined variables, and pipeline failures
set -euo pipefail

# Load shared helpers and environment variables (expects utils.sh next to this script)
. "$(dirname "$0")/utils.sh"

# Ensure we have root privileges for system modifications
require_root

# Load environment for consistency (interfaces, paths, etc.)
load_env

echo "== Stage 6: Finalize & persist =="

# 1) Enable services on boot (avoid restarts here to reduce risk of dropping SSH)
echo "-- enabling services on boot --"
# dhcpcd may be named dhcpcd or dhcpcd5 depending on image
systemctl enable dhcpcd 2>/dev/null || systemctl enable dhcpcd5 2>/dev/null || true
# Enable dnsmasq and hostapd so AP/DHCP come up automatically after reboot
systemctl enable dnsmasq || true
systemctl enable hostapd || true
# Enable netfilter-persistent when available to auto-restore iptables on boot
systemctl enable netfilter-persistent 2>/dev/null || true

# 2) Persist iptables NAT rules for subsequent boots
echo "-- saving iptables rules --"
if command -v netfilter-persistent >/dev/null 2>&1; then
  # Use the helper to save rules to the canonical location
  netfilter-persistent save || true
else
  # Fallback to iptables-save into rules.v4 which iptables-persistent reads
  mkdir -p /etc/iptables
  iptables-save > /etc/iptables/rules.v4
fi

# 3) Quick summary of enablement and runtime state to help verify configuration
echo "-- service enablement (is-enabled) --"
for s in dhcpcd dhcpcd5 dnsmasq hostapd netfilter-persistent; do
  systemctl is-enabled "$s" 2>/dev/null && echo "  $s: enabled" || echo "  $s: (not enabled or not present)"
done

echo "-- service runtime (is-active) --"
for s in dnsmasq hostapd; do
  systemctl is-active "$s" && echo "  $s: active" || echo "  $s: inactive"
done

# Show whether a MASQUERADE rule exists in POSTROUTING (NAT table)
echo "-- NAT rule --"
iptables -t nat -S POSTROUTING | grep MASQUERADE || echo "  (no MASQUERADE found in POSTROUTING)"

# Show presence and path of dnsmasq leases file for quick DHCP verification
echo "-- dhcp leases path --"
test -f /var/lib/misc/dnsmasq.leases && ls -l /var/lib/misc/dnsmasq.leases || echo "  (no leases file yet)"

echo "== Stage 6 complete =="
