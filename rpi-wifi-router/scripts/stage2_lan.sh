#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/utils.sh"
require_root
load_env

echo "== Stage 2: LAN static IP on ${LAN_IFACE} via dhcpcd =="

# Ensure dhcpcd is installed & enabled
systemctl enable --now dhcpcd || systemctl enable --now dhcpcd5 || true

ensure_iface_up "$LAN_IFACE" 15 1 || echo "Continuing despite iface not reporting UP..."

CONF="/etc/dhcpcd.conf"
BEGIN="# --- RPI-WIFI-ROUTER BEGIN WLAN1 ---"
END="# --- RPI-WIFI-ROUTER END WLAN1 ---"
TMP="$(mktemp)"
render "${ROOT_DIR}/config/dhcpcd_wlan1.conf.tmpl" "$TMP"

# Remove old block if exists
if [[ -f "$CONF" ]] && grep -q "$BEGIN" "$CONF"; then
  sed -i "/$BEGIN/,/$END/d" "$CONF"
fi

{
  echo "$BEGIN"
  cat "$TMP"
  echo "$END"
} >> "$CONF"

systemctl restart dhcpcd || systemctl restart dhcpcd5 || true
ip link set "$LAN_IFACE" up || true
ip addr replace "${LAN_CIDR}" dev "$LAN_IFACE" || true

iface_diag "$LAN_IFACE"
echo "Done Stage 2."

