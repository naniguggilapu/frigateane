#!/bin/bash
# Build FrigateANEDetector.app (arm64) from source.
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$HOME/Applications/FrigateANEDetector.app}"
ENGINE="$ROOT/engine"

echo "=== [1/5] provisioning portable engine (standalone python + deps + model) ==="
bash "$ROOT/scripts/provision_engine.sh"

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
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "=== [4/5] bundling engine + networking ==="
cp -R "$ENGINE/detector" "$APP/Contents/Resources/engine/detector"
cp -R "$ENGINE/models"   "$APP/Contents/Resources/engine/models"
cp -R "$ENGINE/python"   "$APP/Contents/Resources/engine/python"
mkdir -p "$APP/Contents/Resources/networking"
cp "$ROOT"/networking/* "$APP/Contents/Resources/networking/"

echo "=== [5/5] ad-hoc sign ==="
find "$APP" -name '.DS_Store' -delete 2>/dev/null || true
xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign - "$APP/Contents/MacOS/FrigateDetector" 2>&1 | tail -1 || true

echo "DONE -> $APP"
du -sh "$APP"
