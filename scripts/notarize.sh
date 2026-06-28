#!/bin/bash
# Sign (Developer ID + hardened runtime), notarize, and staple the app + DMG.
#
# Prerequisites (one-time):
#   1. Apple Developer Program membership.
#   2. A "Developer ID Application" certificate in your login keychain
#      (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ +).
#   3. A notarytool credential profile:
#        xcrun notarytool store-credentials FrigateANE \
#          --apple-id you@example.com --team-id ABCDE12345 \
#          --password <app-specific-password>
#
# Usage:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE=FrigateANE \
#   bash scripts/notarize.sh [path/to/App.app] [out.dmg]
set -euo pipefail

APP="${1:-$HOME/Applications/FrigateANEDetector.app}"
OUT_DMG="${2:-$HOME/Desktop/FrigateANEDetector-signed.dmg}"
PROFILE="${NOTARY_PROFILE:-FrigateANE}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENT="$ROOT/Resources/entitlements.plist"
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your 'Developer ID Application: Name (TEAMID)'}"

echo "== signing nested code (inside-out) =="
# 1) every dylib / python extension module
find "$APP/Contents/Resources" -type f \( -name '*.dylib' -o -name '*.so' \) -print0 \
  | while IFS= read -r -d '' f; do
      codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$f"
    done
# 2) any other nested Mach-O executables (e.g. the bundled python binaries)
find "$APP/Contents/Resources/engine/python" -type f -perm -111 -print0 \
  | while IFS= read -r -d '' f; do
      if file "$f" | grep -q 'Mach-O'; then
        codesign --force --options runtime --timestamp --entitlements "$ENT" --sign "$SIGN_IDENTITY" "$f" || true
      fi
    done
# 3) main executable + the app bundle
codesign --force --options runtime --timestamp --entitlements "$ENT" --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/FrigateDetector"
codesign --force --options runtime --timestamp --entitlements "$ENT" --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "== building DMG =="
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT_DMG"
hdiutil create -volname "Frigate ANE Detector" -srcfolder "$STAGE" -format UDZO -ov "$OUT_DMG"
rm -rf "$STAGE"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$OUT_DMG"

echo "== submitting to notarytool (this can take a few minutes) =="
xcrun notarytool submit "$OUT_DMG" --keychain-profile "$PROFILE" --wait

echo "== stapling =="
xcrun stapler staple "$APP"
xcrun stapler staple "$OUT_DMG"
spctl -a -vvv --type install "$OUT_DMG" || true
echo "Done -> $OUT_DMG (notarized + stapled)"
