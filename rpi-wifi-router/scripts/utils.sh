#!/usr/bin/env bash
######################################
# Created by : Meir
# Purpose : Shared helpers for rpi-wifi-router; safe-by-default Bash utilities used by stage scripts
# Date : 2025-10-29
# Version : 1
######################################

# Fail fast on errors, treat unset vars as errors, and trap ERR with -E
set -Eeuo pipefail

# --- Paths --------------------------------------------------------------------
# Resolve repository root (one level above this file) and the config directory
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${ROOT_DIR}/config"

# --- Logging ------------------------------------------------------------------
# Simple colorized log helpers; write errors to stderr
log_info()  { printf "\e[1;34m[INFO]\e[0m %s\n"  "$*"; }
log_warn()  { printf "\e[1;33m[WARN]\e[0m %s\n"  "$*"; }
log_error() { printf "\e[1;31m[ERR ]\e[0m %s\n"  "$*" 1>&2; }

# --- Safety -------------------------------------------------------------------
# Ensure the script is running as root; exit with a clear message if not
require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)."
    exit 1
  fi
}

# --- Env validation -----------------------------------------------------------
# Required variables that must be present in config/.env
_required_vars=(
  WAN_IFACE
  LAN_IFACE
  COUNTRY_CODE

  LAN_CIDR
  LAN_IP
  LAN_SUBNET
  LAN_NETMASK
  LAN_BROADCAST

  DHCP_RANGE_START
  DHCP_RANGE_END
  DHCP_LEASE

  AP_SSID
  AP_PASSPHRASE
  AP_CHANNEL
  AP_HW_MODE
  AP_WPA
  AP_WPA_KEY_MGMT
  AP_WPA_PAIRWISE
  AP_RSN_PAIRWISE
)

