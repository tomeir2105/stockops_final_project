#!/usr/bin/env bash
######################################
# Created by : Meir
# Purpose : Orchestrate staged setup (0→6) for Raspberry Pi router/AP on Debian 13 (trixie)
# Date : 2025-10-29
# Version : 1
######################################

#!/usr/bin/env bash

# Fail fast on errors:
# -e  : exit on any command failure
# -u  : treat unset variables as errors
# -o pipefail : fail a pipeline if any command fails
set -euo pipefail

# --- OS verification ---
# Read OS information from /etc/os-release in a subshell to avoid polluting environment
OS_ID="$(. /etc/os-release && echo "$ID")"
OS_VERSION_ID="$(. /etc/os-release && echo "$VERSION_ID")"
# Capture full kernel string for a light sanity check that this is an RPi kernel
KERNEL="$(uname -a)"

# Enforce Debian 13 (trixie) only; exit with a clear message if mismatch
if [[ "$OS_ID" != "debian" || "$OS_VERSION_ID" != "13" ]]; then
  echo "[ERR ] This installer is tested only on Debian 13 (trixie)."
  echo "       Detected: ID=$OS_ID VERSION_ID=$OS_VERSION_ID"
  exit 1
fi

# Warn (but do not fail) if the kernel string does not look like an RPi kernel
if ! echo "$KERNEL" | grep -q "rpt-rpi-v8"; then
  echo "[WARN] Kernel does not look like Raspberry Pi kernel (rpt-rpi-v8)."
  echo "       Detected: $KERNEL"
  echo "       Continuing anyway..."
fi

# --- Paths resolution ---
# Resolve repository root based on this script's location
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# scripts/ directory is expected to live under repo root
SCRIPTS_DIR="$ROOT_DIR/scripts"

# Validate scripts/ presence early to avoid partial runs
if [[ ! -d "$SCRIPTS_DIR" ]]; then
  echo "ERROR: scripts/ directory not found at: $SCRIPTS_DIR" >&2
  exit 1
fi

# Move into scripts/ so relative paths inside stage scripts are stable
cd "$SCRIPTS_DIR"

# Ensure stage scripts are executable; ignore errors to keep idempotency on fresh OS
chmod +x utils.sh stage*.sh || true

echo "== Running all stages (0 → 6) =="

# Ordered list of stage scripts to execute
stages=(
  stage0_prep.sh
  stage1_wan.sh
  stage2_lan.sh
  stage3_ap.sh
  stage4_nat.sh
  stage5_health.sh
  stage6_enable.sh
)

# Execute stages sequentially with a small pause between them
for s in "${stages[@]}"; do
  echo ">>> Running $s"
  bash "$s"               # force bash, do NOT use ./$s to avoid exec bit assumptions and shebang quirks
  echo ">>> Done $s"
  sleep 1
done

echo "== Complete. Reboot is recommended =="

