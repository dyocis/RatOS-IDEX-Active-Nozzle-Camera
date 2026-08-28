#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-127.0.0.1}"
PORT="${2:-8084}"
TOKEN="${3:-${ACTIVE_CAMERA_TOKEN:-}}"
BASE="http://${HOST}:${PORT}"
TOKEN_B64=""

if [[ -n "$TOKEN" ]]; then
  command -v python3 >/dev/null 2>&1 || {
    echo "python3 is required when using a shared token" >&2
    exit 1
  }
  TOKEN_B64="$(python3 -c 'import base64,sys; print(base64.b64encode(sys.argv[1].encode("utf-8")).decode("ascii"))' "$TOKEN")"
fi

select_tool() {
  local tool="$1"
  local args=(
    -fsS
    --max-time 2
    --get
    --data-urlencode "tool=${tool}"
  )

  if [[ -n "$TOKEN_B64" ]]; then
    args+=(--header "X-Active-Nozzle-Token: ${TOKEN_B64}")
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
