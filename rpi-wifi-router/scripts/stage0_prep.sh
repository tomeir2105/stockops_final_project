#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/utils.sh"
require_root
load_env

echo "== Stage 0: System prep =="
apt-get update
ensure_pkg dnsmasq hostapd iptables-persistent net-tools curl gettext-base rfkill iw usbutils dhcpcd5

# hostapd occasionally ships masked; ensure it's unmasked
systemctl unmask hostapd || true

# Stop services for clean reconfig
systemctl stop hostapd || true
systemctl stop dnsmasq || true

# Mark LAN_IFACE unmanaged in NetworkManager (if present)
nm_mark_unmanaged "$LAN_IFACE" || true

echo "Done Stage 0."

