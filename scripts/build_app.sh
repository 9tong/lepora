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

# 3. Compile AppIcon.icns from iconset
ICONSET_TMP="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET_TMP"
cp -R "$ROOT_DIR/Lepora/Resources/Assets.xcassets/AppIcon.appiconset" "$ICONSET_TMP"
rm -f "$ICONSET_TMP/Contents.json"
iconutil -c icns "$ICONSET_TMP" -o "$RES_DIR/AppIcon.icns"
rm -rf "$ICONSET_TMP"

# 4. Copy compiled offline EditorBundle
cp -R "$ROOT_DIR/Lepora/Resources/EditorBundle" "$RES_DIR/EditorBundle"

# 5. Copy Info.plist & expand build variables cleanly
cp "$ROOT_DIR/Lepora/Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$CONTENTS/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundlePackageType APPL" "$CONTENTS/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleInfoDictionaryVersion 6.0" "$CONTENTS/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDevelopmentRegion zh-Hans" "$CONTENTS/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string zh-Hans" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :NSHighResolutionCapable true" "$CONTENTS/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$CONTENTS/Info.plist"

printf 'APPL????' > "$CONTENTS/PkgInfo"

# 6. Strip Finder xattrs and ad-hoc sign cleanly
xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "==> Built & signed: $APP_BUNDLE"
