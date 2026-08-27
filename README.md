# RatOS IDEX Active Nozzle Camera

[![Validate](https://github.com/dyocis/RatOS-IDEX-Active-Nozzle-Camera/actions/workflows/validate.yml/badge.svg)](https://github.com/dyocis/RatOS-IDEX-Active-Nozzle-Camera/actions/workflows/validate.yml)
[![Latest Release](https://img.shields.io/github/v/release/dyocis/RatOS-IDEX-Active-Nozzle-Camera)](https://github.com/dyocis/RatOS-IDEX-Active-Nozzle-Camera/releases/latest)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

Automatically switches a single Mainsail webcam feed between the T0 and T1 nozzle cameras based on the active RatOS IDEX toolhead. Supports cameras connected directly to the printer Pi or hosted on a separate Raspberry Pi.

The design supports both common layouts:

1. **Local cameras** — both nozzle cameras are connected directly to the RatRig/RatOS Pi.
2. **Remote camera host** — the cameras are connected to a second Raspberry Pi or other Linux host, while Klipper/RatOS runs on the printer Pi.

The Klipper side watches the actual active extruder (`extruder` / `extruder1`). It does not replace or edit RatOS's stock `_SELECT_TOOL` macro.

## Demo

![Active Nozzle camera switching demo](docs/active_nozzle.gif)

Animated demo of the Active Nozzle webcam feed following real RatOS IDEX tool changes in Mainsail.

## How it works

```text
T0 camera stream ─┐
                  ├─> Active Nozzle Camera service ─> one stable MJPEG URL ─> Mainsail
T1 camera stream ─┘
                            ^
                            |
                   RatOS active tool watcher
```

The switcher exposes:

- `/?action=stream` — active MJPEG stream
- `/?action=snapshot` — snapshot from the active camera
- `/status` — current selected tool
- `/health` — simple health response
- `/select?tool=0` — select T0
- `/select?tool=1` — select T1

## Requirements

### Camera host

- Linux with systemd
- Python 3
- Existing T0 and T1 MJPEG camera streams
- The source streams must be reachable from the host running the switcher

### RatOS printer

- RatOS / Klipper
- `gcode_shell_command` support
- `curl`
- Standard RatOS IDEX extruder names: `extruder` for T0 and `extruder1` for T1

The installer never restarts Klipper automatically.

## Quick install

Clone the repository on each machine where you need to install a component:

```bash
git clone https://github.com/dyocis/RatOS-IDEX-Active-Nozzle-Camera.git
cd RatOS-IDEX-Active-Nozzle-Camera
```

The examples below invoke the scripts with `bash`, so executable file permissions are not required.

### Option A — Cameras connected directly to the RatRig Pi

Run on the RatRig Pi:

```bash
bash ./install.sh local
```

The installer will ask for the full T0 and T1 stream URLs. Snapshot URLs are optional; leave them blank to extract snapshots from the MJPEG streams.

Example stream URLs:

```text
T0: http://127.0.0.1:8080/?action=stream
T1: http://127.0.0.1:8081/?action=stream
```

It installs both the camera switcher and the Klipper integration.

### Option B — Cameras on a separate Raspberry Pi

On the camera Pi:

```bash
bash ./install.sh camera-host
```

Enter the existing T0 and T1 stream URLs as seen from that camera Pi. Snapshot URLs may be left blank.

Then on the RatOS printer Pi:

```bash
bash ./install.sh printer
```

Enter the camera host's IP/hostname and active stream port when prompted.

Example:

```text
Switcher host: 192.168.1.50
Switcher port: 8084
```

## Mainsail webcam

After installing the camera-host portion, add one webcam to Mainsail.

For cameras connected directly to the printer Pi:

```text
Stream URL:   http://<PRINTER-IP>:8084/?action=stream
Snapshot URL: http://<PRINTER-IP>:8084/?action=snapshot
```

For a separate camera Pi:

```text
Stream URL:   http://<CAMERA-PI-IP>:8084/?action=stream
Snapshot URL: http://<CAMERA-PI-IP>:8084/?action=snapshot
```

Use the Mainsail webcam service type that correctly displays your MJPEG stream. Some installations work with **MJPEG-Streamer**, while others require **MJPEG-Streamer experimental**.

## Test before restarting Klipper

Test the camera host manually:

```bash
curl -s 'http://127.0.0.1:8084/status'
curl -s 'http://127.0.0.1:8084/select?tool=1'
curl -s 'http://127.0.0.1:8084/select?tool=0'
```

For a remote camera host, replace `127.0.0.1` with its IP address.

You can also run:

```bash
bash ./verify.sh <switcher-host> [port] [token]
```

Example without a token:

```bash
bash ./verify.sh 192.168.1.50 8084
```

Example with a token:

```bash
bash ./verify.sh 192.168.1.50 8084 'my token & symbols'
```

Instead of passing the token as the third argument, you may set `ACTIVE_CAMERA_TOKEN` in the shell environment before running `verify.sh`.

## Klipper restart

The printer installer adds:

```ini
[include active_nozzle_camera.cfg]
```

to `printer.cfg` if it is not already present. Before changing `printer.cfg`, the installer creates a timestamped backup under:

```text
~/printer_data/config/.active-nozzle-camera-backups/
```

**The installer does not restart Klipper.** Finish any active print first, then restart Klipper from Mainsail or with your normal workflow.

After restart:

1. Display the Active Nozzle webcam.
2. Select T1 and verify the feed changes to T1.
3. Select T0 and verify it returns to T0.
4. Run a small two-tool print and verify the feed follows actual tool changes.

The active tool is checked every 0.5 seconds. It is also reasserted every 30 seconds so a restarted camera host automatically returns to the correct nozzle feed even if no additional tool change occurs.

## Tested Hardware

Initial development and validation were performed on:

- RatRig V-Core 4 IDEX
- RatOS 2.1
- Dual nozzle cameras
- MJPEG camera streams
- Mainsail
- Separate Raspberry Pi camera host

The Active Nozzle feed was validated during a real two-color IDEX print and switched correctly on every tool change.

## Configuration files

### Camera host

The camera switcher reads:

```text
/etc/default/active-nozzle-camera
```

Example:

```bash
ACTIVE_CAMERA_LISTEN_HOST=0.0.0.0
ACTIVE_CAMERA_LISTEN_PORT=8084
T0_STREAM_URL=http://127.0.0.1:8080/?action=stream
T0_SNAPSHOT_URL=
T1_STREAM_URL=http://127.0.0.1:8081/?action=stream
T1_SNAPSHOT_URL=
ACTIVE_CAMERA_TOKEN_B64=
```

If a snapshot URL is blank, the service extracts a JPEG frame from the corresponding MJPEG stream instead.

The installer stores the optional shared token as UTF-8 base64 in `ACTIVE_CAMERA_TOKEN_B64` so shell/systemd metacharacters do not corrupt the environment file. The service still accepts the older `ACTIVE_CAMERA_TOKEN` variable for backward compatibility with v0.1.0/manual configurations.

### Printer side

The installer creates:

```text
~/printer_data/config/active_nozzle_camera.cfg
~/printer_data/config/scripts/active_nozzle_camera.sh
```

The shell helper sends a short HTTP request to the camera switcher when Klipper detects that the active tool changed and periodically reasserts the current tool. Token and tool query parameters are URL-encoded by `curl`.

## Optional token

The camera-host installer can configure an optional shared token.

If enabled, `/select` requires the token and the printer helper includes it automatically. Tokens containing spaces or URL-special characters such as `&`, `+`, `%`, `#`, and `=` are supported.

The token is intended only as a lightweight control on a trusted local network. It is sent over ordinary HTTP unless your network provides HTTPS separately, so do not treat it as Internet-facing authentication and do not expose the service directly to the public Internet.

## Uninstall

### Local installation

```bash
bash ./uninstall.sh local
```

### Remote camera host

On the camera host:

```bash
bash ./uninstall.sh camera-host
```

On the printer:

```bash
bash ./uninstall.sh printer
```

Before removing its entries from `printer.cfg`, the uninstaller creates a timestamped backup under `.active-nozzle-camera-backups`. The uninstaller does not restart Klipper.

## Notes

- Existing camera services are not modified.
- Existing individual T0/T1 webcam entries can remain in Mainsail.
- The Active Nozzle feed is an additional logical webcam.
- The switcher re-emits JPEG frames with its own MJPEG boundary, so the two source cameras do not need to use identical multipart boundaries.
- A camera host restart defaults the switcher to T0, then the printer-side heartbeat reasserts the actual active tool within about 30 seconds.
- Licensed under the GNU General Public License v3.0 (GPL-3.0).

## License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)**. See `LICENSE` for the full license text.
