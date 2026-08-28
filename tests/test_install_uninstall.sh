#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
FAKEBIN="$TEST_ROOT/fakebin"
SYSTEM_ROOT="$TEST_ROOT/system"
CONFIG_DIR="$TEST_ROOT/config"
SYSTEMCTL_LOG="$TEST_ROOT/systemctl.log"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p \
  "$FAKEBIN" \
  "$SYSTEM_ROOT/etc/default" \
  "$SYSTEM_ROOT/etc/systemd/system" \
  "$SYSTEM_ROOT/usr/local/lib" \
  "$CONFIG_DIR"

cat >"$FAKEBIN/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF

cat >"$FAKEBIN/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"
exit 0
EOF

chmod +x "$FAKEBIN/sudo" "$FAKEBIN/systemctl"

cat >"$CONFIG_DIR/printer.cfg" <<'EOF'
# mock printer.cfg
[printer]
kinematics: corexy
max_velocity: 300
max_accel: 3000
EOF
cp "$CONFIG_DIR/printer.cfg" "$TEST_ROOT/printer.original"

TOKEN='Install test & symbols+%#='

run_local_install() {
  printf '%s\n' \
    'http://127.0.0.1:8080/?action=stream' \
    '' \
    'http://127.0.0.1:8081/?action=stream' \
    '' \
    '8084' \
    "$TOKEN" | \
    PATH="$FAKEBIN:$PATH" \
    SYSTEMCTL_LOG="$SYSTEMCTL_LOG" \
    ACTIVE_CAMERA_SYSTEM_ROOT="$SYSTEM_ROOT" \
    PRINTER_CONFIG_DIR="$CONFIG_DIR" \
    bash "$REPO_ROOT/install.sh" local
}

run_local_install

[[ -f "$SYSTEM_ROOT/etc/default/active-nozzle-camera" ]]
[[ -f "$SYSTEM_ROOT/etc/systemd/system/active-nozzle-camera.service" ]]
[[ -f "$SYSTEM_ROOT/usr/local/lib/active-nozzle-camera/active_nozzle_camera.py" ]]
echo 'PASS: camera-host files installed in isolated system root'

[[ -f "$CONFIG_DIR/active_nozzle_camera.cfg" ]]
[[ -f "$CONFIG_DIR/scripts/active_nozzle_camera.sh" ]]
grep -qxF '[include active_nozzle_camera.cfg]' "$CONFIG_DIR/printer.cfg"
echo 'PASS: printer integration installed'

BACKUP_COUNT="$(find "$CONFIG_DIR/.active-nozzle-camera-backups" -maxdepth 1 -type f -name 'printer.cfg.*.bak' | wc -l)"
[[ "$BACKUP_COUNT" -eq 1 ]]
BACKUP_FILE="$(find "$CONFIG_DIR/.active-nozzle-camera-backups" -maxdepth 1 -type f -name 'printer.cfg.*.bak' | head -1)"
cmp -s "$TEST_ROOT/printer.original" "$BACKUP_FILE"
echo 'PASS: installer backed up original printer.cfg exactly once'

TOKEN_B64="$(python3 -c 'import base64,sys; print(base64.b64encode(sys.argv[1].encode()).decode())' "$TOKEN")"
grep -q "^ACTIVE_CAMERA_TOKEN_B64=$TOKEN_B64$" "$SYSTEM_ROOT/etc/default/active-nozzle-camera"
grep -q "^TOKEN_B64=$TOKEN_B64$" "$CONFIG_DIR/scripts/active_nozzle_camera.sh"
echo 'PASS: shared token encoded consistently for camera host and printer helper'

run_local_install

INCLUDE_COUNT="$(grep -c '^\[include active_nozzle_camera\.cfg\]$' "$CONFIG_DIR/printer.cfg")"
[[ "$INCLUDE_COUNT" -eq 1 ]]
BACKUP_COUNT_AFTER="$(find "$CONFIG_DIR/.active-nozzle-camera-backups" -maxdepth 1 -type f -name 'printer.cfg.*.bak' | wc -l)"
[[ "$BACKUP_COUNT_AFTER" -eq 1 ]]
echo 'PASS: repeated install is idempotent for printer.cfg include and backup'

PATH="$FAKEBIN:$PATH" \
SYSTEMCTL_LOG="$SYSTEMCTL_LOG" \
ACTIVE_CAMERA_SYSTEM_ROOT="$SYSTEM_ROOT" \
PRINTER_CONFIG_DIR="$CONFIG_DIR" \
bash "$REPO_ROOT/uninstall.sh" local

[[ ! -e "$SYSTEM_ROOT/etc/default/active-nozzle-camera" ]]
[[ ! -e "$SYSTEM_ROOT/etc/systemd/system/active-nozzle-camera.service" ]]
[[ ! -e "$SYSTEM_ROOT/usr/local/lib/active-nozzle-camera" ]]
echo 'PASS: camera-host files removed'

[[ ! -e "$CONFIG_DIR/active_nozzle_camera.cfg" ]]
[[ ! -e "$CONFIG_DIR/scripts/active_nozzle_camera.sh" ]]
if grep -qxF '[include active_nozzle_camera.cfg]' "$CONFIG_DIR/printer.cfg"; then
  echo 'FAIL: include remained after uninstall'
  exit 1
fi
echo 'PASS: printer integration removed'

UNINSTALL_BACKUPS="$(find "$CONFIG_DIR/.active-nozzle-camera-backups" -maxdepth 1 -type f -name 'printer.cfg.*.bak' | wc -l)"
[[ "$UNINSTALL_BACKUPS" -eq 2 ]]
echo 'PASS: uninstaller created a pre-change printer.cfg backup'

if grep -qi 'klipper' "$SYSTEMCTL_LOG"; then
  echo 'FAIL: install/uninstall attempted to restart Klipper'
  exit 1
fi
echo 'PASS: Klipper was never restarted'

grep -qx 'enable --now active-nozzle-camera.service' "$SYSTEMCTL_LOG"
grep -qx 'disable --now active-nozzle-camera.service' "$SYSTEMCTL_LOG"
echo 'PASS: only the camera service was managed'

echo 'Install/uninstall functional test completed successfully.'
