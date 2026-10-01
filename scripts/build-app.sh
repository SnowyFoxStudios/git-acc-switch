#!/bin/bash
# Builds GitAccountSwitch.app into ./build. With --install, copies it to ~/Applications and launches it.
# Optional env: VERSION (e.g. 0.1.0) and BUILD_NUMBER override the ones in Resources/Info.plist.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/GitAccountSwitch"

APP=build/GitAccountSwitch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GitAccountSwitch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# CI passes the release version (from the tag) and build number; local builds keep Info.plist's.
[[ -n "${VERSION:-}" ]] && /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
[[ -n "${BUILD_NUMBER:-}" ]] && /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  DEST="$HOME/Applications/GitAccountSwitch.app"
  pkill -x GitAccountSwitch 2>/dev/null || true
  # Before the rename the app was GhAccSwitch.app; drop it so only one copy is installed.
  pkill -x GhAccSwitch 2>/dev/null || true
  rm -rf "$HOME/Applications/GhAccSwitch.app"
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  open "$DEST"
  echo "Installed and launched $DEST"
fi
