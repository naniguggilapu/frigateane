#!/bin/bash
# Build FrigateANEDetector.app (arm64) from source.
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$HOME/Applications/FrigateANEDetector.app}"
ENGINE="$ROOT/engine"

echo "=== [1/5] provisioning engine (venv + deps + model) ==="
# Reuse a prebuilt engine if present (fast path), else provision from scratch.
PREBUILT="$HOME/frigate/FrigateDetector.app/Contents/Resources/app"
if [ ! -x "$ENGINE/venv/bin/python3" ] && [ -x "$PREBUILT/venv/bin/python3" ]; then
  echo "Reusing prebuilt engine from $PREBUILT"
  mkdir -p "$ENGINE"
  cp -R "$PREBUILT/venv" "$ENGINE/venv"
  [ -d "$PREBUILT/models" ] && cp -R "$PREBUILT/models" "$ENGINE/models"
else
  bash "$ROOT/scripts/provision_engine.sh"
fi

echo "=== [2/5] compiling Swift (arm64, Swift 5 mode) ==="
mkdir -p "$ROOT/build"
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
  "$ROOT"/Sources/*.swift \
  -framework AppKit -framework Foundation \
  -o "$ROOT/build/FrigateDetector"
file "$ROOT/build/FrigateDetector"

echo "=== [3/5] assembling .app ==="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/engine"
cp "$ROOT/build/FrigateDetector" "$APP/Contents/MacOS/FrigateDetector"
chmod +x "$APP/Contents/MacOS/FrigateDetector"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "=== [4/5] bundling engine ==="
cp -R "$ENGINE/detector" "$APP/Contents/Resources/engine/detector"
cp -R "$ENGINE/models"   "$APP/Contents/Resources/engine/models"
cp -R "$ENGINE/venv"     "$APP/Contents/Resources/engine/venv"

echo "=== [5/5] ad-hoc sign ==="
find "$APP" -name '.DS_Store' -delete 2>/dev/null || true
xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign - "$APP/Contents/MacOS/FrigateDetector" 2>&1 | tail -1 || true

echo "DONE -> $APP"
du -sh "$APP"