# Validate presence of required variables; print missing ones and exit
_validate_required_vars() {
  local missing=()
  for v in "${_required_vars[@]}"; do
    if [[ -z "${!v-}" ]]; then
      missing+=("$v")
    fi
  done
  if (( ${#missing[@]} )); then
    log_error "Missing required variables in ${CONFIG_DIR}/.env:"
    for v in "${missing[@]}"; do echo "  - $v"; done
    echo
    echo "Please edit ${CONFIG_DIR}/.env and set the variables above, then re-run."
    exit 1
  fi
}

# --- Environment loader (robust) ---------------------------------------------
# Load key=value pairs from config/.env while ignoring comments and blank lines
load_env() {
  set -a
  local ENV_SRC="${CONFIG_DIR}/.env"
  if [[ -f "$ENV_SRC" ]]; then
    while IFS= read -r raw || [ -n "$raw" ]; do
      local line="${raw%$'\r'}"   # strip CR if present
      [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
      if [[ "$line" =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*= ]]; then
        eval "export ${line}"
      fi
    done < "$ENV_SRC"
  else
    log_error "Config file not found: ${ENV_SRC}"
    exit 1
  fi
  set +a
  _validate_required_vars
}

# --- Package helpers ----------------------------------------------------------
# Install missing packages only; idempotent across runs
ensure_pkg() {
  local missing=()
  for pkg in "$@"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
      missing+=("$pkg")
    fi
  done
  if ((${#missing[@]})); then
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
  fi
}

# --- Template rendering -------------------------------------------------------
# Render a template with envsubst into destination path atomically
render_template() {
  local src="$1"
  local dst="$2"
  if [[ ! -f "$src" ]]; then
    log_error "Template not found: $src"
    return 1
  fi
  mkdir -p "$(dirname "$dst")"
  local tmp
  tmp="$(mktemp)"
  ( envsubst <"$src" ) >"$tmp" || { rm -f "$tmp"; return 1; }
  install -m 0644 "$tmp" "$dst"
  rm -f "$tmp"
  log_info "Rendered $(basename "$src") -> $dst"
}

# --- Compatibility wrappers (for existing stage scripts) ----------------------
# Keep these names for legacy calls in stage scripts
ensure_iface_up() { wait_iface_up "$@"; }
render()          { render_template "$@"; }

# --- Network helpers ----------------------------------------------------------
# Print concise link, address, and wireless info for an interface
print_link_state() {
  local iface="$1"
  echo "---- Link state: ${iface} ----"
  ip -d link show "$iface" || true
  ip -4 addr show "$iface" || true
  if command -v iw >/dev/null 2>&1; then
    iw dev "$iface" info 2>/dev/null || true
  fi
}

# Wait for interface state UP with retries; print diagnostics if it never comes up
wait_iface_up() {
  local iface="$1"
  local attempts="${2:-15}"
  local delay="${3:-0.5}"
  local i
  for ((i=1; i<=attempts; i++)); do
    if ip link show "$iface" | grep -q "state UP"; then
      return 0
    fi
    sleep "$delay"
  done
  log_warn "${iface} did not report state UP after ${attempts} attempts."
  print_link_state "$iface"
  return 1
}

# Determine current default route device for internet connectivity
current_wan_dev() {
  ip route get 1.1.1.1 2>/dev/null | awk '{
    for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}
  }'
}

# Stop wpa_supplicant on a specific interface to free it for AP mode
safe_stop_wpa_for_iface() {
  local iface="$1"
  if systemctl list-units | grep -q "wpa_supplicant@${iface}.service"; then
    systemctl stop "wpa_supplicant@${iface}.service" || true
  else
    command -v wpa_cli >/dev/null 2>&1 && wpa_cli -i "$iface" terminate 2>/dev/null || true
    pkill -f "wpa_supplicant.*-i${iface}" 2>/dev/null || true
  fi
}

# Ensure a wireless interface is free from client-mode processes and not the active WAN path
ensure_iface_free_for_ap() {
  local iface="$1"
  local gwdev
  gwdev="$(current_wan_dev || true)"
  if [[ -n "$gwdev" && "$gwdev" == "$iface" ]]; then
    log_error "Refusing to modify $iface because it is the active WAN path ($gwdev)."
    return 1
  fi
  safe_stop_wpa_for_iface "$iface"
  if command -v iw >/dev/null 2>&1; then
    while read -r ifn; do
      [[ "$ifn" == "p2p-dev-${iface}" ]] && iw dev "$ifn" del 2>/dev/null || true
    done < <(iw dev | awk '/Interface/{print $2}')
  fi
  ip addr flush dev "$iface" 2>/dev/null || true
  ip link set "$iface" down 2>/dev/null || true
  ip link set "$iface" up 2>/dev/null || true
  return 0
}

# Apply regulatory domain for Wi-Fi if iw is available
apply_regdom() {
  local cc="$1"
  if [[ -n "$cc" ]] && command -v iw >/dev/null 2>&1; then
    iw reg set "$cc" 2>/dev/null || true
  fi
}

# --- NetworkManager integration ----------------------------------------------
# Mark an interface unmanaged by NetworkManager (safe no-op if nmcli missing)
nm_mark_unmanaged() {
  local iface="$1"
  if command -v nmcli >/dev/null 2>&1; then
    nmcli dev set "$iface" managed no 2>/dev/null || true
    local d="/etc/NetworkManager/conf.d"
    local f="${d}/99-unmanaged-${iface}.conf"
    mkdir -p "$d"
    cat >"$f" <<EOF
[keyfile]
unmanaged-devices=interface-name:${iface}
EOF
    systemctl is-active --quiet NetworkManager && systemctl reload NetworkManager || true
  fi
  return 0
}

# --- Diagnostics --------------------------------------------------------------
# Broad interface diagnostics: rfkill, link, iw info/link, routes, and recent dmesg
iface_diag() {
  local iface="$1"
  echo "== diag:${iface} =="
  echo "-- rfkill --"
  command -v rfkill >/dev/null 2>&1 && rfkill list || echo "rfkill not installed"
  echo "-- link --"
  ip -d link show "$iface" || true
  ip -4 addr show "$iface" || true
  echo "-- iw info --"
  command -v iw >/dev/null 2>&1 && iw dev "$iface" info || echo "iw not installed"
  echo "-- iw link --"
  command -v iw >/dev/null 2>&1 && iw dev "$iface" link || true
  echo "-- routes touching ${iface} --"
  ip route show dev "$iface" || true
  echo "-- dmesg (last 80 lines filtered for ${iface}/wlan) --"
  # Replaced deprecated egrep with grep -E
  dmesg | grep -Ei "(firmware|error|warn|wlan|${iface})" | tail -n 80 || true
  return 0
}

# --- Service helpers ----------------------------------------------------------
# Restart only if enabled or currently active to avoid noisy errors
restart_service_if_active() {
  local svc="$1"
  if systemctl is-enabled --quiet "$svc" 2>/dev/null || systemctl is-active --quiet "$svc"; then
    systemctl restart "$svc" || true
  fi
}
stop_service_if_running() { local svc="$1"; systemctl stop "$svc" 2>/dev/null || true; }
start_service()           { local svc="$1"; systemctl start "$svc" 2>/dev/null || true; }
enable_service()          { local svc="$1"; systemctl enable "$svc" 2>/dev/null || true; }

# Start a systemd service and show concise status; print logs on failure
start_service_and_verify() {
  local svc="$1"
  systemctl daemon-reload || true
  systemctl start "$svc" || true
  sleep 1
  if ! systemctl is-active --quiet "$svc"; then
    log_error "Failed to start service: $svc"
    systemctl --no-pager --full status "$svc" | sed -n '1,40p' || true
    journalctl -xeu "$svc" --no-pager -n 80 || true
    return 1
  fi
  systemctl --no-pager --full status "$svc" | sed -n '1,15p' || true
  return 0
}

# --- Port checks (DNS/DHCP) ---------------------------------------------------
# Quick views into listening sockets for common DNS/DHCP ports
check_dns_dhcp_ports() {
  echo "UDP/53:"; ss -ulpn 2>/dev/null | grep -E '(:53\s)' || true
  echo "TCP/53:"; ss -ltnp 2>/dev/null | grep -E '(:53\s)' || true
  echo "UDP/67:"; ss -ulpn 2>/dev/null | grep -E '(:67\s)' || true
  echo "UDP/68:"; ss -ulpn 2>/dev/null | grep -E '(:68\s)' || true
}

# --- Port helpers (used by stage scripts) -------------------------------------
# Return 0 if a port is in use, 1 if free. Usage: port_in_use udp 53
port_in_use() {
  local proto="${1,,}"
  local port="$2"
  case "$proto" in
    tcp)
      ss -ltnp 2>/dev/null | awk -v p=":$port" '$4 ~ p' | grep -q ":" ;;
    udp)
      ss -ulpn 2>/dev/null | awk -v p=":$port" '$5 ~ p' | grep -q ":" ;;
    *)
      log_error "port_in_use: unknown protocol '$1' (use tcp|udp)"
      return 2 ;;
  esac
}

# --- Capability checks --------------------------------------------------------
# Quick check if the wireless driver supports AP mode
check_ap_capability() {
  if ! command -v iw >/dev/null 2>&1; then
    echo "iw not installed"
    return 2
  fi
  if iw list | awk '/Supported interface modes:/{flag=1;next}/^$/{flag=0}flag' | grep -q '\* AP'; then
    echo "AP mode supported"
    return 0
  else
    echo "AP mode NOT supported by driver/device"
    return 1
  fi
}
