#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Lepora"
VERSION="${1:-1.0.0}"
ARCH="arm64"
APP_BUNDLE="$ROOT_DIR/build/Release/$APP_NAME.app"
DMG_NAME="${APP_NAME}-${VERSION}-${ARCH}.dmg"
DMG_OUTPUT="$ROOT_DIR/build/$DMG_NAME"
STAGING_DIR="$ROOT_DIR/build/dmg_staging"
TMP_DMG="$ROOT_DIR/build/${APP_NAME}-tmp.dmg"

echo "==> Packaging $DMG_NAME..."

# 1. Ensure fresh Release app bundle exists
if [ ! -d "$APP_BUNDLE" ]; then
  "$ROOT_DIR/scripts/build_app.sh" Release
fi

# 2. Prepare clean staging folder with Lepora.app + /Applications symlink
rm -rf "$STAGING_DIR" "$TMP_DMG" "$DMG_OUTPUT"
mkdir -p "$STAGING_DIR"
ditto --norsrc "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

# Strip any macOS provenance/Finder xattrs, re-sign cleanly, and verify strictly
xattr -cr "$STAGING_DIR/$APP_NAME.app"
codesign --force --deep --sign - "$STAGING_DIR/$APP_NAME.app"
codesign --verify --deep --strict "$STAGING_DIR/$APP_NAME.app"

# 3. Create temporary read-write DMG
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDRW \
  "$TMP_DMG" >/dev/null

# 4. Mount temporarily to attach volume icon cleanly
MOUNT_POINT="/Volumes/$APP_NAME"
if [ -d "$MOUNT_POINT" ]; then
  hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
fi

ATTACH_OUT="$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG")"
DEVICE="$(echo "$ATTACH_OUT" | awk '/\/Volumes\// {print $1; exit}')"
VOL_PATH="$(echo "$ATTACH_OUT" | sed -n 's/.*\(\/Volumes\/.*\)/\1/p' | head -n 1)"

if [ -n "${VOL_PATH:-}" ] && [ -d "$VOL_PATH" ]; then
  if [ -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns" ]; then
    cp "$APP_BUNDLE/Contents/Resources/AppIcon.icns" "$VOL_PATH/.VolumeIcon.icns"
    SetFile -a C "$VOL_PATH" 2>/dev/null || true
  fi
  sync
  sleep 1
  hdiutil detach "$DEVICE" >/dev/null 2>&1 || hdiutil detach "$VOL_PATH" -force >/dev/null 2>&1
fi

# 5. Convert to compressed read-only UDZO DMG
hdiutil convert "$TMP_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "$DMG_OUTPUT" >/dev/null

# 6. Cleanup & verify final DMG
rm -rf "$STAGING_DIR" "$TMP_DMG"
hdiutil verify "$DMG_OUTPUT" >/dev/null
SHA256="$(shasum -a 256 "$DMG_OUTPUT" | awk '{print $1}')"
SIZE="$(du -h "$DMG_OUTPUT" | awk '{print $1}')"

echo "==> DMG ready: $DMG_OUTPUT ($SIZE)"
echo "==> SHA256:    $SHA256"
