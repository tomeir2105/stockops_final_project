#!/usr/bin/env bash
######################################
# Created by : Meir
# Purpose : Stage 5 — Verify services, NAT, and basic networking health
# Date : 2025-10-29
# Version : 1
######################################

# Fail on errors, undefined variables, and pipeline failures
set -euo pipefail

# Load shared helpers and environment (expects utils.sh next to this script)
. "$(dirname "$0")/utils.sh"

# Ensure root for iptables/sysctl/service checks
require_root

# Load environment variables and defaults (e.g., interfaces)
load_env

echo "== Stage 5: Verify services and networking =="

# Show NAT table MASQUERADE rules; if none found, print a clear notice
echo "-- iptables rules --"
iptables -t nat -L -n -v | grep MASQUERADE || echo "No MASQUERADE rule found"

# Verify IPv4 forwarding kernel knob (should be = 1 for routing to work)
echo "-- sysctl forwarding --"
sysctl net.ipv4.ip_forward

# Check if hostapd is active; print concise status
echo "-- hostapd status --"
systemctl is-active hostapd && echo "hostapd running" || echo "hostapd NOT running"

# Check if dnsmasq is active; print concise status
echo "-- dnsmasq status --"
systemctl is-active dnsmasq && echo "dnsmasq running" || echo "dnsmasq NOT running"

# Show current DHCP leases (if any) managed by dnsmasq
echo "-- DHCP leases --"
test -f /var/lib/misc/dnsmasq.leases && cat /var/lib/misc/dnsmasq.leases || echo "no leases yet"

echo "== Stage 5 complete =="
