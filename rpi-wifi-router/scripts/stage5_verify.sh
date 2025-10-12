#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/utils.sh"
require_root
load_env

echo "== Stage 5: Verify services and networking =="

echo "-- iptables rules --"
iptables -t nat -L -n -v | grep MASQUERADE || echo "No MASQUERADE rule found"

echo "-- sysctl forwarding --"
sysctl net.ipv4.ip_forward

echo "-- hostapd status --"
systemctl is-active hostapd && echo "hostapd running" || echo "hostapd NOT running"

echo "-- dnsmasq status --"
systemctl is-active dnsmasq && echo "dnsmasq running" || echo "dnsmasq NOT running"

echo "-- DHCP leases --"
test -f /var/lib/misc/dnsmasq.leases && cat /var/lib/misc/dnsmasq.leases || echo "no leases yet"

echo "== Stage 5 complete =="

