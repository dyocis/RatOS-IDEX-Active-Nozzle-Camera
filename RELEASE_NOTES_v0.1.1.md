# RatOS IDEX Active Nozzle Camera v0.1.1

## Reliability and Installer Improvements

This release focuses on recovery behavior, safer configuration changes, token handling, and automated validation.

### Highlights

- Adds periodic active-camera re-synchronization every 30 seconds so the Active Nozzle feed recovers automatically after a camera-host or switcher restart without waiting for another tool change.
- Creates timestamped `printer.cfg` backups before installer or uninstaller modifications.
- Fixes optional snapshot URL handling so blank snapshot URLs are preserved and snapshots can be extracted directly from the MJPEG stream.
- Hardens optional shared-token handling:
  - stores installer-provided tokens as UTF-8 base64 in `ACTIVE_CAMERA_TOKEN_B64`
  - preserves backward compatibility with `ACTIVE_CAMERA_TOKEN`
  - URL-encodes tool and token query parameters with `curl`
  - supports spaces and URL-special characters in tokens
- Improves `verify.sh` token support.
- Adds functional GitHub Actions tests for health/status endpoints, tool selection, blank snapshot fallback, token authentication, invalid tool rejection, and legacy token compatibility.
- Improves README installation instructions, validation/release/license badges, backup documentation, and restart recovery behavior.

### Validation

Printer-side validation confirmed that when T1 was active and the camera switcher service was restarted, the feed temporarily returned to T0 and then automatically recovered to T1 within about 30 seconds without another tool change.

Additional temporary-environment tests confirmed:

- installer backup creation
- no unnecessary backup on repeated install
- uninstaller pre-change backup creation
- include idempotency
- blank and explicit snapshot URL handling
- complex-token base64 round-trip
- rejection of missing or incorrect tokens
- successful complex-token authentication through both `verify.sh` and the generated printer helper

GitHub Actions functional tests also pass on the development branch.

### Compatibility

- RatOS / Klipper IDEX configurations using `extruder` for T0 and `extruder1` for T1
- Local-camera and remote-camera-host layouts
- Existing v0.1.0/manual configurations using `ACTIVE_CAMERA_TOKEN`

### License

GNU General Public License v3.0 (GPL-3.0).
