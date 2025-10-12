#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/utils.sh"
require_root
load_env

echo "== Stage 3: Configure hostapd + dnsmasq =="
stop_service_if_running "hostapd"
stop_service_if_running "dnsmasq"

# Make sure the interface & IP exist before dnsmasq binds
ip link set "$LAN_IFACE" up || true
ip addr replace "${LAN_CIDR}" dev "$LAN_IFACE" || true

# Render configs
render "${ROOT_DIR}/config/hostapd.conf.tmpl" "/etc/hostapd/hostapd.conf"
if [[ -f /etc/default/hostapd ]]; then
  sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
  # Silence empty DAEMON_OPTS warning
  grep -q '^DAEMON_OPTS=' /etc/default/hostapd || echo 'DAEMON_OPTS=""' >> /etc/default/hostapd
fi

render "${ROOT_DIR}/config/dnsmasq.conf.tmpl" "/etc/dnsmasq.d/wlan1.conf"
echo 'conf-dir=/etc/dnsmasq.d,*.conf' > /etc/dnsmasq.conf

systemctl daemon-reload

# Port checks (informational)
echo "UDP/53:"; port_in_use udp 53 || echo "(free)"
echo "TCP/53:"; port_in_use tcp 53 || echo "(free)"
echo "UDP/67:"; port_in_use udp 67 || echo "(free)"

# Start in safe order
start_service_and_verify "dnsmasq"
start_service_and_verify "hostapd"

echo "Done Stage 3."

