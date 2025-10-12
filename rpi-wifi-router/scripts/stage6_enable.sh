#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/utils.sh"
require_root
load_env

echo "== Stage 6: Enable services on boot =="
systemctl enable dhcpcd || systemctl enable dhcpcd5 || true
systemctl enable hostapd
systemctl enable dnsmasq
systemctl restart dhcpcd || systemctl restart dhcpcd5 || true
systemctl restart hostapd
systemctl restart dnsmasq
echo "All services enabled. Reboot recommended."

