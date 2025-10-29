#!/usr/bin/env bash
######################################
# Created by : Meir
# Purpose : Stage 0 system preparation for Raspberry Pi router/AP setup
# Date : 2025-10-29
# Version : 1
######################################

# Fail fast on errors and undefined vars; propagate failures through pipes
set -euo pipefail

# Load shared helpers and environment (expects utils.sh next to this script)
. "$(dirname "$0")/utils.sh"

# Ensure the script is executed with root privileges
require_root

# Load configuration variables (e.g., LAN_IFACE) from env or defaults
load_env

echo "== Stage 0: System prep =="

# Refresh APT package index
apt-get update

# Install required packages if missing; ensure_pkg should be idempotent
# dnsmasq, hostapd: DHCP/DNS and AP services
# iptables-persistent: persist NAT/firewall rules across reboots
# net-tools, curl, gettext-base: basic utilities
# rfkill, iw, usbutils, dhcpcd5: wireless tooling and DHCP client
ensure_pkg dnsmasq hostapd iptables-persistent net-tools curl gettext-base rfkill iw usbutils dhcpcd5

# hostapd may ship masked on some images; unmask to allow enabling/starting
systemctl unmask hostapd || true

# Stop services to allow clean reconfiguration before later stages
systemctl stop hostapd || true
systemctl stop dnsmasq || true

# If NetworkManager is present, mark the LAN interface as unmanaged to avoid conflicts
nm_mark_unmanaged "$LAN_IFACE" || true

echo "Done Stage 0."
