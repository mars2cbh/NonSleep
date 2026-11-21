#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
SOURCE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :NonSleepReleaseVersion' Resources/Info.plist)"
VERSION_INFO="$(python3 scripts/calver.py "${NONSLEEP_VERSION:-$SOURCE_VERSION}")"
read -r RELEASE_VERSION APP_VERSION <<< "$VERSION_INFO"
if [[ -n "${NONSLEEP_BUILD_NUMBER:-}" && ! "$NONSLEEP_BUILD_NUMBER" =~ '^[0-9]+$' ]]; then
  echo "NONSLEEP_BUILD_NUMBER must be an integer" >&2
  exit 1
fi
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/module-cache"
BUILD_OPTIONS=(-c release --disable-sandbox --cache-path "$PROJECT_DIR/.build/cache" --config-path "$PROJECT_DIR/.build/config" --security-path "$PROJECT_DIR/.build/security" -debug-info-format none)
swift build "${BUILD_OPTIONS[@]}"
BINARY_DIR="$(swift build "${BUILD_OPTIONS[@]}" --show-bin-path)"
APP_DIR="${NONSLEEP_APP_DIR:-$PROJECT_DIR/build/NonSleep.app}"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY_DIR/NonSleep" "$APP_DIR/Contents/MacOS/NonSleep"
cp "$BINARY_DIR/NonSleepHelper" "$APP_DIR/Contents/MacOS/NonSleepHelper"
cp Resources/Sparkle-LICENSE.txt "$APP_DIR/Contents/Resources/Sparkle-LICENSE.txt"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :NonSleepReleaseVersion $RELEASE_VERSION" "$APP_DIR/Contents/Info.plist"
if [[ -n "${NONSLEEP_BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NONSLEEP_BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
fi
swift scripts/icon.swift "$PROJECT_DIR/build"
cp "$PROJECT_DIR/build/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
# Preserve Sparkle's framework symlinks, installer and XPC services.
SPARKLE_FRAMEWORK="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
mkdir -p "$APP_DIR/Contents/Frameworks"
ditto "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
NONSLEEP_SIGNING_IDENTITY="${NONSLEEP_SIGNING_IDENTITY:--}"
codesign --force --sign "$NONSLEEP_SIGNING_IDENTITY" --identifier dev.nonsleep.helper "$APP_DIR/Contents/MacOS/NonSleepHelper"
SPARKLE_VERSION_DIR="$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign --force --preserve-metadata=identifier,entitlements,flags,runtime --sign "$NONSLEEP_SIGNING_IDENTITY" "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc"
codesign --force --preserve-metadata=identifier,entitlements,flags,runtime --sign "$NONSLEEP_SIGNING_IDENTITY" "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
codesign --force --preserve-metadata=identifier,entitlements,flags,runtime --sign "$NONSLEEP_SIGNING_IDENTITY" "$SPARKLE_VERSION_DIR/Autoupdate"
codesign --force --preserve-metadata=identifier,entitlements,flags,runtime --sign "$NONSLEEP_SIGNING_IDENTITY" "$SPARKLE_VERSION_DIR/Updater.app"
codesign --force --preserve-metadata=identifier,entitlements,flags,runtime --sign "$NONSLEEP_SIGNING_IDENTITY" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$NONSLEEP_SIGNING_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "Built: $APP_DIR"
