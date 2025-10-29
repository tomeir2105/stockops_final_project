#!/usr/bin/env bash
######################################
# Created by : Meir
# Purpose : Stage 1 — Verify WAN interface connectivity (link, DHCP, IP, route, DNS, connectivity)
# Date : 2025-10-29
# Version : 1
######################################

# Exit on errors, unset vars, and failing pipelines
set -euo pipefail

# Optional behavior:
#   --require-ip   Exit non-zero if no IPv4 is assigned (useful in CI/automation)
REQUIRE_IP=0
for arg in "$@"; do
  case "$arg" in
    --require-ip) REQUIRE_IP=1 ;;
  esac
done

# Load shared helpers and environment (expects utils.sh next to this script)
. "$(dirname "$0")/utils.sh"

# Ensure root for network and journal queries
require_root

# Load environment (expects WAN_IFACE if defined)
load_env

# Choose WAN interface from env or default to wlan0
WAN="${WAN_IFACE:-wlan0}"

# Timestamp for easier log correlation
STAMP="$(date '+%Y-%m-%d %H:%M:%S')"

echo "== Stage 1: WAN check (DHCP on ${WAN}) @ ${STAMP} =="

# Verify the interface exists; fail fast with a helpful message
if ! ip link show "$WAN" >/dev/null 2>&1; then
  echo "ERROR: Interface ${WAN} does not exist. Set WAN_IFACE in config/.env or plug the device."
  exit 1
fi

echo "-- Interface presence --"
echo "Detected interface: ${WAN}"

# Link state and carrier
echo "-- Link state --"
STATE="$(ip -o link show "$WAN" | awk -F', ' '{print $3}' | awk '{print $2}' || true)"
CARRIER_FILE="/sys/class/net/${WAN}/carrier"
if [[ -r "$CARRIER_FILE" ]]; then
  CARRIER_VAL="$(cat "$CARRIER_FILE" 2>/dev/null || true)"
  [[ "$CARRIER_VAL" == "1" ]] && CARRIER="carrier: yes" || CARRIER="carrier: no"
else
  CARRIER="carrier: unknown"
fi
echo "state: ${STATE:-unknown} | ${CARRIER}"

# Extended diagnostics from utils (rfkill, iw info, addresses, routes, dmesg slice)
if declare -F iface_diag >/dev/null 2>&1; then
  iface_diag "$WAN" || true
fi

# Wi-Fi specifics if applicable
if command -v iw >/dev/null 2>&1 && iw dev "$WAN" info >/dev/null 2>&1; then
  echo "-- Wi-Fi link (iw) --"
  iw dev "$WAN" link || true
fi

# IPv4 addresses list
echo "-- IPv4 addresses --"
IPV4_LIST="$(ip -4 -o addr show dev "$WAN" | awk '{print $4}' || true)"
if [[ -z "$IPV4_LIST" ]]; then
  echo "(none)"
else
  echo "$IPV4_LIST"
fi

# Extract the first IPv4 for convenience
IPV4_CIDR="$(echo "$IPV4_LIST" | head -n1 || true)"
IPV4="${IPV4_CIDR%%/*}"

# Default gateway detection bound to this interface first, then global fallback
echo "-- Default route --"
GATEWAY="$(ip route | awk -v dev="$WAN" '$1=="default" && $5==dev {print $3; exit}' || true)"
[[ -z "${GATEWAY:-}" ]] && GATEWAY="$(ip route | awk '/^default/ {print $3}' | head -n1 || true)"
echo "gateway: ${GATEWAY:-none}"

# DNS servers (prefer resolvectl; fallback to resolv.conf)
echo "-- DNS servers --"
if command -v resolvectl >/dev/null 2>&1; then
  DNS="$(resolvectl dns "$WAN" 2>/dev/null | awk 'NR==1 {$1=""; sub(/^ /,""); gsub(/ +/, ","); print}' || true)"
  [[ -z "${DNS:-}" ]] && DNS="$(resolvectl dns 2>/dev/null | awk 'NR==1 {$1=""; sub(/^ /,""); gsub(/ +/, ","); print}' || true)"
else
  DNS="$(awk '/^nameserver/ {print $2}' /etc/resolv.conf 2>/dev/null | paste -sd, - || true)"
fi
echo "dns: ${DNS:-none}"

# DHCP client hints (non-fatal)
echo "-- DHCP client hints --"
if command -v dhcpcd >/dev/null 2>&1; then
  dhcpcd -U "$WAN" 2>/dev/null || echo "dhcpcd query not available"
elif command -v nmcli >/dev/null 2>&1; then
  nmcli -g IP4.ADDRESS,IP4.GATEWAY,IP4.DNS device show "$WAN" 2>/dev/null || echo "nmcli info not available"
else
  echo "No dhcpcd or NetworkManager tools found for DHCP query"
fi

# Connectivity probes (non-fatal; skipped without an IPv4)
echo "-- Connectivity tests --"
if [[ -n "${IPV4:-}" ]]; then
  ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 && echo "ping 1.1.1.1: ok" || echo "ping 1.1.1.1: fail"
  if command -v getent >/dev/null 2>&1; then
    getent hosts example.com >/dev/null 2>&1 && echo "DNS resolve example.com: ok" || echo "DNS resolve example.com: fail"
  elif command -v host >/dev/null 2>&1; then
    host example.com >/dev/null 2>&1 && echo "DNS resolve example.com: ok" || echo "DNS resolve example.com: fail"
  else
    echo "No resolver tool (getent/host) available for DNS test"
  fi
else
  echo "Skipping connectivity tests (no IPv4 assigned)"
fi

# Warn if NetworkManager is managing the interface (can conflict with manual config)
if command -v nmcli >/dev/null 2>&1; then
  if nmcli dev status 2>/dev/null | awk -v d="$WAN" '$1==d && $3!="unmanaged"' | grep -q .; then
    echo "[WARN] ${WAN} appears managed by NetworkManager. Consider marking it unmanaged:"
    echo "       nmcli dev set ${WAN} managed no"
  fi
fi

# Actionable guidance or strict failure based on flag
if [[ -z "${IPV4:-}" ]]; then
  echo
  echo "No IPv4 address detected on ${WAN}."
  if command -v iw >/dev/null 2>&1 && iw dev "$WAN" info >/dev/null 2>&1; then
    echo "This appears to be a Wi-Fi interface. Connect to your network using one of:"
    echo "  nmcli dev wifi connect \"<SSID>\" password \"<PASS>\" ifname ${WAN}"
    echo "  wpa_cli -i ${WAN} reconfigure"
  else
    echo "This appears to be a wired interface. Check cable or try: dhclient ${WAN}"
  fi
  echo "Logs:"
  echo "  journalctl -u dhcpcd -g ${WAN} -n 50 --no-pager    # if using dhcpcd"
  echo "  journalctl -u NetworkManager -n 50 --no-pager      # if using NetworkManager"
  if [[ "$REQUIRE_IP" -eq 1 ]]; then
    exit 1
  fi
fi

echo "Done Stage 1."
