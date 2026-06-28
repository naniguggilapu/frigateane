# Frigate ANE Detector (macOS, Apple Silicon)

A native macOS app that runs [Frigate](https://frigate.video) object detection on
the **Apple Neural Engine (ANE)** and gives you a one-window setup + dashboard for
the whole stack — MQTT / Home Assistant, recordings storage, cameras, and models.

> **Status:** v0.1 — foundation. The app, setup wizard, config generator, and
> detector engine work. Full container orchestration is wired but still being
> hardened on live targets (see *Roadmap*).

## Why

Frigate's stock detectors don't use Apple's Neural Engine. This project runs YOLO
via ONNX Runtime's **CoreML execution provider** (`CPUAndNeuralEngine`) in a small
Python ZMQ server, and ships a native Swift app that supervises it and orchestrates
Frigate (running in Apple's `container` runtime).

## Architecture

```
┌──────────────────────────────┐        ZMQ tcp:5555        ┌────────────────────┐
│  FrigateANEDetector.app       │ ◀───────────────────────▶ │  Frigate container │
│  (native Swift, arm64)        │                            │  (Apple container) │
│  • Setup wizard               │   writes config.yaml ────▶ │  cameras, record,  │
│  • Dashboard / menubar        │   + start script           │  go2rtc, MQTT      │
│  • Supervises Python engine   │                            └────────────────────┘
│        │                      │
│        ▼                      │
│  engine/ (venv)               │
│   detector/zmq_onnx_client.py │  ── YOLO ONNX on the ANE (CoreML EP)
│   models/yolo.onnx            │
└──────────────────────────────┘
```

## Requirements

- Apple Silicon Mac (M1 or newer) — the ANE path requires arm64.
- macOS 13+ to run the app; **macOS 26 + Apple `container`** to run Frigate itself.
- Xcode command-line tools (for building from source).
- An MQTT broker (e.g. Home Assistant's Mosquitto) if you want HA integration.

## Build

```bash
git clone <your-fork-url> frigate-ane-mac
cd frigate-ane-mac
bash scripts/build.sh           # provisions engine, compiles, assembles the .app
open ~/Applications/FrigateANEDetector.app
```

`scripts/provision_engine.sh` creates the Python venv, installs `onnxruntime` /
`pyzmq` / `numpy`, and exports a `yolo.onnx` (via ultralytics) if one isn't present.

## Use

1. Launch the app — the **Setup** wizard opens on first run.
2. Fill in the tabs:
   - **MQTT** — broker host/port/user/password.
   - **Home Assistant** — toggle MQTT auto-discovery.
   - **Storage** — pick a *mounted* drive/folder for recordings (the app warns if it's missing).
   - **Cameras** — add RTSP main/sub streams; set retention (continuous / event days).
   - **Models** — choose the YOLO `.onnx` (runs on the ANE); optionally enable a local
     AI vision model via Ollama for scene descriptions.
3. **Save & Generate Config** writes `config.yaml` + a guarded `start-frigate.sh` to
   `~/Library/Application Support/FrigateANE/`.
4. On the **Dashboard**, **Start All** ensures the container system is up, pulls the
   Frigate image if needed, and starts Frigate + the ANE detector. Open the Frigate
   UI at `http://localhost:8971`.

Settings live in `~/Library/Application Support/FrigateANE/config.json`. No secrets
are committed to the repo.

## Roadmap

- [ ] Hardened one-click container runtime install / health checks.
- [ ] "Test connection" buttons for MQTT and the detector.
- [ ] Bundled, signed + notarized release `.dmg`.
- [ ] Per-camera object/zone editing in the wizard.
- [ ] Optional CoreML `.mlpackage` detector path (no Python).

## License

MIT — see [LICENSE](LICENSE).
