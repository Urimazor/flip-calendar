#!/bin/bash
# Builds "Flip Calendar Wallpaper.app" into ~/Applications and starts it. Needs the Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Flip Calendar Wallpaper.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for ARCH in arm64 x86_64; do
  swiftc -O -target "$ARCH-apple-macos12.0" -o "build/wallpaper-$ARCH" \
    -framework AppKit -framework WebKit wallpaper/main.swift
done
lipo -create build/wallpaper-arm64 build/wallpaper-x86_64 -output "$APP/Contents/MacOS/FlipCalendarWallpaper"
cp wallpaper/Info.plist "$APP/Contents/Info.plist"
cp web/index.html "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP"
mkdir -p "$HOME/Applications"
pkill -x FlipCalendarWallpaper 2>/dev/null || true
rm -rf "$HOME/Applications/Flip Calendar Wallpaper.app"
cp -R "$APP" "$HOME/Applications/"
open "$HOME/Applications/Flip Calendar Wallpaper.app"
echo "Running. Quit it from the ◷ icon in the menu bar."
echo "To start it automatically: System Settings > General > Login Items > + > ~/Applications/Flip Calendar Wallpaper.app"
