# Raspberry Pi Wi‑Fi Router Installer

## Overview
This project automates the setup of a Raspberry Pi as a full Wi‑Fi router / access point running Debian 13 (trixie).  
It configures the network interfaces, access point, DHCP/DNS server, NAT, and persistence — all through staged, idempotent Bash scripts.

## Features
- Modular staged installer (0 → 6)
- Automatic OS and kernel validation
- Dynamic LAN / WAN configuration
- Hostapd + Dnsmasq configuration and verification
- NAT / IP forwarding setup
- Persistent iptables via netfilter‑persistent
- Health and troubleshooting diagnostics (ports, logs, connectivity)
- Secure AP credentials and country‑specific regulatory domain handling

## Directory Layout
```
scripts/
 ├── stage0_prep.sh        # install base pkgs and prep system
 ├── stage1_wan.sh         # verify WAN interface and DHCP
 ├── stage2_lan.sh         # configure LAN with static IP
 ├── stage3_ap.sh          # configure hostapd + dnsmasq
 ├── stage4_nat.sh         # enable routing and NAT
 ├── stage5_health.sh      # unified health + troubleshooting
 ├── stage6_finalize.sh    # enable services and persist rules
 └── utils.sh              # shared helper functions
config/
 ├── hostapd.conf.tmpl
 ├── dnsmasq.conf.tmpl
 ├── iptables.rules.v4.tmpl
 ├── sysctl_router.conf
 └── .env                  # user configuration
```

## Quick Start
```bash
git clone https://github.com/tomeir2105/stockops_final_project.git
cd stockops_final_project/router_installer

# make scripts executable
chmod +x scripts/*.sh

# run full staged setup
sudo ./scripts/run_all.sh
```

## Requirements
- Raspberry Pi 4 / 5 or compatible Debian 13 system
- Internet connectivity on the WAN interface
- 2 network interfaces (one WAN, one LAN/AP)
- sudo / root privileges

## Configuration
All parameters are defined in `config/.env`, including:
```
WAN_IFACE=wlan0
LAN_IFACE=wlan1
COUNTRY_CODE=IL
LAN_CIDR=192.168.50.1/24
AP_SSID=MyRouter
AP_PASSPHRASE=securepassword
```
Templates in `config/*.tmpl` use these variables automatically.

## Usage
Each stage can be executed independently:
```bash
sudo ./scripts/stage0_prep.sh
sudo ./scripts/stage1_wan.sh
...
sudo ./scripts/stage6_finalize.sh
```

## Troubleshooting
Run health diagnostics anytime:
```bash
sudo ./scripts/stage5_health.sh
```
It prints service status, active ports, NAT rules, DHCP leases, and last logs.

## License
MIT License © 2025 Meir

---
*Created by Meir — Raspberry Pi Router Automation Project*
