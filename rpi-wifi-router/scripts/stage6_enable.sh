#!/usr/bin/env bash
######################################
# Created by : Meir
# Purpose : Stage 6 — Permanently ensure radios are unblocked and enable/restart AP services on boot
# Date : 2025-10-29
# Version : 1
######################################

# Fail on errors, undefined variables, and pipeline failures
set -euo pipefail

# Load shared helpers and environment (expects utils.sh next to this script)
. "$(dirname "$0")/utils.sh"

# Ensure root privileges for systemctl operations
require_root

# Load environment for consistency, even if this stage uses no vars directly
load_env

echo "== Stage 6: Enable services on boot (permanent RF-unblock) =="

# ---------------------------------------------------------------------------
# Permanently prevent RF-kill soft blocks from being restored at boot
# ---------------------------------------------------------------------------
if ! command -v rfkill >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y rfkill
fi

systemctl stop systemd-rfkill.service systemd-rfkill.socket || true
rm -f /var/lib/systemd/rfkill/* || true
rfkill unblock all || true
systemctl mask systemd-rfkill.service systemd-rfkill.socket || true

rfkill list || true

# ---------------------------------------------------------------------------
# Enable core services to start on boot
# ---------------------------------------------------------------------------
# dhcpcd service name differs; try both
systemctl enable dhcpcd || systemctl enable dhcpcd5 || true
systemctl enable hostapd

# ---------------------------------------------------------------------------
# dnsmasq — preflight + error handling (only for actual errors)
# ---------------------------------------------------------------------------

# 1) Ensure dnsmasq is installed (some images don’t have it)
if ! command -v dnsmasq >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y dnsmasq
fi

# 2) Make sure leases dir exists (dnsmasq fails if missing)
LEASES_FILE="$(grep -E '^\s*dhcp-leasefile=' /etc/dnsmasq.conf /etc/dnsmasq.d/* 2>/dev/null | tail -n1 | cut -d= -f2 || true)"
if [[ -z "${LEASES_FILE}" ]]; then
  LEASES_FILE="/var/lib/misc/dnsmasq.leases"
fi
mkdir -p "$(dirname "${LEASES_FILE}")"
chmod 0755 "$(dirname "${LEASES_FILE}")"

# 3) Remove backup *.conf.bak* files that dnsmasq parses and that can cause duplicate entries (real start error)
find /etc/dnsmasq.d -maxdepth 1 -type f -name '*.conf.bak*' -print -delete || true

# 4) Detect port-53 conflict (e.g., systemd-resolved) and stop it if it collides
if ss -ulpn | grep -qE ':\s*53\b'; then
  if ss -ulpn | grep -q 'systemd-resolved'; then
    echo "Port 53 in use by systemd-resolved — stopping to allow dnsmasq to bind (error handling)."
    systemctl stop systemd-resolved || true
    systemctl disable systemd-resolved || true
    # On some distros resolv.conf is a stub; replace with real resolver if needed
    if [[ -L /etc/resolv.conf ]] && readlink /etc/resolv.conf | grep -q 'stub-resolv.conf'; then
      rm -f /etc/resolv.conf
      printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' >/etc/resolv.conf
    fi
  else
    echo "Another process is using UDP/53; dnsmasq cannot start. See below:"
    ss -ulpn | grep -E ':\s*53\b' || true
    exit 1
  fi
fi

# 5) Syntax test the dnsmasq config — this prints exact error location if invalid
if ! dnsmasq --test; then
  echo "dnsmasq configuration test failed. Inspect /etc/dnsmasq.conf and /etc/dnsmasq.d/*.conf" >&2
  exit 1
fi

# 6) Enable dnsmasq now that errors are cleared
systemctl enable dnsmasq

# ---------------------------------------------------------------------------
# Restart now in safe order
# ---------------------------------------------------------------------------
systemctl restart dhcpcd || systemctl restart dhcpcd5 || true
systemctl restart hostapd
systemctl restart dnsmasq

echo "All services enabled and started. RF-kill permanently disabled (systemd-rfkill masked). Reboot recommended."

