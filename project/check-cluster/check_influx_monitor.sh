#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Check recent data written by Jenkins pipelines into InfluxDB (CPU & RAM)
# -----------------------------------------------------------------------------

# === CONFIGURATION ===
INFLUX_URL="http://influxdb.stockops.svc.cluster.local:8086"
INFLUX_ORG="monitor"
INFLUX_BUCKET="netdata_2h"
INFLUX_TOKEN="${INFLUX_TOKEN:-}"  # can be passed via environment or Jenkins secret

# -----------------------------------------------------------------------------
# Helper function
# -----------------------------------------------------------------------------
function query_influx() {
  local measurement=$1
  local field=$2
  local label=$3

  echo
  echo "Querying latest $label data..."
  echo "-------------------------------------------"

  curl -sS "${INFLUX_URL}/api/v2/query?org=${INFLUX_ORG}" \
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

# -----------------------------------------------------------------------------
# MAIN EXECUTION
# -----------------------------------------------------------------------------
if [[ -z "$INFLUX_TOKEN" ]]; then
  echo "ERROR: INFLUX_TOKEN not set."
  echo "You can export it like this:"
  echo "  export INFLUX_TOKEN='your_token_here'"
  exit 1
fi

echo "Checking InfluxDB data..."
echo "InfluxDB URL  : $INFLUX_URL"
echo "Organization  : $INFLUX_ORG"
echo "Bucket        : $INFLUX_BUCKET"
echo

# --- CPU ---
query_influx "netdata_cpu" "used_percent" "CPU used%"

# --- RAM ---
query_influx "netdata_mem" "used_bytes" "RAM used bytes"

echo
echo "Done. Above are the last ~30 minutes of measurements."

