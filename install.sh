#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-}"
if [[ -z "$ROLE" ]]; then
  echo "Usage: $0 {local|camera-host|printer}"
  exit 2
fi

if [[ "$ROLE" != "local" && "$ROLE" != "camera-host" && "$ROLE" != "printer" ]]; then
  echo "Invalid role: $ROLE"
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

prompt_default() {
  local prompt="$1"
  local default="$2"
  local value
  read -r -p "$prompt [$default]: " value
  printf '%s' "${value:-$default}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1"
    exit 1
  }
}

install_camera_host() {
  require_cmd python3
  require_cmd systemctl

  echo
  echo "Camera host setup"
  echo "Enter full MJPEG source URLs as seen from this machine."
  echo

  T0_STREAM="$(prompt_default "T0 stream URL" "http://127.0.0.1:8080/?action=stream")"
  T0_SNAPSHOT="$(prompt_default "T0 snapshot URL (blank allowed)" "http://127.0.0.1:8080/?action=snapshot")"
  T1_STREAM="$(prompt_default "T1 stream URL" "http://127.0.0.1:8081/?action=stream")"
  T1_SNAPSHOT="$(prompt_default "T1 snapshot URL (blank allowed)" "http://127.0.0.1:8081/?action=snapshot")"
  ACTIVE_PORT="$(prompt_default "Active Nozzle listen port" "8084")"
  read -r -p "Optional shared token for /select (blank = none): " TOKEN

  sudo install -d -m 755 /usr/local/lib/active-nozzle-camera
  sudo install -m 755 "$SCRIPT_DIR/src/active_nozzle_camera.py" \
    /usr/local/lib/active-nozzle-camera/active_nozzle_camera.py

  tmp_env="$(mktemp)"
  cat >"$tmp_env" <<EOF
ACTIVE_CAMERA_LISTEN_HOST=0.0.0.0
ACTIVE_CAMERA_LISTEN_PORT=$ACTIVE_PORT
T0_STREAM_URL=$T0_STREAM
T0_SNAPSHOT_URL=$T0_SNAPSHOT
T1_STREAM_URL=$T1_STREAM
T1_SNAPSHOT_URL=$T1_SNAPSHOT
ACTIVE_CAMERA_TOKEN=$TOKEN
EOF
  sudo install -m 640 "$tmp_env" /etc/default/active-nozzle-camera
  rm -f "$tmp_env"

  tmp_service="$(mktemp)"
  cat >"$tmp_service" <<EOF
[Unit]
Description=RatOS IDEX Active Nozzle Camera
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$TARGET_USER
EnvironmentFile=/etc/default/active-nozzle-camera
ExecStart=/usr/bin/python3 /usr/local/lib/active-nozzle-camera/active_nozzle_camera.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
  sudo install -m 644 "$tmp_service" /etc/systemd/system/active-nozzle-camera.service
  rm -f "$tmp_service"

  sudo systemctl daemon-reload
  sudo systemctl enable --now active-nozzle-camera.service

  echo
  echo "Camera switcher installed."
  echo "Local test URL: http://127.0.0.1:${ACTIVE_PORT}/status"
}

install_printer() {
  require_cmd curl

  CONFIG_DIR="${PRINTER_CONFIG_DIR:-$TARGET_HOME/printer_data/config}"
  if [[ ! -d "$CONFIG_DIR" ]]; then
    echo "RatOS config directory not found: $CONFIG_DIR"
    echo "Set PRINTER_CONFIG_DIR=/path/to/config and run again."
    exit 1
  fi

  if [[ "$ROLE" == "local" ]]; then
    SWITCHER_HOST="127.0.0.1"
    SWITCHER_PORT="${ACTIVE_PORT:-8084}"
    TOKEN="${TOKEN:-}"
  else
    SWITCHER_HOST="$(prompt_default "Camera switcher host/IP" "127.0.0.1")"
    SWITCHER_PORT="$(prompt_default "Camera switcher port" "8084")"
    read -r -p "Shared token if configured on camera host (blank = none): " TOKEN
  fi

  mkdir -p "$CONFIG_DIR/scripts"

  helper="$CONFIG_DIR/scripts/active_nozzle_camera.sh"
  cat >"$helper" <<EOF
#!/usr/bin/env bash
TOOL="\${1:-}"

case "\$TOOL" in
    0|1) ;;
    *) exit 2 ;;
