#!/usr/bin/env bash
######################################
# Created by : Meir
# Purpose : Stage 6 — Enable and restart network/AP services to run on boot
# Date : 2025-10-29
# Version : 1
######################################

# Fail on errors, undefined variables, and pipeline failures
set -euo pipefail

# Load shared helpers and environment (expects utils.sh next to this script)
. "$(dirname "$0")/utils.sh"

# Ensure root privileges for systemctl operations
require_root

# Load environment for consistency, even if this stage uses no vars directly
load_env

echo "== Stage 6: Enable services on boot =="

# dhcpcd service name differs across images; try both and do not fail hard
systemctl enable dhcpcd || systemctl enable dhcpcd5 || true

# Ensure AP and DHCP/DNS services start automatically on boot
systemctl enable hostapd
systemctl enable dnsmasq

# Restart in dependency-safe order: DHCP client, then AP, then DNS/DHCP server
# dhcpcd provides address/config; hostapd brings up the AP; dnsmasq serves clients
systemctl restart dhcpcd || systemctl restart dhcpcd5 || true
systemctl restart hostapd
systemctl restart dnsmasq

echo "All services enabled. Reboot recommended."
