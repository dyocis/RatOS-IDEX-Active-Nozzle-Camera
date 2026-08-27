#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-127.0.0.1}"
PORT="${2:-8084}"
TOKEN="${3:-${ACTIVE_CAMERA_TOKEN:-}}"
BASE="http://${HOST}:${PORT}"
TOKEN_Q=""
if [[ -n "$TOKEN" ]]; then
  TOKEN_Q="&token=${TOKEN}"
fi

echo "===== HEALTH ====="
curl -fsS --max-time 2 "${BASE}/health"
echo

echo "===== STATUS ====="
curl -fsS --max-time 2 "${BASE}/status"
echo

echo "===== SELECT T1 ====="
curl -fsS --max-time 2 "${BASE}/select?tool=1${TOKEN_Q}"
echo

sleep 2

echo "===== SELECT T0 ====="
curl -fsS --max-time 2 "${BASE}/select?tool=0${TOKEN_Q}"
echo

echo "Verification requests completed."
