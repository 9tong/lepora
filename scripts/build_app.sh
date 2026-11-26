#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-Release}"
APP_NAME="Lepora"
BUILD_DIR="$ROOT_DIR/build/$CONFIG"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"
SDK="$(xcrun --show-sdk-path)"
ICON_BUNDLE="$ROOT_DIR/Lepora/Resources/AppIcon.icon"
ICTOOL="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"

echo "==> Building $APP_NAME ($CONFIG) with macOS SDK $(xcrun --show-sdk-version)..."

# 1. Ensure EditorBundle exists
if [ ! -f "$ROOT_DIR/Lepora/Resources/EditorBundle/index.html" ]; then
  echo "==> Building EditorEngine offline bundle..."
  (cd "$ROOT_DIR/EditorEngine" && npm run build)
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RES_DIR"

# 2. Compile Swift 6 native macOS executable
SWIFT_FLAGS=(-target arm64-apple-macosx26.0 -sdk "$SDK" -swift-version 6 -parse-as-library)
if [ "$CONFIG" = "Release" ]; then
  SWIFT_FLAGS+=(-O)
else
  SWIFT_FLAGS+=(-Onone -g)
fi

SWIFT_FILES=()
while IFS= read -r -d '' file; do
  SWIFT_FILES+=("$file")
done < <(find "$ROOT_DIR/Lepora" -name "*.swift" -print0)

echo "==> Compiling ${#SWIFT_FILES[@]} Swift source files..."
swiftc "${SWIFT_FLAGS[@]}" \
  -framework SwiftUI \
  -framework AppKit \
  -framework WebKit \
  -framework UniformTypeIdentifiers \
  "${SWIFT_FILES[@]}" \
  -o "$MACOS_DIR/$APP_NAME"

# 3. Compile native macOS 26/27 Liquid Glass AppIcon.icon -> Assets.car + AppIcon.icns
if [ -d "$ICON_BUNDLE" ]; then
  echo "==> Compiling Liquid Glass AppIcon.icon (Light & Dark)..."
  PARTIAL_PLIST="$(mktemp)"
  xcrun actool \
    --compile "$RES_DIR" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$PARTIAL_PLIST" \
    "$ICON_BUNDLE" >/dev/null
  rm -f "$PARTIAL_PLIST"

  # Export crisp runtime Dock icons for explicit in-app Light/Dark theme overrides
  if [ -x "$ICTOOL" ]; then
    "$ICTOOL" "$ICON_BUNDLE" --export-image --output-file "$RES_DIR/DockIconLight.png" \
      --platform macOS --rendition Default --width 512 --height 512 --scale 1 >/dev/null 2>&1 || true
    "$ICTOOL" "$ICON_BUNDLE" --export-image --output-file "$RES_DIR/DockIconDark.png" \
      --platform macOS --rendition Dark --width 512 --height 512 --scale 1 >/dev/null 2>&1 || true
  fi
else
  ICONSET_TMP="$BUILD_DIR/AppIcon.iconset"
  rm -rf "$ICONSET_TMP"
  cp -R "$ROOT_DIR/Lepora/Resources/Assets.xcassets/AppIcon.appiconset" "$ICONSET_TMP"
  rm -f "$ICONSET_TMP/Contents.json"
  iconutil -c icns "$ICONSET_TMP" -o "$RES_DIR/AppIcon.icns"
  rm -rf "$ICONSET_TMP"
fi

# 4. Copy compiled offline EditorBundle & Retina floating feather assets
cp -R "$ROOT_DIR/Lepora/Resources/EditorBundle" "$RES_DIR/EditorBundle"
for feather in FloatingFeatherLight.png FloatingFeatherDark.png; do
  if [ -f "$ROOT_DIR/Lepora/Resources/$feather" ]; then
    cp "$ROOT_DIR/Lepora/Resources/$feather" "$RES_DIR/$feather"
  fi
done

# 5. Copy Info.plist & configure bundle icon metadata
cp "$ROOT_DIR/Lepora/Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$CONTENTS/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$CONTENTS/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconName AppIcon" "$CONTENTS/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundlePackageType APPL" "$CONTENTS/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleInfoDictionaryVersion 6.0" "$CONTENTS/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDevelopmentRegion zh-Hans" "$CONTENTS/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string zh-Hans" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :NSHighResolutionCapable true" "$CONTENTS/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$CONTENTS/Info.plist"

printf 'APPL????' > "$CONTENTS/PkgInfo"

# 6. Strip Finder/iCloud FileProvider xattrs, sign & strictly verify in /tmp (outside iCloud)
TMP_CLEAN="$(mktemp -d /tmp/lepora-build-sign.XXXXXX)"
trap 'rm -rf "$TMP_CLEAN"' EXIT
ditto --norsrc "$APP_BUNDLE" "$TMP_CLEAN/$APP_NAME.app"
xattr -cr "$TMP_CLEAN/$APP_NAME.app"
codesign --force --deep --sign - "$TMP_CLEAN/$APP_NAME.app"
codesign --verify --deep --strict "$TMP_CLEAN/$APP_NAME.app"
rm -rf "$APP_BUNDLE"
ditto --norsrc "$TMP_CLEAN/$APP_NAME.app" "$APP_BUNDLE"

echo "==> Built & signed: $APP_BUNDLE"
