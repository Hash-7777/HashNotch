#!/usr/bin/env bash
#
# Packages "HashNotch.app" into a disk image anyone can download, open, and
# drag into Applications.
#
#   ./scripts/make_dmg.sh                 # writes to ./build/
#   ./scripts/make_dmg.sh ~/Desktop       # writes there instead
#
# The app is built first, so the image can never contain a stale binary — that
# is the whole failure this wraps up: `swift build` does not touch the bundle,
# and the bundle is what gets shipped.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$ROOT/build}"
APP="$ROOT/build/HashNotch.app"
VOLUME="HashNotch"

# Version comes from the bundle rather than being typed here, so the file name
# can never disagree with what is inside it.
"$ROOT/scripts/build_app.sh"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
# A hyphen, not a space. GitHub rewrites every space in a release asset's name
# to a dot as the file is uploaded, so an image built as "HashNotch 1.2.0.dmg"
# is offered for download as "HashNotch.1.2.0.dmg" — and any instruction that
# names the file as it was built is then wrong at the one moment it is read.
# Without a space, what is built and what is downloaded are the same string.
DMG="$OUT_DIR/HashNotch-$VERSION.dmg"

mkdir -p "$OUT_DIR"

# Staged in a temp folder so nothing but the app and the drop target ends up on
# the image — no .DS_Store from the build folder, no stray files.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
# The drag-to-install target. A plain symlink is enough; it shows as the
# Applications folder once mounted.
ln -s /Applications "$STAGE/Applications"
# Travelling alongside, so the terms are readable without mounting the app.
cp "$ROOT/LICENSE" "$STAGE/LICENSE.txt"

echo "Building disk image…"
rm -f "$DMG"
hdiutil create \
  -volname "$VOLUME" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG" >/dev/null

# Verify by mounting it and checking the app inside, not by trusting that
# hdiutil exited zero. A disk image that mounts to a broken bundle is the one
# failure that reaches every single person who downloads it.
echo "Verifying…"
hdiutil verify "$DMG" >/dev/null
MOUNT="$(mktemp -d)"
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" >/dev/null
if ! codesign --verify --strict "$MOUNT/HashNotch.app"; then
  hdiutil detach "$MOUNT" >/dev/null || true
  rm -rf "$MOUNT"
  echo "The app inside the image does not verify — do not ship this." >&2
  exit 1
fi
hdiutil detach "$MOUNT" >/dev/null
rm -rf "$MOUNT"

echo "Signature inside the image verified."
echo "Built: $DMG"
echo "Size:  $(du -h "$DMG" | cut -f1)"
