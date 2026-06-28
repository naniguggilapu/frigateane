#!/bin/bash
# Provision a PORTABLE detector engine: download a relocatable CPython
# (python-build-standalone), install deps into it, and ensure a YOLO model.
# The result runs on any Apple-Silicon Mac without Homebrew/system Python.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$ROOT/engine"
PYDIR="$ENGINE/python"            # bundled relocatable interpreter
MODELS="$ENGINE/models"
PYBIN="$PYDIR/bin/python3"

mkdir -p "$ENGINE" "$MODELS"

if [ ! -x "$PYBIN" ]; then
  echo "Fetching relocatable CPython (python-build-standalone)…"
  # Pinned, known-good build (reproducible). Override with PYSTANDALONE_URL.
  URL="${PYSTANDALONE_URL:-https://github.com/astral-sh/python-build-standalone/releases/download/20260623/cpython-3.13.14+20260623-aarch64-apple-darwin-install_only.tar.gz}"
  # If the pinned asset is gone, fall back to the latest release's matching asset.
  if ! curl -fsI "$URL" >/dev/null 2>&1; then
    echo "  pinned URL unavailable; querying latest release…"
    API="https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest"
    URL="$(curl -fsSL "$API" 2>/dev/null \
          | grep -oE 'https://[^\"]*cpython-3\.13\.[0-9]+\+[0-9]+-aarch64-apple-darwin-install_only\.tar\.gz' \
          | head -1 || true)"
  fi
  test -n "${URL:-}" || { echo "ERROR: could not resolve a CPython download URL"; exit 1; }
  echo "  $URL"
  TMP="$(mktemp -d)"
  curl -fL "$URL" -o "$TMP/python.tar.gz"
  tar -xzf "$TMP/python.tar.gz" -C "$ENGINE"   # extracts a top-level ./python/
  rm -rf "$TMP"
  test -x "$PYBIN" || { echo "ERROR: standalone python not found after extract"; exit 1; }
fi

echo "Using bundled python: $("$PYBIN" --version 2>&1)"
"$PYBIN" -m pip install --upgrade pip >/dev/null
"$PYBIN" -m pip install -r "$ENGINE/requirements.txt"

if ! ls "$MODELS"/*.onnx >/dev/null 2>&1; then
  echo "No YOLO .onnx in $MODELS — exporting yolov8n (320) via ultralytics…"
  if "$PYBIN" -m pip install ultralytics >/dev/null 2>&1; then
    ( cd "$MODELS" && "$PYBIN" - <<'PY'
from ultralytics import YOLO
import os, glob
YOLO("yolov8n.pt").export(format="onnx", imgsz=320, opset=13)
for f in glob.glob("*.onnx"):
    if "yolo" in f:
        os.replace(f, "yolo.onnx"); break
print("exported yolo.onnx")
PY
    ) || echo "Export failed — place a YOLO .onnx named yolo.onnx into $MODELS."
  else
    echo "Could not install ultralytics — place a YOLO .onnx named yolo.onnx into $MODELS."
  fi
fi
echo "Engine provisioned (portable)."
