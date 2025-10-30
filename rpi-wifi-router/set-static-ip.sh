#!/usr/bin/env bash
######################################
# Created by : Meir
# Purpose : Add/ensure static DHCP leases for k3s1..k3s3 on the router (dnsmasq) — auto-fill MACs from show-clients.sh
# Date : 2025-10-29
# Version : 1
######################################

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Desired static IPs -------------------------------------------------------
declare -A HOSTS=(
  [k3s1]="192.168.50.101"
  [k3s2]="192.168.50.102"
  [k3s3]="192.168.50.103"
)

# ---- Paths --------------------------------------------------------------------
DNSMASQ_DIR="/etc/dnsmasq.d"
STATIC_FILE="${DNSMASQ_DIR}/static_leases.conf"
LEASES_FILE="/var/lib/misc/dnsmasq.leases"
LAN_IFACE="${LAN_IFACE:-wlan1}"

# ---- Helpers ------------------------------------------------------------------
need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1"; exit 1; }; }
is_mac() { [[ "${1,,}" =~ ^[0-9a-f]{2}(:[0-9a-f]{2}){5}$ ]] ; }

mac_from_neigh() {
  local ip="$1"
  ip neigh show to "$ip" 2>/dev/null | awk '/lladdr/ {print tolower($5); exit}'
}
mac_from_leases() {
  local ip="$1"
  [[ -r "$LEASES_FILE" ]] || return 0
  awk -v ip="$ip" '($3==ip){print tolower($2); exit}' "$LEASES_FILE"
}
mac_from_arp() {
  local ip="$1"
  command -v arp >/dev/null 2>&1 || return 0
  arp -an 2>/dev/null | awk -v ip="($ip)" '($2 ~ ip){print tolower($4); exit}'
}
resolve_mac_by_ip_chain() {
  local ip="$1" mac=""
  mac="$(mac_from_neigh "$ip")" || true
  [[ -n "$mac" ]] || mac="$(mac_from_leases "$ip")" || true
  [[ -n "$mac" ]] || mac="$(mac_from_arp "$ip")" || true
  echo -n "$mac"
}

ensure_dnsmasq_dir() { mkdir -p "$DNSMASQ_DIR"; chmod 0755 "$DNSMASQ_DIR"; }
ensure_static_file() {
  if [[ ! -e "$STATIC_FILE" ]]; then
    umask 022
    cat >"$STATIC_FILE" <<'EOF'
# Static DHCP leases managed by script.
# Format: dhcp-host=<MAC>,<HOSTNAME>,<IP>,infinite
EOF
  fi
}
backup_file() { local src="$1"; cp -a "$src" "${src}.bak.$(date +%Y%m%d-%H%M%S)"; }
remove_old_lines() { local host="$1" ip="$2"; sed -i -E "/^dhcp-host=.*\b(${host}|${ip})\b.*$/d" "$STATIC_FILE"; }
append_line() { local mac="$1" host="$2" ip="$3"; echo "dhcp-host=${mac},${host},${ip},infinite" >>"$STATIC_FILE"; }
dnsmasq_test() { dnsmasq --test; }
dnsmasq_reload() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl reload dnsmasq || systemctl restart dnsmasq
  else
    service dnsmasq reload || service dnsmasq restart
  fi
}

# ---- Build hostname->MAC map from show-clients.sh (no subshell loss) ----------
declare -A MACMAP=()

build_macmap_from_show() {
  local output="$1"
  # Use process substitution so the while loop runs in THIS shell (keeps MACMAP)
  while read -r host mac; do
    [[ -n "$host" && -n "$mac" ]] || continue
    [[ "$host" != "-" ]] || continue
    if [[ "$mac" =~ ^([0-9a-f]{2}:){5}[0-9a-f]{2}$ ]]; then
      MACMAP["$host"]="$mac"
    fi
  done < <(
    awk '
      BEGIN{IGNORECASE=1}
      /^[[:space:]]*$/ {next}
      /^MAC[[:space:]]+IP[[:space:]]+HOSTNAME/ {next}
      /^-[-]+/ {next}
      {
        mac=$1; ip=$2; host=$3;
        # Normalize to lowercase for keys and values
        for(i=1;i<=NF;i++){;}
        printf "%s %s\n", tolower(host), tolower(mac);
      }
    ' <<<"$output"
  )
}

# ---- Preconditions ------------------------------------------------------------
need_cmd awk; need_cmd sed; need_cmd ip; need_cmd dnsmasq

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo)."
  exit 1
fi

ensure_dnsmasq_dir
ensure_static_file
backup_file "$STATIC_FILE"

# ---- Run show-clients and capture output --------------------------------------
SHOW_OUT=""
if [[ -x "${SCRIPT_DIR}/show-clients.sh" ]]; then
  SHOW_OUT="$("${SCRIPT_DIR}/show-clients.sh" || true)"
  echo "$SHOW_OUT"
elif [[ -f "${SCRIPT_DIR}/show-clients.sh" ]]; then
  SHOW_OUT="$(bash "${SCRIPT_DIR}/show-clients.sh" || true)"
  echo "$SHOW_OUT"
else
  echo "Note: ${SCRIPT_DIR}/show-clients.sh not found; continuing without it."
fi

# Populate MACMAP from the captured output
[[ -n "$SHOW_OUT" ]] && build_macmap_from_show "$SHOW_OUT"

# ---- Resolve and apply --------------------------------------------------------
declare -A RESOLVED_MACS=()

for host in k3s1 k3s2 k3s3; do
  target_ip="${HOSTS[$host]}"
  lc_host="${host,,}"

  # 1) Prefer MAC from show-clients by hostname (handles K3S1/K3S2/K3S3)
  mac="${MACMAP[$lc_host]:-}"

  # 2) If still empty, try by the target IP (in case hostname missing)
  [[ -n "$mac" ]] || mac="$(resolve_mac_by_ip_chain "$target_ip")"

  # 3) If still empty, try any MAC seen for a host that equals host in uppercase (defensive)
  [[ -n "$mac" ]] || mac="${MACMAP[${host^^}]:-}"

  if ! is_mac "${mac:-}"; then
    echo "ERROR: Could not auto-detect MAC for ${host} (${target_ip})."
    echo "Please ensure it appears in show-clients output, then re-run."
    exit 1
  fi

  RESOLVED_MACS["$host"]="$mac"
done

# Write entries
for host in k3s1 k3s2 k3s3; do
  ip_addr="${HOSTS[$host]}"
  mac="${RESOLVED_MACS[$host]}"

  remove_old_lines "$host" "$ip_addr"
  append_line "$mac" "$host" "$ip_addr"
done

# ---- Validate and reload ------------------------------------------------------
if dnsmasq_test; then
  dnsmasq_reload
  echo "Static leases updated and dnsmasq reloaded successfully."
  echo "File: $STATIC_FILE"
else
  echo "dnsmasq --test failed. Restoring previous file."
  mv -f "$STATIC_FILE".bak.* "$STATIC_FILE" 2>/dev/null || true
  exit 1
fi

