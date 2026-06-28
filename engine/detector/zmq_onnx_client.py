#!/usr/bin/env python3
"""Frigate ZMQ detector server — runs YOLO ONNX on Apple Silicon (CoreML / ANE).

Implements Frigate's zmq_ipc REQ/REP protocol:
  1. Model request:  [{"model_request": true, "model_name": "<name>"}]
       -> reply [{"model_available": bool, "model_loaded": bool}]
  2. Model transfer: [{"model_data": true, "model_name": "<name>"}, <bytes>]
       -> reply [{"model_saved": bool, "model_loaded": bool}]
  3. Inference:      [{"shape": [...], "dtype": "...", "model_type": "..."}, <tensor>]
       -> reply [{"shape": [20,6], "dtype": "float32"}, <bytes>]
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import time
from pathlib import Path

import numpy as np
import onnxruntime as ort
import zmq

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger("frigate-detector")

MODELS_DIR = Path(__file__).resolve().parent.parent / "models"
MODELS_DIR.mkdir(parents=True, exist_ok=True)


def pick_providers(prefer_coreml: bool) -> list:
    """Return ORT providers list — CoreML (ANE) first if requested."""
    avail = ort.get_available_providers()
    log.info("ORT available providers: %s", avail)
    out = []
    if prefer_coreml and "CoreMLExecutionProvider" in avail:
        cache_dir = str(MODELS_DIR / "coreml_cache")
        os.makedirs(cache_dir, exist_ok=True)
        out.append(
            (
                "CoreMLExecutionProvider",
                {
                    "ModelFormat": "NeuralNetwork",
                    "MLComputeUnits": "CPUAndNeuralEngine",
                    "RequireStaticInputShapes": "1",
                    "EnableOnSubgraphs": "1",
                    "ModelCacheDirectory": cache_dir,
                },
            )
        )
    out.append("CPUExecutionProvider")
    return out


class Detector:
    def __init__(self, models_dir: Path, prefer_coreml: bool):
        self.models_dir = models_dir
        self.prefer_coreml = prefer_coreml
        self.model_name = None
        self.session = None
        self.input_name = None

    def load(self, model_name: str) -> bool:
        path = self.models_dir / model_name
        if not path.is_file():
            log.warning("Model file missing: %s", path)
            return False
        try:
            providers = pick_providers(self.prefer_coreml)
            t0 = time.time()
            so = ort.SessionOptions()
            if os.environ.get("ORT_VERBOSE") == "1":
                so.log_severity_level = 0
            self.session = ort.InferenceSession(str(path), sess_options=so, providers=providers)
            self.input_name = self.session.get_inputs()[0].name
            self.model_name = model_name
            log.info("Loaded %s in %.1fs using %s", model_name, time.time() - t0, self.session.get_providers())
            return True
        except Exception as e:
            log.exception("Model load failed: %s", e)
            self.session = None
            return False

    def is_loaded(self, model_name: str) -> bool:
        return self.session is not None and self.model_name == model_name

    def infer(self, tensor: np.ndarray):
        assert self.session is not None
        return self.session.run(None, {self.input_name: tensor})


def nms_numpy(boxes: np.ndarray, scores: np.ndarray, iou_thresh: float) -> list:
    if len(boxes) == 0:
        return []
    x1, y1, x2, y2 = boxes[:, 0], boxes[:, 1], boxes[:, 2], boxes[:, 3]
    areas = (x2 - x1) * (y2 - y1)
    order = scores.argsort()[::-1]
    keep = []
    while order.size > 0:
        i = order[0]
        keep.append(i)
        if order.size == 1:
            break
        xx1 = np.maximum(x1[i], x1[order[1:]])
        yy1 = np.maximum(y1[i], y1[order[1:]])
        xx2 = np.minimum(x2[i], x2[order[1:]])
        yy2 = np.minimum(y2[i], y2[order[1:]])
        w = np.maximum(0.0, xx2 - xx1)
        h = np.maximum(0.0, yy2 - yy1)
        inter = w * h
        iou = inter / (areas[i] + areas[order[1:]] - inter + 1e-9)
        inds = np.where(iou <= iou_thresh)[0]
        order = order[inds + 1]
    return keep


def post_process_yolo_single(output, width, height, score_thresh=0.4, iou_thresh=0.4):
    pred = np.squeeze(output)
    if pred.shape[0] < pred.shape[1]:
        pred = pred.T
    scores = np.max(pred[:, 4:], axis=1)
    keep = scores > score_thresh
    pred = pred[keep]
    scores = scores[keep]
    detections = np.zeros((20, 6), np.float32)
    if pred.size == 0:
        return detections
    class_ids = np.argmax(pred[:, 4:], axis=1)
    boxes = pred[:, :4]
    boxes_xyxy = np.empty_like(boxes)
    boxes_xyxy[:, 0] = boxes[:, 0] - boxes[:, 2] / 2
    boxes_xyxy[:, 1] = boxes[:, 1] - boxes[:, 3] / 2
    boxes_xyxy[:, 2] = boxes[:, 0] + boxes[:, 2] / 2
    boxes_xyxy[:, 3] = boxes[:, 1] + boxes[:, 3] / 2
    idx = nms_numpy(boxes_xyxy, scores, iou_thresh)
    for i, k in enumerate(idx[:20]):
        b = boxes_xyxy[k]
        detections[i] = [class_ids[k], scores[k], b[1] / height, b[0] / width, b[3] / height, b[2] / width]
    return detections


def handle_request(det: Detector, frames: list) -> list:
    try:
        header = json.loads(frames[0].decode("utf-8"))
    except Exception:
        log.warning("Bad header frame")
        return [json.dumps({"error": "bad header"}).encode()]

    if header.get("model_request"):
        name = header.get("model_name", "")
        path = det.models_dir / name
        avail = path.is_file()
        if avail and not det.is_loaded(name):
            det.load(name)
        loaded = det.is_loaded(name)
        log.info("model_request name=%s avail=%s loaded=%s", name, avail, loaded)
        return [json.dumps({"model_available": avail, "model_loaded": loaded}).encode()]

    if header.get("model_data"):
        name = header.get("model_name", "model.onnx")
        if len(frames) < 2:
            return [json.dumps({"model_saved": False, "model_loaded": False}).encode()]
        path = det.models_dir / name
        try:
            with open(path, "wb") as f:
                f.write(frames[1])
            saved = True
            log.info("Saved model %s (%d bytes)", name, len(frames[1]))
        except Exception as e:
            log.exception("Save failed: %s", e)
            saved = False
        loaded = det.load(name) if saved else False
        return [json.dumps({"model_saved": saved, "model_loaded": loaded}).encode()]

    if not det.session:
        log.warning("Inference requested but no model loaded")
        return [np.zeros((20, 6), np.float32).tobytes()]
    try:
        shape = header.get("shape")
        dtype = header.get("dtype", "float32")
        tensor = np.frombuffer(frames[1], dtype=np.dtype(dtype)).reshape(shape)
        in_dtype = det.session.get_inputs()[0].type
        if "float" in in_dtype and tensor.dtype != np.float32:
            tensor = tensor.astype(np.float32) / 255.0
        out = det.infer(tensor)
        in_shape = det.session.get_inputs()[0].shape
        w = int(in_shape[3]) if isinstance(in_shape[3], int) else tensor.shape[3]
        h = int(in_shape[2]) if isinstance(in_shape[2], int) else tensor.shape[2]
        detections = post_process_yolo_single(out[0], w, h)
        return [detections.tobytes()]
    except Exception as e:
        log.exception("Inference error: %s", e)
        return [np.zeros((20, 6), np.float32).tobytes()]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--endpoint", default="tcp://0.0.0.0:5555")
    p.add_argument("--model", default="AUTO")
    p.add_argument("--no-coreml", action="store_true")
    p.add_argument("--selftest", action="store_true", help="load model, run one dummy inference, print result, exit")
    args = p.parse_args()

    det = Detector(MODELS_DIR, prefer_coreml=not args.no_coreml)
    if args.model and args.model != "AUTO":
        det.load(args.model)
    else:
        for f in sorted(MODELS_DIR.glob("*.onnx")):
            det.load(f.name)
            break

    if args.selftest:
        if det.session is None:
            print("SELFTEST FAIL: no model loaded")
            sys.exit(2)
        shape = det.session.get_inputs()[0].shape
        dims = [int(d) if isinstance(d, int) else 1 for d in shape]
        if len(dims) == 4:
            dims = [1, dims[1] if dims[1] else 3, dims[2] if dims[2] else 320, dims[3] if dims[3] else 320]
        x = np.random.rand(*dims).astype(np.float32)
        # warmup + timed
        det.infer(x)
        t0 = time.time()
        out = det.infer(x)
        ms = (time.time() - t0) * 1000.0
        providers = det.session.get_providers()
        ane = "CoreMLExecutionProvider" in providers
        print(f"SELFTEST OK model={det.model_name} providers={providers} ane={ane} "
              f"latency_ms={ms:.1f} out_shape={list(np.shape(out[0]))}")
        sys.exit(0)

    ctx = zmq.Context.instance()
    sock = ctx.socket(zmq.REP)
    sock.bind(args.endpoint)
    log.info("ZMQ REP listening on %s", args.endpoint)

    infer_count = 0
    last_log = time.time()
    while True:
        try:
            frames = sock.recv_multipart()
            reply = handle_request(det, frames)
            sock.send_multipart(reply)
            if len(reply) == 1 and len(reply[0]) == 480:
                infer_count += 1
                now = time.time()
                if now - last_log >= 30:
                    log.info("inferences in last %.0fs: %d", now - last_log, infer_count)
                    infer_count = 0
                    last_log = now
        except KeyboardInterrupt:
            break
        except Exception as e:
            log.exception("Loop error: %s", e)
            try:
                sock.send_multipart([json.dumps({"error": str(e)}).encode()])
            except Exception:
                pass


if __name__ == "__main__":
    main()
