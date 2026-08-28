# RatOS IDEX Active Nozzle Camera v0.1.2

## Reliability, Security, and Low-Overhead Hardening

This release focuses on improving resilience and upgrade safety while keeping runtime overhead minimal for Raspberry Pi camera hosts.

### Highlights

- Moves new shared-token clients to the `X-Active-Nozzle-Token` HTTP header so tokens no longer need to appear in request URLs.
- Keeps v0.1.1 query-token compatibility for upgrades while stripping query strings from normal request logs.
- Uses `hmac.compare_digest()` for token comparison.
- Supports complex UTF-8 tokens by transporting the header value as ASCII-safe base64.
- Adds an 8 MiB upper bound for individual JPEG frames and snapshots so malformed upstream streams cannot grow memory indefinitely.
- Discards malformed pre-JPEG data immediately except for the single byte needed to detect a split JPEG start marker.
- Adds `bash ./install.sh upgrade` to preserve existing camera URLs, switcher host/port, and token values while updating installed components.
- Creates pre-upgrade backups of camera-host service/configuration files and generated printer-side integration files.
- Migrates older raw printer-helper tokens to the encoded header format during upgrade.
- Restarts only `active-nozzle-camera.service` when upgrading the camera-host component; Klipper is never restarted automatically.
- Adds full automated install, reinstall, upgrade, and uninstall lifecycle coverage in GitHub Actions.
- Documents resource-footprint goals and v0.1.2 upgrade behavior in the README.

### Runtime Footprint

The v0.1.2 hardening work was designed specifically to avoid adding persistent load to Raspberry Pi camera hosts.

- No background health polling was added.
- No telemetry database, frame history, or persistent cache was added.
- No additional camera connections are created for monitoring.
- Upgrade and migration logic runs only when the installer is invoked.
- CI validation runs only on GitHub Actions.
- Normal MJPEG streaming remains the primary runtime workload.

### Stream Safety

A single JPEG frame or snapshot is limited to 8 MiB. This leaves substantial headroom for high-resolution USB cameras while preventing a broken stream that never emits a JPEG end marker from consuming memory without bound.

Malformed data before a JPEG start marker is discarded immediately, except for one trailing byte required to recognize a marker split across network reads.

### Shared-Token Changes

New v0.1.2 printer helpers and `verify.sh` requests send the optional shared token in the `X-Active-Nozzle-Token` header as base64-encoded UTF-8 bytes.

The service continues to accept the v0.1.1 `?token=` query format for compatibility during upgrades, but HTTP request logging removes query strings so legacy tokens are not written to normal service logs.

Existing manual configurations using the older `ACTIVE_CAMERA_TOKEN` environment variable remain supported.

### Upgrade

Existing installations can be upgraded with:

```bash
bash ./install.sh upgrade
```

Run the command on each machine that has an Active Nozzle Camera component installed.

The upgrader detects installed camera-host and printer-side components, preserves their current settings, creates timestamped backups, updates generated files, and avoids restarting Klipper.

If an existing printer helper cannot be parsed safely, the upgrade stops rather than guessing at its configuration.

### Validation

GitHub Actions now validates:

- shell syntax and Python compilation
- active-tool selection and status/health responses
- blank snapshot fallback to MJPEG frame extraction
- complex UTF-8 token authentication
- malformed-token rejection
- legacy token compatibility
- query-string log redaction
- oversized incomplete JPEG rejection
- settings-preserving upgrade behavior
- legacy printer-token migration
- install and reinstall idempotency
- uninstall cleanup and `printer.cfg` backup behavior
- confirmation that Klipper is never restarted by install, upgrade, or uninstall flows

All v0.1.2 development validation runs completed successfully before release preparation.

### Compatibility

- RatOS / Klipper IDEX configurations using `extruder` for T0 and `extruder1` for T1
- Local-camera and remote-camera-host layouts
- Existing v0.1.1 installations
- Existing v0.1.0/manual configurations using `ACTIVE_CAMERA_TOKEN`

### License

GNU General Public License v3.0 (GPL-3.0).
