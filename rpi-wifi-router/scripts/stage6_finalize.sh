#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/utils.sh"
require_root
load_env

echo "== Stage 6: Finalize & persist =="

# 1) Enable services on boot (no restarts here to avoid disrupting SSH)
echo "-- enabling services on boot --"
systemctl enable dhcpcd 2>/dev/null || systemctl enable dhcpcd5 2>/dev/null || true
systemctl enable dnsmasq || true
systemctl enable hostapd || true
systemctl enable netfilter-persistent 2>/dev/null || true

# 2) Persist iptables NAT rules
echo "-- saving iptables rules --"
if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save || true
else
  mkdir -p /etc/iptables
  iptables-save > /etc/iptables/rules.v4
fi

# 3) Quick summary
echo "-- service enablement (is-enabled) --"
for s in dhcpcd dhcpcd5 dnsmasq hostapd netfilter-persistent; do
  systemctl is-enabled "$s" 2>/dev/null && echo "  $s: enabled" || echo "  $s: (not enabled or not present)"
done

echo "-- service runtime (is-active) --"
for s in dnsmasq hostapd; do
  systemctl is-active "$s" && echo "  $s: active" || echo "  $s: inactive"
done

echo "-- NAT rule --"
iptables -t nat -S POSTROUTING | grep MASQUERADE || echo "  (no MASQUERADE found in POSTROUTING)"

echo "-- dhcp leases path --"
test -f /var/lib/misc/dnsmasq.leases && ls -l /var/lib/misc/dnsmasq.leases || echo "  (no leases file yet)"

echo "== Stage 6 complete =="

