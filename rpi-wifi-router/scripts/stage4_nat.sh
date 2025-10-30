#!/usr/bin/env bash
######################################
# Created by : Meir
# Purpose : Stage 4 — Configure IPv4 forwarding, NAT, and persist iptables rules (with auto/user iface selection)
# Date : 2025-10-30
# Version : 2
######################################

set -euo pipefail
. "$(dirname "$0")/utils.sh"
require_root
load_env

echo "== Stage 4: Routing & NAT =="

# ---- Interface selection ------------------------------------------------------
# Allow explicit user choice via env: WAN_IFACE, LAN_IFACE. Support 'auto'.
WAN_IFACE="${WAN_IFACE:-auto}"
LAN_IFACE="${LAN_IFACE:-auto}"

if [[ "${WAN_IFACE}" == "auto" ]]; then
  # prefer interface used to reach internet
  WAN_IFACE="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="dev"){print $(i+1); exit}}' || true)"
  [[ -z "${WAN_IFACE}" ]] && for c in eth0 wlan0; do ip -o link show "$c" >/dev/null 2>&1 && { WAN_IFACE="$c"; break; }; done
fi

if [[ "${LAN_IFACE}" == "auto" ]]; then
  # prefer wlan1, else first wlan*
  if ip -o link show wlan1 >/dev/null 2>&1; then
    LAN_IFACE="wlan1"
  else
    LAN_IFACE="$(ip -o link show | awk -F': ' '$2 ~ /^wlan[0-9]+$/ {print $2; exit}' || true)"
  fi
fi

[[ -z "${WAN_IFACE}" ]] && { echo "[error] Could not determine WAN_IFACE. Set WAN_IFACE=eth0|wlan0"; exit 1; }
[[ -z "${LAN_IFACE}" ]] && { echo "[error] Could not determine LAN_IFACE. Set LAN_IFACE=wlanX"; exit 1; }

# LAN_SUBNET may come from env; if missing, derive from LAN_IFACE address
LAN_SUBNET="${LAN_SUBNET:-}"
if [[ -z "${LAN_SUBNET}" ]]; then
  LAN_SUBNET="$(ip -o -4 addr show "${LAN_IFACE}" | awk '{print $4}' | sed 's|/[0-9]\{1,2\}$||' | head -n1 || true)"
  [[ -z "${LAN_SUBNET}" ]] && LAN_SUBNET="192.168.50.0"   # fallback
fi

echo "[detect] WAN_IFACE=${WAN_IFACE}"
echo "[detect] LAN_IFACE=${LAN_IFACE}"
echo "[detect] LAN_SUBNET=${LAN_SUBNET}"

# Dry-run mode: only print detection and exit (no changes)
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "(dry-run) no iptables/sysctl changes"
  exit 0
fi

# ---- Sysctl (persist + runtime) ----------------------------------------------
render "${ROOT_DIR}/config/sysctl_router.conf" "/etc/sysctl.d/99-rpi-router.conf"
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
sysctl --system >/dev/null

# ---- iptables apply + persist -------------------------------------------------
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
export WAN_IFACE LAN_IFACE LAN_SUBNET
render "${ROOT_DIR}/config/iptables.rules.v4.tmpl" "$TMP"
iptables-restore < "$TMP"

mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4

echo "NAT set: ${LAN_SUBNET}/24 -> ${WAN_IFACE}"
echo "Done Stage 4."

