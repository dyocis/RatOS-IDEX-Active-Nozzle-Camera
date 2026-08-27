#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-127.0.0.1}"
PORT="${2:-8084}"
TOKEN="${3:-${ACTIVE_CAMERA_TOKEN:-}}"
BASE="http://${HOST}:${PORT}"

select_tool() {
  local tool="$1"
  local args=(
    -fsS
    --max-time 2
    --get
    --data-urlencode "tool=${tool}"
  )

  if [[ -n "$TOKEN" ]]; then
    args+=(--data-urlencode "token=${TOKEN}")
  fi

  curl "${args[@]}" "${BASE}/select"
}

echo "===== HEALTH ====="
curl -fsS --max-time 2 "${BASE}/health"
echo

echo "===== STATUS ====="
curl -fsS --max-time 2 "${BASE}/status"
echo

echo "===== SELECT T1 ====="
select_tool 1
echo

sleep 2

echo "===== SELECT T0 ====="
select_tool 0
echo

echo "Verification requests completed."
