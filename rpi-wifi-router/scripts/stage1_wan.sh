#!/usr/bin/env bash
 pipefail
. "$(dirname "$0")/utils.sh"
require_root
load_env

echo "== Stage 1: WAN check (DHCP on ${WAN_IFACE}) =="
iface_diag "$WAN_IFACE"
echo "If no IPv4 address, connect ${WAN_IFACE} to home Wi-Fi before continuing."
echo "Done Stage 1."

set -euo pipefail
. "$(dirname "$0")/utils.sh"
require_root
load_env

echo "== Stage 1: WAN check (wlan0 DHCP) =="
ip link show "$WAN_IFACE" > /dev/null
echo "Detected $WAN_IFACE."
IPV4=$(ip -4 addr show dev "$WAN_IFACE" | awk '/inet /{print $2}')
echo "$WAN_IFACE IPv4: ${IPV4:-"(none)"}"
echo "Done Stage 1."
