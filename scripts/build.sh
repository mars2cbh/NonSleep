#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
if [[ -n "${NONSLEEP_VERSION:-}" && ! "$NONSLEEP_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "NONSLEEP_VERSION must be a numeric version such as 0.2.0" >&2
  exit 1
fi
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
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
if [[ -n "${NONSLEEP_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NONSLEEP_VERSION" "$APP_DIR/Contents/Info.plist"
fi
if [[ -n "${NONSLEEP_BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NONSLEEP_BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
fi
swift scripts/icon.swift "$PROJECT_DIR/build"
cp "$PROJECT_DIR/build/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
NONSLEEP_SIGNING_IDENTITY="${NONSLEEP_SIGNING_IDENTITY:--}"
codesign --force --sign "$NONSLEEP_SIGNING_IDENTITY" --identifier dev.nonsleep.helper "$APP_DIR/Contents/MacOS/NonSleepHelper"
codesign --force --sign "$NONSLEEP_SIGNING_IDENTITY" "$APP_DIR"
codesign --verify --strict "$APP_DIR"
echo "Built: $APP_DIR"