esac

BASE_URL="http://${SWITCHER_HOST}:${SWITCHER_PORT}/select?tool=\${TOOL}"
TOKEN="${TOKEN}"

if [[ -n "\$TOKEN" ]]; then
    BASE_URL="\${BASE_URL}&token=\${TOKEN}"
fi

/usr/bin/curl \
    -fsS \
    --connect-timeout 0.3 \
    --max-time 1 \
    "\$BASE_URL" \
    >/dev/null 2>&1 &

exit 0
EOF
  chmod 755 "$helper"

  cfg="$CONFIG_DIR/active_nozzle_camera.cfg"
  cat >"$cfg" <<EOF
# RatOS IDEX - automatic active nozzle camera
#
# Watches Klipper's actual active extruder.
# T0 = extruder
# T1 = extruder1
#
# Tool changes are detected every 0.5 seconds. The current tool is also
# reasserted every 30 seconds so a restarted camera host automatically
# returns to the correct active nozzle feed without waiting for another
# tool change.

[gcode_shell_command active_nozzle_camera_select]
command: /bin/bash $helper
timeout: 1.0
verbose: False

[gcode_macro _ACTIVE_NOZZLE_CAMERA_SYNC]
variable_last_tool: -1
variable_heartbeat_count: 0
gcode:
    {% set active = printer.toolhead.extruder %}
    {% set state = printer["gcode_macro _ACTIVE_NOZZLE_CAMERA_SYNC"] %}
    {% set previous_tool = state.last_tool|int %}
    {% set heartbeat_count = state.heartbeat_count|int + 1 %}
    {% set force_sync = heartbeat_count >= 60 %}

    {% if active == "extruder" %}
        {% set current_tool = 0 %}
    {% elif active == "extruder1" %}
        {% set current_tool = 1 %}
    {% else %}
        {% set current_tool = -1 %}
    {% endif %}

    {% if force_sync %}
        SET_GCODE_VARIABLE MACRO=_ACTIVE_NOZZLE_CAMERA_SYNC VARIABLE=heartbeat_count VALUE=0
    {% else %}
        SET_GCODE_VARIABLE MACRO=_ACTIVE_NOZZLE_CAMERA_SYNC VARIABLE=heartbeat_count VALUE={heartbeat_count}
    {% endif %}

    {% if current_tool >= 0 and (current_tool != previous_tool or force_sync) %}
        SET_GCODE_VARIABLE MACRO=_ACTIVE_NOZZLE_CAMERA_SYNC VARIABLE=last_tool VALUE={current_tool}
        RUN_SHELL_COMMAND CMD=active_nozzle_camera_select PARAMS={current_tool}
    {% endif %}

[delayed_gcode _ACTIVE_NOZZLE_CAMERA_WATCH]
initial_duration: 2.0
gcode:
    _ACTIVE_NOZZLE_CAMERA_SYNC
    UPDATE_DELAYED_GCODE ID=_ACTIVE_NOZZLE_CAMERA_WATCH DURATION=0.5
EOF

  printer_cfg="$CONFIG_DIR/printer.cfg"
  if [[ ! -f "$printer_cfg" ]]; then
    echo "printer.cfg not found at $printer_cfg"
    exit 1
  fi

  include='[include active_nozzle_camera.cfg]'
  if ! grep -qxF "$include" "$printer_cfg"; then
    printf '\n# Automatic IDEX active nozzle camera\n%s\n' "$include" >>"$printer_cfg"
  fi

  echo
  echo "Printer-side integration staged."
  echo "Klipper was NOT restarted."
  echo "When it is safe, restart Klipper and verify T0/T1 switching."
}

case "$ROLE" in
  camera-host)
    install_camera_host
    ;;
  printer)
    install_printer
    ;;
  local)
    install_camera_host
    install_printer
    ;;
esac
