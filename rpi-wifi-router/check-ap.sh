#!/usr/bin/env bash
######################################
# Created by : Meir
# Purpose    : Full diagnostics for k3srouter Wi-Fi AP (hostapd/dnsmasq/NAT/forwarding)
# Date       : 2025-10-30
# Version    : 1
######################################

set -Eeuo pipefail

echo "=== AP DIAGNOSTICS (k3srouter) ==="
date +"Now: %F %T %Z"
echo

# --- System & RF overview -----------------------------------------------------
echo "[SYS] uname / OS:"
uname -a || true
command -v lsb_release >/dev/null && lsb_release -a || true
echo

echo "[RF] rfkill (should not be soft/hard blocked):"
rfkill list || true
echo

# --- Interfaces & addressing --------------------------------------------------
echo "[NET] Interfaces (brief):"
ip -br link || true
echo
echo "[NET] IP addresses (brief):"
ip -br addr || true
echo
echo "[NET] Routes:"
ip route || true
echo

# Try to guess AP iface (default wlan1, fallback to any wlan in AP mode)
AP_IFACE="${AP_IFACE:-wlan1}"
if ! ip -br link show "$AP_IFACE" &>/dev/null; then
  AP_IFACE="$(iw dev 2>/dev/null | awk '/Interface/ {print $2}' | head -n1 || true)"
fi
echo "[NET] Using AP_IFACE='$AP_IFACE'"
echo

echo "[WIFI] iw dev:"
iw dev || true
echo
echo "[WIFI] AP interface detailed info:"
iw dev "$AP_IFACE" info || true
echo
echo "[WIFI] Regulatory + PHY caps (truncated):"
iw reg get || true
iw list 2>/dev/null | sed -n '1,120p' || true
echo

# --- hostapd ------------------------------------------------------------------
echo "[HOSTAPD] service status (summary):"
systemctl is-enabled hostapd 2>/dev/null || true
systemctl is-active hostapd 2>/dev/null || true
systemctl --no-pager --full status hostapd | sed -n '1,80p' || true
echo
echo "[HOSTAPD] last 100 log lines:"
journalctl -u hostapd --no-pager -n 100 || true
echo
echo "[HOSTAPD] config (if present):"
CONF="$(systemctl show -p FragmentPath hostapd 2>/dev/null | cut -d= -f2 || true)"
[ -z "${CONF}" ] && CONF="/etc/hostapd/hostapd.conf"
[ -f "$CONF" ] && { echo "# $CONF"; sed -e 's/^/  /' "$CONF"; } || echo "  (no hostapd.conf found)"
echo

# --- dnsmasq ------------------------------------------------------------------
echo "[DNSMASQ] service status (summary):"
systemctl is-enabled dnsmasq 2>/dev/null || true
systemctl is-active dnsmasq 2>/dev/null || true
systemctl --no-pager --full status dnsmasq | sed -n '1,80p' || true
echo
echo "[DNSMASQ] last 100 log lines:"
journalctl -u dnsmasq --no-pager -n 100 || true
echo
echo "[DNSMASQ] main config & snippets:"
[ -f /etc/dnsmasq.conf ] && { echo "# /etc/dnsmasq.conf"; sed -e 's/^/  /' /etc/dnsmasq.conf; } || echo "  (no /etc/dnsmasq.conf)"
if [ -d /etc/dnsmasq.d ]; then
  for f in /etc/dnsmasq.d/*.conf; do
    [ -f "$f" ] && { echo "# $f"; sed -e 's/^/  /' "$f"; }
  done
fi
echo
echo "[DNSMASQ] leases:"
[ -f /var/lib/misc/dnsmasq.leases ] && cat /var/lib/misc/dnsmasq.leases || echo "  (no leases file)"
echo

# --- Forwarding / NAT ---------------------------------------------------------
echo "[FW] IP forwarding (should be 1):"
sysctl -n net.ipv4.ip_forward || true
sysctl -n net.ipv6.conf.all.forwarding || true
echo

echo "[FW] Detect firewall backend:"
if iptables -V &>/dev/null; then
  echo "  iptables: $(iptables -V)"
fi
if nft --version &>/dev/null; then
  echo "  nft: $(nft --version)"
fi
echo

echo "[FW] NAT rules:"
if command -v nft &>/dev/null && nft list table ip nat &>/dev/null; then
  nft list table ip nat || true
else
  echo "  (nft nat table not present or nft not installed)"
fi
if command -v iptables &>/dev/null; then
  echo "  --- iptables -t nat -S ---"
  iptables -t nat -S || true
  echo "  --- iptables -t filter -S (FORWARD rules) ---"
  iptables -t filter -S | sed -n '/^\-P FORWARD/p;/\-A FORWARD/p' || true
fi
echo

# --- ARP & neighbors ----------------------------------------------------------
echo "[NET] Neighbors on 192.168.50.0/24:"
ip neigh | grep -E '192\.168\.50\.' || echo "  (no neighbors seen)"
echo

# --- Quick sanity checks & hints ----------------------------------------------
echo "[CHECKS] Quick validations:"
FAIL=0

# dnsmasq active?
if ! systemctl is-active --quiet dnsmasq; then
  echo "  !! dnsmasq is NOT active"
  FAIL=$((FAIL+1))
fi

# hostapd active?
if ! systemctl is-active --quiet hostapd; then
  echo "  !! hostapd is NOT active"
  FAIL=$((FAIL+1))
fi

# AP iface has IP?
if ! ip -br addr show "$AP_IFACE" 2>/dev/null | awk '{print $3}' | grep -qE '192\.168\.50\.'; then
  echo "  !! $AP_IFACE has no 192.168.50.x address"
  FAIL=$((FAIL+1))
fi

# forwarding
if [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)" != "1" ]; then
  echo "  !! net.ipv4.ip_forward != 1"
  FAIL=$((FAIL+1))
fi

# NAT (basic check for MASQUERADE)
if command -v iptables &>/dev/null; then
  if ! iptables -t nat -S 2>/dev/null | grep -q MASQUERADE; then
    echo "  !! No MASQUERADE rule found in iptables nat"
    FAIL=$((FAIL+1))
  fi
elif command -v nft &>/dev/null; then
  if ! nft list ruleset 2>/dev/null | grep -qi masquerade; then
    echo "  !! No MASQUERADE rule found in nftables"
    FAIL=$((FAIL+1))
  fi
fi

# rfkill
if rfkill list 2>/dev/null | grep -qi 'Soft blocked: yes'; then
  echo "  !! rfkill soft-block present"
  FAIL=$((FAIL+1))
fi
if rfkill list 2>/dev/null | grep -qi 'Hard blocked: yes'; then
  echo "  !! rfkill hard-block present"
  FAIL=$((FAIL+1))
fi

if [ "$FAIL" -eq 0 ]; then
  echo "  OK: No obvious AP issues detected in quick checks."
else
  echo "  Found $FAIL issue(s) in quick checks. See sections above."
fi

echo
echo "=== END AP DIAGNOSTICS ==="

