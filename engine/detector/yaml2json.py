#!/usr/bin/env python3
# Convert a Frigate config.yaml to JSON so the app can import an existing setup.
import sys, json
try:
    import yaml
except Exception:
    print("{}"); sys.exit(0)
try:
    with open(sys.argv[1]) as f:
        data = yaml.safe_load(f) or {}
    print(json.dumps(data))
except Exception:
    print("{}")
