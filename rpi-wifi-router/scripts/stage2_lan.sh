#!/usr/bin/env bash
######################################
# Created by : Meir
# Purpose : Stage 2 — Configure LAN interface with static IP using dhcpcd (wlan1)
# Date : 2025-10-29
# Version : 1
######################################

# Fail fast and propagate failures through pipelines
set -euo pipefail

# Load shared helpers and environment variables (expects utils.sh next to this script)
. "$(dirname "$0")/utils.sh"

# Require root for network/service operations
require_root

# Load config (expects variables like ROOT_DIR, LAN_IFACE, LAN_CIDR)
load_env

echo "== Stage 2: LAN static IP on ${LAN_IFACE} via dhcpcd =="

# Ensure dhcpcd service is present and running; support both names (dhcpcd/dhcpcd5)
systemctl enable --now dhcpcd || systemctl enable --now dhcpcd5 || true

# Bring interface up, waiting a short time for carrier if needed
ensure_iface_up "$LAN_IFACE" 15 1 || echo "Continuing despite iface not reporting UP..."

# dhcpcd.conf path and managed block markers
CONF="/etc/dhcpcd.conf"
BEGIN="# --- RPI-WIFI-ROUTER BEGIN WLAN1 ---"
END="# --- RPI-WIFI-ROUTER END WLAN1 ---"

# Create a temp file for the rendered template and ensure cleanup
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# Render static-IP configuration for wlan1 from template
# Template should use variables provided by load_env (e.g., LAN_CIDR, LAN_IFACE, etc.)
render "${ROOT_DIR}/config/dhcpcd_wlan1.conf.tmpl" "$TMP"

# Remove any previous managed block to keep idempotency
if [[ -f "$CONF" ]] && grep -q "$BEGIN" "$CONF"; then
  sed -i "/$BEGIN/,/$END/d" "$CONF"
fi

# Append the freshly rendered block
{
  echo "$BEGIN"
  cat "$TMP"
  echo "$END"
} >> "$CONF"

# Restart dhcpcd to apply configuration (support both service names)
systemctl restart dhcpcd || systemctl restart dhcpcd5 || true

# Bring link up explicitly and assign the static address immediately (without waiting for dhcpcd)
ip link set "$LAN_IFACE" up || true
ip addr replace "${LAN_CIDR}" dev "$LAN_IFACE" || true

# Show interface diagnostics for verification
iface_diag "$LAN_IFACE"

echo "Done Stage 2."
