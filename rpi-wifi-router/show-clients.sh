#!/usr/bin/env bash
######################################
# Created by : Meir
# Purpose : List connected Wi-Fi clients (MAC, IP, hostname, signal, rates, last-seen)
# Date : 2025-10-29
# Version : 1
######################################

# Fail fast on errors and undefined vars; safer pipelines
set -euo pipefail

# Usage: ./show_clients.sh [iface]
# If no iface is given, defaults to $LAN_IFACE or wlan1
IFACE="${1:-${LAN_IFACE:-wlan1}}"

# Paths used by common setups
LEASES_FILE="/var/lib/misc/dnsmasq.leases"   # dnsmasq leases
NEIGH_CMD="ip neigh show"                     # neighbor table source (ARP/NDP)
IW_CMD="iw"

# Ensure required tools exist
if ! command -v ${IW_CMD} >/dev/null 2>&1; then
  echo "ERROR: 'iw' is required. Install 'iw' package and retry."
  exit 1
fi
if ! command -v ip >/dev/null 2>&1; then
  echo "ERROR: 'iproute2' is required."
  exit 1
fi

# Verify the interface exists
if ! ip link show "$IFACE" >/dev/null 2>&1; then
  echo "ERROR: Interface '$IFACE' not found."
  exit 1
fi

# Read station dump (associated clients)
# 'iw dev <iface> station dump' prints blocks per station with fields like:
# Station <MAC> (on <iface>)
#     signal: -45 dBm
#     rx bitrate: 300.0 MBit/s
#     tx bitrate: 173.3 MBit/s
#     connected time: 1234 seconds
#     inactive time: 40 ms
STATION_DUMP="$(${IW_CMD} dev "$IFACE" station dump 2>/dev/null || true)"

# If nothing is associated, exit gracefully
if [[ -z "${STATION_DUMP}" ]]; then
  echo "No stations associated on ${IFACE}."
  exit 0
fi

# Build maps:
# mac -> signal (dBm)
# mac -> rxrate (MBit/s)
# mac -> txrate (MBit/s)
# mac -> inactive (ms)
# mac -> last_seen (approx; derived from inactive time)
declare -A SIG RX TX INACTIVE

# Parse iw output
# Notes:
# - signal line: "signal: -45 [-48, -47] dBm" or "signal: -45 dBm"
# - rx/tx bitrate lines: "rx bitrate: 300.0 MBit/s", optional "VHT-MCS 5" etc. We grab first number.
current_mac=""
while IFS= read -r line; do
  if [[ "$line" =~ ^Station[[:space:]]+([0-9a-f:]{17})[[:space:]] ]]; then
    current_mac="${BASH_REMATCH[1],,}"   # normalize to lowercase
    # initialize defaults
    SIG["$current_mac"]="?"
    RX["$current_mac"]="?"
    TX["$current_mac"]="?"
    INACTIVE["$current_mac"]="?"
  elif [[ -n "${current_mac}" && "$line" =~ signal:[[:space:]]*(-?[0-9]+) ]]; then
    SIG["$current_mac"]="${BASH_REMATCH[1]}"
  elif [[ -n "${current_mac}" && "$line" =~ rx[[:space:]]bitrate:[[:space:]]*([0-9.]+) ]]; then
    RX["$current_mac"]="${BASH_REMATCH[1]}"
  elif [[ -n "${current_mac}" && "$line" =~ tx[[:space:]]bitrate:[[:space:]]*([0-9.]+) ]]; then
    TX["$current_mac"]="${BASH_REMATCH[1]}"
  elif [[ -n "${current_mac}" && "$line" =~ inactive[[:space:]]time:[[:space:]]*([0-9]+)[[:space:]]*ms ]]; then
    INACTIVE["$current_mac"]="${BASH_REMATCH[1]}"
  fi
done <<< "${STATION_DUMP}"

# Map MAC -> (IP, HOSTNAME) using dnsmasq leases if available, otherwise ARP/neighbor table
declare -A IPMAP HOSTMAP
if [[ -r "$LEASES_FILE" ]]; then
  # dnsmasq leases format: <expiry> <mac> <ip> <hostname> <client-id>
  while read -r exp mac ip host _rest; do
    [[ -z "${mac:-}" || -z "${ip:-}" ]] && continue
    mac="${mac,,}"
    IPMAP["$mac"]="$ip"
    # Use "-" if hostname blank or "*"
    if [[ -n "${host:-}" && "$host" != "*" ]]; then
      HOSTMAP["$mac"]="$host"
    fi
  done < "$LEASES_FILE"
fi

# Fill missing IPs from neighbor table
# Typical lines: "192.168.50.123 dev wlan1 lladdr aa:bb:cc:dd:ee:ff REACHABLE"
while read -r nline; do
  # Extract ip, dev, mac
  ipaddr="$(awk '{print $1}' <<<"$nline")"
  devname="$(awk '/ dev /{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1)}}' <<<"$nline")"
  macaddr="$(awk '/ lladdr /{for(i=1;i<=NF;i++) if($i=="lladdr"){print $(i+1)}}' <<<"$nline")"
  [[ -z "${ipaddr:-}" || -z "${devname:-}" || -z "${macaddr:-}" ]] && continue
  [[ "$devname" != "$IFACE" ]] && continue
  macaddr="${macaddr,,}"
  if [[ -z "${IPMAP[$macaddr]:-}" ]]; then
    IPMAP["$macaddr"]="$ipaddr"
  fi
done < <(${NEIGH_CMD} 2>/dev/null || true)

# Prepare header
printf "%-17s  %-15s  %-24s  %7s  %7s  %7s  %10s\n" "MAC" "IP" "HOSTNAME" "SIGNAL" "RX(Mb)" "TX(Mb)" "INACTIVE(ms)"
printf "%-17s  %-15s  %-24s  %7s  %7s  %7s  %10s\n" "-----------------" "---------------" "------------------------" "-------" "-------" "-------" "----------"

# Emit rows in the order seen in station dump
# Extract MACs again in order from STATION_DUMP
while read -r line; do
  if [[ "$line" =~ ^Station[[:space:]]+([0-9a-f:]{17})[[:space:]] ]]; then
    mac="${BASH_REMATCH[1],,}"
    ip="${IPMAP[$mac]:-"-"}"
    host="${HOSTMAP[$mac]:-"-"}"
    sig="${SIG[$mac]:-"?"}"
    rx="${RX[$mac]:-"?"}"
    tx="${TX[$mac]:-"?"}"
    ina="${INACTIVE[$mac]:-"?"}"
    printf "%-17s  %-15s  %-24s  %7s  %7s  %7s  %10s\n" "$mac" "$ip" "$host" "$sig" "$rx" "$tx" "$ina"
  fi
done <<< "${STATION_DUMP}"

# Notes for admin:
# - RX/TX rates are the latest reported link bitrates (approximate).
# - INACTIVE is time since last data frame from the station (ms).
# - IP/hostname resolution prefers dnsmasq leases, then neighbor table.
# - If you don't see IPs, ensure clients obtained DHCP from dnsmasq or have entries in 'ip neigh'.

