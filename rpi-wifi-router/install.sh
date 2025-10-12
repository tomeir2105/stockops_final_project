#!/usr/bin/env bash
set -euo pipefail

# --- OS verification ---
OS_ID="$(. /etc/os-release && echo "$ID")"
OS_VERSION_ID="$(. /etc/os-release && echo "$VERSION_ID")"
KERNEL="$(uname -a)"

if [[ "$OS_ID" != "debian" || "$OS_VERSION_ID" != "13" ]]; then
  echo "[ERR ] This installer is tested only on Debian 13 (trixie)."
  echo "       Detected: ID=$OS_ID VERSION_ID=$OS_VERSION_ID"
  exit 1
fi

if ! echo "$KERNEL" | grep -q "rpt-rpi-v8"; then
  echo "[WARN] Kernel does not look like Raspberry Pi kernel (rpt-rpi-v8)."
  echo "       Detected: $KERNEL"
  echo "       Continuing anyway..."
fi

# Resolve to repo root and scripts dir
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"

if [[ ! -d "$SCRIPTS_DIR" ]]; then
  echo "ERROR: scripts/ directory not found at: $SCRIPTS_DIR" >&2
  exit 1
fi

cd "$SCRIPTS_DIR"

# Make sure the stage scripts are executable (safe on fresh OS)
chmod +x utils.sh stage*.sh || true

echo "== Running all stages (0 → 6) =="

stages=(stage0_prep.sh stage1_wan.sh stage2_lan.sh stage3_ap.sh stage4_nat.sh stage5_health.sh stage6_enable.sh)

for s in "${stages[@]}"; do
  echo ">>> Running $s"
  bash "$s"               # <— force bash, do NOT use ./\$s
  echo ">>> Done $s"
  sleep 1
done

echo "== Complete. Reboot is recommended =="

