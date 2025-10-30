#!/usr/bin/env bash
######################################
# Created by : Meir
# Purpose : Create and enable a systemd service to automatically run 'rfkill unblock all' on boot (fix RF-kill blocking wlan0/wlan1/BT)
# Date : 2025-10-29
# Version : 1
######################################

set -euo pipefail

SERVICE_PATH="/etc/systemd/system/rfkill-unblock.service"

# Require root
if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

# Ensure rfkill exists
if ! command -v rfkill >/dev/null 2>&1; then
  echo "rfkill not found. Install it: apt-get update && apt-get install -y rfkill" >&2
  exit 1
fi

# Create the systemd unit
cat > "${SERVICE_PATH}" <<'EOF'
######################################
# Created by : Meir
# Purpose : Automatically unblocks Wi-Fi and Bluetooth radios on boot (fix RF-kill issues)
# Date : 2025-10-29
# Version : 1
######################################
[Unit]
Description=Unblock Wi-Fi and Bluetooth (rfkill)
DefaultDependencies=no
Before=network-pre.target hostapd.service
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/rfkill unblock all
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Reload, enable, and start
systemctl daemon-reload
systemctl enable rfkill-unblock.service
systemctl start rfkill-unblock.service

# Verify current state (not an improvement; confirms success)
rfkill list

