# Credits & upstream licenses

This project is a native macOS app built on top of prior community work. The original
manual approach — running a YOLO ONNX model on the Apple Neural Engine via a ZMQ server
that Frigate (in Apple's `container` runtime) connects to — comes from the projects below.
Both are MIT-licensed; their notices are preserved here as required.

---

## frigate-nvr/apple-silicon-detector

A Frigate detector that leverages Apple Silicon (the Neural Engine, via CoreML).
The bundled detector engine in `engine/detector/` is derived from this project.

- Repository: https://github.com/frigate-nvr/apple-silicon-detector
- License: MIT

```
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the above copyright notice and this permission
notice being included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
```

(See the upstream repository for its full copyright line and LICENSE file.)

---

## harb70 — "Frigate on Apple Container with Apple Silicon detector" how-to

The container launch script, `pf` NAT rules, launchd services, startup/watch scripts,
and config layout that this app automates follow this community guide.

- Guide: https://gist.github.com/harb70/0ca2fa85b70b242575d8c050a2a66ada
- License: MIT (as stated in the guide)

---

## This project's contribution

The native macOS app around the above approach is original work: the AppKit setup
wizard, dashboard, config generator, orchestrator, connection tests (MQTT/RTSP/ANE
self-test), launch-at-login, and portable-Python (python-build-standalone) packaging.
