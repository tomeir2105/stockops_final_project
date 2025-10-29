#!/usr/bin/env bash
######################################
# Created by : Meir
# Purpose : Stage 1 — Deep WAN diagnostics: link, DHCP, IP, route, DNS, connectivity
# Date : 2025-10-29
# Version : 1
######################################

# Exit on errors, unset vars, and failing pipelines
set -euo pipefail

# Load shared helpers and environment (expects utils.sh next to this script)
. "$(dirname "$0")/utils.sh"

# Ensure root for certain network and journal queries
require_root

# Load environment (expects WAN_IFACE if defined)
load_env

# Choose WAN interface from env or default to wlan0
WAN="${WAN_IFACE:-wlan0}"

echo "== Stage 1: WAN check (DHCP on ${WAN}) =="

# Verify the interface exists; fail fast with a helpful message
if ! ip link show "$WAN" >/dev/null 2>&1; then
  echo "[ERR ] Interface '$WAN' not found. Set WAN_IFACE in config/.env or plug the device."
  exit 1
fi

echo "-- Interface presence --"
echo "Detected interface: $WAN"

# Quick link carrier and state for fast triage
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

# Extended interface diagnostics (rfkill, iw info, addresses, routes)
if declare -F iface_diag >/dev/null 2>&1; then
  iface_diag "$WAN" || true
fi

# If this is a wireless device, show current SSID/BSSID/freq if connected
if command -v iw >/dev/null 2>&1; then
  if iw dev "$WAN" info >/dev/null 2>&1; then
    echo "-- Wi-Fi link (iw) --"
    iw dev "$WAN" link || true
  fi
fi

# List all IPv4 addresses on the interface (CIDR)
echo "-- IPv4 addresses --"
IPV4_LIST="$(ip -4 -o addr show dev "$WAN" | awk '{print $4}' || true)"
if [[ -z "${IPV4_LIST}" ]]; then
  echo "(none)"
else
  echo "$IPV4_LIST"
fi

# Extract the first IPv4 for convenience
IPV4_CIDR="$(echo "$IPV4_LIST" | head -n1 || true)"
IPV4="${IPV4_CIDR%%/*}"

# Determine default gateway preferring routes bound to this interface
echo "-- Default route --"
GATEWAY="$(ip route show dev "$WAN" | awk '/^default/ {print $3}' | head -n1 || true)"
[[ -z "${GATEWAY:-}" ]] && GATEWAY="$(ip route | awk '/^default/ {print $3}' | head -n1 || true)"
echo "gateway: ${GATEWAY:-none}"

# DNS servers associated with this interface or global resolvers
echo "-- DNS servers --"
if command -v resolvectl >/dev/null 2>&1; then
  DNS="$(resolvectl dns "$WAN" 2>/dev/null | awk '{for(i=2;i<=NF;i++) printf (i==NF?$i:$i", ")}' || true)"
  [[ -z "${DNS:-}" ]] && DNS="$(resolvectl dns 2>/dev/null | awk 'NR==1{for(i=2;i<=NF;i++) printf (i==NF?$i:$i", ")}')"
else
  DNS="$(awk '/^nameserver/ {print $2}' /etc/resolv.conf 2>/dev/null | paste -sd, - || true)"
fi
echo "dns: ${DNS:-none}"

# Show DHCP client hints if available (dhcpcd or NetworkManager)
echo "-- DHCP client hints --"
if command -v dhcpcd >/dev/null 2>&1; then
  dhcpcd -U "$WAN" 2>/dev/null || echo "dhcpcd query not available"
elif command -v nmcli >/dev/null 2>&1; then
  nmcli -g IP4.ADDRESS,IP4.GATEWAY,IP4.DNS device show "$WAN" 2>/dev/null || echo "nmcli info not available"
else
  echo "No dhcpcd or NetworkManager tools found for DHCP query"
fi

# Connectivity probes (non-fatal). Helps validate route and DNS.
echo "-- Connectivity tests --"
if [[ -n "${IPV4:-}" ]]; then
  ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 && echo "ping 1.1.1.1: ok" || echo "ping 1.1.1.1: fail"
  if command -v getent >/dev/null 2>&1; then
    getent hosts example.com >/dev/null 2>&1 && echo "DNS resolve example.com: ok" || echo "DNS resolve example.com: fail"
  else
    host example.com >/dev/null 2>&1 && echo "DNS resolve example.com: ok" || echo "DNS resolve example.com: fail"
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

# Actionable guidance if IP is missing
if [[ -z "${IPV4:-}" ]]; then
  echo
  echo "No IPv4 address detected on ${WAN}."
  echo "If this is Wi-Fi, connect ${WAN} to your home network before continuing."
  echo "Examples:"
  echo "  nmcli dev wifi connect \"<SSID>\" password \"<PASS>\" ifname ${WAN}    # NetworkManager"
  echo "  wpa_cli -i ${WAN} reconfigure                                         # wpa_supplicant"
  echo "  journalctl -u dhcpcd -g ${WAN} -n 50 --no-pager                        # dhcpcd logs"
fi

echo "Done Stage 1."
