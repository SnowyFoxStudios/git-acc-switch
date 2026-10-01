#!/bin/bash
# Builds GitAccountSwitch.app into ./build. With --install, copies it to ~/Applications and launches it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/GitAccountSwitch"

APP=build/GitAccountSwitch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GitAccountSwitch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
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
