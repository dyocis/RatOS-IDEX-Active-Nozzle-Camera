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
  "$SYSTEM_ROOT/usr/local/lib/active-nozzle-camera" \
  "$CONFIG_DIR/scripts"

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

TOKEN='Test token & plus+percent%hash#equals=space'
TOKEN_B64="$(python3 -c 'import base64,sys; print(base64.b64encode(sys.argv[1].encode()).decode())' "$TOKEN")"

cat >"$SYSTEM_ROOT/etc/default/active-nozzle-camera" <<EOF
ACTIVE_CAMERA_LISTEN_HOST=0.0.0.0
ACTIVE_CAMERA_LISTEN_PORT=8084
T0_STREAM_URL=http://127.0.0.1:8080/?action=stream
T0_SNAPSHOT_URL=
T1_STREAM_URL=http://127.0.0.1:8081/?action=stream
T1_SNAPSHOT_URL=
ACTIVE_CAMERA_TOKEN_B64=$TOKEN_B64
EOF
cp "$SYSTEM_ROOT/etc/default/active-nozzle-camera" "$TEST_ROOT/env.before"

printf '%s\n' '# old switcher' >"$SYSTEM_ROOT/usr/local/lib/active-nozzle-camera/active_nozzle_camera.py"
printf '%s\n' '# old service' >"$SYSTEM_ROOT/etc/systemd/system/active-nozzle-camera.service"

cat >"$CONFIG_DIR/printer.cfg" <<'EOF'
# mock printer.cfg
[include active_nozzle_camera.cfg]
EOF
cp "$CONFIG_DIR/printer.cfg" "$TEST_ROOT/printer.before"

cat >"$CONFIG_DIR/scripts/active_nozzle_camera.sh" <<'EOF'
#!/usr/bin/env bash
BASE_URL="http://192.168.50.82:8084/select"
TOKEN='Test token & plus+percent%hash#equals=space'
EOF
chmod +x "$CONFIG_DIR/scripts/active_nozzle_camera.sh"
printf '%s\n' '# old generated Klipper integration' >"$CONFIG_DIR/active_nozzle_camera.cfg"

PATH="$FAKEBIN:$PATH" \
SYSTEMCTL_LOG="$SYSTEMCTL_LOG" \
ACTIVE_CAMERA_SYSTEM_ROOT="$SYSTEM_ROOT" \
PRINTER_CONFIG_DIR="$CONFIG_DIR" \
bash "$REPO_ROOT/install.sh" upgrade

cmp -s "$TEST_ROOT/env.before" "$SYSTEM_ROOT/etc/default/active-nozzle-camera"
echo 'PASS: camera-host environment preserved exactly'

grep -q 'MAX_JPEG_BYTES' "$SYSTEM_ROOT/usr/local/lib/active-nozzle-camera/active_nozzle_camera.py"
echo 'PASS: camera-host switcher code upgraded'

grep -qx 'daemon-reload' "$SYSTEMCTL_LOG"
grep -qx 'restart active-nozzle-camera.service' "$SYSTEMCTL_LOG"
echo 'PASS: camera service reloaded and restarted'

if grep -qi 'klipper' "$SYSTEMCTL_LOG"; then
  echo 'FAIL: upgrade attempted to restart Klipper'
  exit 1
fi
echo 'PASS: Klipper was not restarted'

cmp -s "$TEST_ROOT/printer.before" "$CONFIG_DIR/printer.cfg"
echo 'PASS: printer.cfg remained unchanged'

grep -q '^BASE_URL="http://192.168.50.82:8084/select"$' "$CONFIG_DIR/scripts/active_nozzle_camera.sh"
echo 'PASS: printer switcher host and port preserved'

grep -q "^TOKEN_B64=$TOKEN_B64$" "$CONFIG_DIR/scripts/active_nozzle_camera.sh"
echo 'PASS: legacy printer token migrated without re-prompting'

if grep -q '^TOKEN=' "$CONFIG_DIR/scripts/active_nozzle_camera.sh"; then
  echo 'FAIL: legacy raw TOKEN assignment remains in upgraded helper'
  exit 1
fi
echo 'PASS: upgraded helper no longer stores legacy raw TOKEN assignment'

CAMERA_BACKUP="$(find "$SYSTEM_ROOT/etc/active-nozzle-camera-backups" -mindepth 1 -maxdepth 1 -type d | head -1)"
PRINTER_BACKUP="$(find "$CONFIG_DIR/.active-nozzle-camera-backups" -mindepth 1 -maxdepth 1 -type d | head -1)"

[[ -n "$CAMERA_BACKUP" && -f "$CAMERA_BACKUP/active-nozzle-camera.env" ]]
cmp -s "$TEST_ROOT/env.before" "$CAMERA_BACKUP/active-nozzle-camera.env"
echo 'PASS: pre-upgrade camera-host configuration backed up'

[[ -n "$PRINTER_BACKUP" && -f "$PRINTER_BACKUP/active_nozzle_camera.sh" ]]
echo 'PASS: pre-upgrade printer integration backed up'

echo 'Upgrade functional test completed successfully.'
