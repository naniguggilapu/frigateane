# Contributing to Frigate ANE Detector

Thanks for your interest in improving this project! It's MIT-licensed and open to
contributions of all sizes — bug reports, docs, and code.

## Getting set up

Requirements:

- Apple Silicon Mac (M1 or newer).
- macOS 13+ to run the app; macOS 26 + Apple `container` to run Frigate itself.
- Xcode command-line tools (`xcode-select --install`).
- Python 3 (for the detector engine venv).

Build and run:

```bash
git clone git@github.com:naniguggilapu/frigateane.git
cd frigateane
bash scripts/build.sh                  # provisions engine, compiles, assembles the .app
open ~/Applications/FrigateANEDetector.app
```

`scripts/provision_engine.sh` creates the Python venv, installs `onnxruntime` /
`pyzmq` / `numpy`, and exports a `yolo.onnx` model if one isn't present.

## Project layout

| Path | What |
|------|------|
| `Sources/` | Swift app — `Config`, `ConfigGenerator`, `Engine`, `Orchestrator`, `UI`, `main`. |
| `engine/` | Python ZMQ detector (`detector/zmq_onnx_client.py`) + `requirements.txt`. Models/venv are gitignored. |
| `networking/` | `pf` NAT rules + LaunchDaemon template for container ↔ LAN. |
| `scripts/` | `build.sh`, `provision_engine.sh`. |
| `Resources/` | `Info.plist` for the app bundle. |
| `test/` | Headless harness for the config generator. |

## Code style

- Swift: programmatic AppKit (no storyboards/XIBs), `-swift-version 5`. Keep UI building
  in small helper functions; keep side-effecting shell calls in `Orchestrator`/`Shell`.
- Python: standard library + the three deps; keep the Frigate ZMQ protocol intact.
- No secrets in the repo. User config lives in `~/Library/Application Support/FrigateANE/`.

## Pull requests

1. Branch from `main`.
2. Make focused changes with a clear description.
3. Note how you tested (the app launches, config generates, etc.). End-to-end Frigate
   testing needs a macOS 26 + Apple `container` host — mention if you couldn't run it.
4. By contributing, you agree your work is licensed under the project's MIT license.

## Reporting issues

Open a GitHub issue with: macOS version, Mac model (chip), what you did, what happened,
and any relevant log output from the app's dashboard.
