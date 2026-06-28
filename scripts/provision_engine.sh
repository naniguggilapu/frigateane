#!/bin/bash
# Provision the Python detector engine: create a venv, install deps, ensure a YOLO model.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$ROOT/engine"
VENV="$ENGINE/venv"
MODELS="$ENGINE/models"

PY="${PYTHON:-python3}"
echo "Using python: $($PY --version 2>&1)"

if [ ! -x "$VENV/bin/python3" ]; then
  echo "Creating venv at $VENV"
  "$PY" -m venv "$VENV"
fi
"$VENV/bin/python3" -m pip install --upgrade pip >/dev/null
"$VENV/bin/python3" -m pip install -r "$ENGINE/requirements.txt"

mkdir -p "$MODELS"
if ! ls "$MODELS"/*.onnx >/dev/null 2>&1; then
  echo "No YOLO .onnx found in $MODELS."
  echo "Attempting to export yolov8n -> onnx (320x320) via ultralytics…"
  if "$VENV/bin/python3" -m pip install ultralytics >/dev/null 2>&1; then
    ( cd "$MODELS" && "$VENV/bin/python3" - <<'PY'
from ultralytics import YOLO
m = YOLO("yolov8n.pt")
m.export(format="onnx", imgsz=320, opset=13)
import os, glob
for f in glob.glob("*.onnx"):
    if "yolo" in f:
        os.replace(f, "yolo.onnx")
        break
print("exported yolo.onnx")
PY
    ) || echo "Export failed — place a YOLO .onnx (named yolo.onnx) into $MODELS manually."
  else
    echo "Could not install ultralytics — place a YOLO .onnx (named yolo.onnx) into $MODELS manually."
  fi
fi
echo "Engine provisioned."
