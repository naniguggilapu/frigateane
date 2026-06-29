# Changelog

## v1.1.0

Validated end-to-end on a live camera (Frigate in Apple `container` → ANE detector →
real-time inference), and hardened from what that testing exposed.

### Fixed
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
