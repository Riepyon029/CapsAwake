#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="${1:-$PROJECT_DIR/dist}"
BUILD_DIR="$PROJECT_DIR/.build"
APP_DIR="$DEST_DIR/Caps Awake.app"
mkdir -p "$BUILD_DIR" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
for ARCH in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -parse-as-library -sdk "$SDK_PATH" -target "$ARCH-apple-macosx14.0" \
    "$PROJECT_DIR/Sources/Shared/Protocol.swift" "$PROJECT_DIR/Sources/Shared/SessionCore.swift" \
    "$PROJECT_DIR/Sources/Helper/main.swift" -framework IOKit -o "$BUILD_DIR/helper-$ARCH"
  xcrun swiftc -swift-version 5 -O -parse-as-library -sdk "$SDK_PATH" -target "$ARCH-apple-macosx14.0" \
    "$PROJECT_DIR/Sources/Shared/Protocol.swift" "$PROJECT_DIR/Sources/App/Model.swift" \
    "$PROJECT_DIR/Sources/App/ContentView.swift" "$PROJECT_DIR/Sources/App/main.swift" \
    -framework AppKit -framework SwiftUI -framework ApplicationServices -o "$BUILD_DIR/app-$ARCH"
done
lipo -create "$BUILD_DIR/helper-arm64" "$BUILD_DIR/helper-x86_64" -output "$APP_DIR/Contents/Resources/CapsAwakeHelper"
lipo -create "$BUILD_DIR/app-arm64" "$BUILD_DIR/app-x86_64" -output "$APP_DIR/Contents/MacOS/CapsAwake"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/Help.html" "$APP_DIR/Contents/Resources/Help.html"
cp "$PROJECT_DIR/Resources/CapsAwakePink.icns" "$APP_DIR/Contents/Resources/CapsAwakePink.icns"
rm -f "$APP_DIR/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP_DIR/Contents/Resources/CapsAwakeHelper"
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
touch "$APP_DIR"
printf 'Built: %s\n' "$APP_DIR"
