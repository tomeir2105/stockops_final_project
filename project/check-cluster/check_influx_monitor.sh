#!/usr/bin/env bash
######################################
# Created by : Meir
# Purpose    : Check recent CPU/RAM data written into InfluxDB (CSV preview)
# Date       : 2025-10-30
# Version    : 1
######################################

set -Eeuo pipefail

# --- CONFIGURATION (override via env if needed) --------------------------------
INFLUX_URL="${INFLUX_URL:-http://influxdb.stockops.svc.cluster.local:8086}"
INFLUX_ORG="${INFLUX_ORG:-monitor}"
INFLUX_BUCKET="${INFLUX_BUCKET:-netdata_2h}"
INFLUX_TOKEN="${INFLUX_TOKEN:-}"  # required; pass via env or Jenkins secret

# --- Sanity checks --------------------------------------------------------------
if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl not found in PATH." >&2
  exit 1
fi

if [[ -z "$INFLUX_TOKEN" ]]; then
  echo "ERROR: INFLUX_TOKEN not set." >&2
  echo "Set it with: export INFLUX_TOKEN='your_token_here'" >&2
  exit 1
fi

if [[ -z "$INFLUX_URL" || -z "$INFLUX_ORG" || -z "$INFLUX_BUCKET" ]]; then
  echo "ERROR: INFLUX_URL/INFLUX_ORG/INFLUX_BUCKET must not be empty." >&2
  exit 1
fi

# --- Helper --------------------------------------------------------------------
query_influx() {
  local measurement=$1
  local field=$2
  local label=$3

  echo
  echo "Querying latest ${label} data..."
  echo "-------------------------------------------"

  # --fail makes curl exit non-zero on HTTP >=400 (prevents false success)
  # timeouts prevent hanging
  curl --fail -sS \
    --connect-timeout 5 --max-time 20 \
    "${INFLUX_URL}/api/v2/query?org=${INFLUX_ORG}" \
    -H "Authorization: Token ${INFLUX_TOKEN}" \
    -H "Accept: application/csv" \
    -H "Content-Type: application/vnd.flux" \
    --data-binary @- <<EOF | head -n 20
from(bucket: "${INFLUX_BUCKET}")
  |> range(start: -30m)
  |> filter(fn: (r) => r._measurement == "${measurement}" and r._field == "${field}")
  |> sort(columns: ["_time"], desc: true)
  |> limit(n: 10)
EOF
}

# --- Main ----------------------------------------------------------------------
echo "Checking InfluxDB data..."
echo "InfluxDB URL  : ${INFLUX_URL}"
echo "Organization  : ${INFLUX_ORG}"
echo "Bucket        : ${INFLUX_BUCKET}"
echo

# CPU
query_influx "netdata_cpu" "used_percent" "CPU used%"

# RAM
query_influx "netdata_mem" "used_bytes" "RAM used bytes"

echo
echo "Done. Above are the last ~30 minutes of measurements."

