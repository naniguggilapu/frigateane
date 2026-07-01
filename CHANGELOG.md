# Changelog

## v1.2.1

### Fixed
- **Detector crash-loop** — if `tcp://…:5555` was already in use (e.g. a stale detector),
  the engine restarted forever and spammed the log. It now backs off after a few immediate
  failures and tells you the port is busy; "Start/Stop Detector" retries.
- **Overlapping status probes** — the dashboard timer could launch a new stack probe
  (multiple `container`/`curl` calls) before the previous finished. Probes are now guarded
  so only one runs at a time, the interval is 5s, and probing pauses while the window is hidden.

## v1.2.0

### Added
- **Backup / Restore config** — export your settings to a JSON file and restore them later (dashboard).
- **Auto-detect container IP** — "Open Frigate UI" and the health check now use the Frigate
  container's own IP (falling back to `localhost`), so the UI opens even on Macs where Apple
  `container` doesn't publish to localhost.
- **Model-type picker** — choose the Frigate `model_type` (yolo-generic / yolonas / yolov9 /
  rfdetr / dfine) alongside the model file and input size.
- **Scrypted detection** — detect a Scrypted server (host + default ports) and open it to copy
  each camera's **rebroadcast RTSP URL** (no camera credentials needed).

## v1.1.2

### Fixed
- **Duplicate camera keys crashed Frigate.** Adding two cameras with the same id
  produced two `camera:` keys in `config.yaml`, which Frigate rejects
  (`ruamel.yaml DuplicateKeyError`) — the container stayed "running" but the web server
  (NGINX) exited, so the UI showed *connection failed*. The generator now guarantees
  **unique camera keys** (duplicates get `_2`, `_3`, …), new cameras get a unique default
  id, and cameras with no stream URL are skipped. (Diagnosed from a real failing config.)

## v1.1.1

Verified end-to-end on a live camera, including the Frigate web UI loading.

### Added
- **Admin password management.** Frigate auto-generates an `admin` password on first
  start (shown only once, in its logs). The dashboard now surfaces it with
  **Show Admin Password**, and **Reset Admin Password** regenerates it (flips
  `reset_admin_password`, restarts Frigate, captures the new password, clears the flag).

### Fixed
- **Setup wizard "Add Camera"** now actually shows the camera row — the camera list's
  scroll view collapsed to zero height (missing bottom constraint), so rows were added
  but invisible; the list is also flipped so rows stack top-down. (Verified by driving
  the live UI.)
- Clarified that the Frigate web UI is served over **HTTPS** on `:8971` (self-signed);
  the app's status/Open-UI use `https://`.

## v1.1.0

Validated end-to-end on a live camera (Frigate in Apple `container` → ANE detector →
real-time inference), and hardened from what that testing exposed.

### Fixed
- **Setup wizard — Add Camera**: clicking *Add camera* now actually shows the camera
  row. The camera list's scroll view collapsed to zero height (missing bottom
  constraint), so rows were added but invisible; the list is also flipped so rows stack
  top-down. (Verified by driving the live UI.)
- **Model cache**: the model is now **copied** into the Frigate config dir instead of
  symlinked. The config dir is bind-mounted into the container, so a symlink pointed
  outside it and was broken in-container — Frigate couldn't load the model and detection
  silently failed. (Caught by end-to-end testing.)
- **Container kernel auto-config**: fresh `container` installs error with
  *"default kernel not configured for architecture arm64."* The app now installs the
  recommended kernel (`container system kernel set --recommended`) on runtime install,
  and auto-installs + retries if a start hits that error.
- **Health check**: Frigate's UI on `:8971` is HTTPS (self-signed); the old `http://`
  probe returned `400` and mislabeled Frigate as not healthy. Now uses `https` everywhere
  (status check, "Open Frigate UI", start log).
- `onnxruntime` pinned to `1.26.0` (1.27.x has a CoreML regression on this model).

### Added
- **Camera UX**: display name / alias (emitted as Frigate `friendly_name`), separate
  **RTSP user + password** fields (URL-encoded and injected into the stream URLs), camera
  **UI order**, and wider stream-link inputs.
- **Portable bundled Python** (python-build-standalone) — the engine runs on any
  Apple-Silicon Mac with no Homebrew/system Python.
- **Container-runtime auto-detect + guided install** (checks macOS 26, installs Apple
  `container` from the signed `.pkg`).
- **Connection tests** — MQTT CONNECT, per-camera RTSP reachability, ANE detector self-test.
- **Launch-at-login + auto-start** Frigate/detector on launch.
- **Dashboard live stats** — inferences/sec sparkline, auto-refreshing stack status,
  menubar throughput; plus Reveal/Copy config actions.
- **One-click container NAT networking** install + start-up health checks.
- Richer start logs (camera count, config + storage paths, UI URL).
- Notarization pipeline (`scripts/notarize.sh` + entitlements) for signed distribution.

### Credits
Built on [`frigate-nvr/apple-silicon-detector`](https://github.com/frigate-nvr/apple-silicon-detector)
(the ANE detector) and harb70's Apple-Container how-to. See [CREDITS.md](CREDITS.md).

## v0.1.0
Initial native macOS app: setup wizard, config generator, ANE detector engine,
container orchestrator.
