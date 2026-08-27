#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-}"
if [[ -z "$ROLE" ]]; then
  echo "Usage: $0 {local|camera-host|printer}"
  exit 2
fi

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

remove_camera_host() {
  sudo systemctl disable --now active-nozzle-camera.service 2>/dev/null || true
  sudo rm -f /etc/systemd/system/active-nozzle-camera.service
  sudo rm -f /etc/default/active-nozzle-camera
  sudo rm -rf /usr/local/lib/active-nozzle-camera
  sudo systemctl daemon-reload
  echo "Camera-host components removed."
}

remove_printer() {
  CONFIG_DIR="${PRINTER_CONFIG_DIR:-$TARGET_HOME/printer_data/config}"
  printer_cfg="$CONFIG_DIR/printer.cfg"

  if [[ -f "$printer_cfg" ]]; then
    sed -i '/^# Automatic IDEX active nozzle camera$/d' "$printer_cfg"
    sed -i '/^\[include active_nozzle_camera\.cfg\]$/d' "$printer_cfg"
  fi

  rm -f "$CONFIG_DIR/active_nozzle_camera.cfg"
  rm -f "$CONFIG_DIR/scripts/active_nozzle_camera.sh"

  echo "Printer-side files removed."
  echo "Klipper was NOT restarted."
}

case "$ROLE" in
  camera-host)
    remove_camera_host
    ;;
  printer)
    remove_printer
    ;;
  local)
    remove_printer
    remove_camera_host
    ;;
  *)
    echo "Usage: $0 {local|camera-host|printer}"
    exit 2
    ;;
esac
