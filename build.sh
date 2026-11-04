#!/bin/bash
# Builds FlipCalendar.saver (Apple Silicon + Intel). Needs only the Xcode Command Line Tools:
#   xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"
NAME=FlipCalendar
OUT="build/$NAME.saver"
rm -rf build
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
for ARCH in arm64 x86_64; do
  swiftc -O -parse-as-library -module-name "$NAME" -target "$ARCH-apple-macos12.0" \
    -emit-library -o "build/$NAME-$ARCH" \
    -framework AppKit -framework ScreenSaver -framework WebKit \
    src/FlipCalendarView.swift
done
lipo -create "build/$NAME-arm64" "build/$NAME-x86_64" -output "$OUT/Contents/MacOS/$NAME"
cp src/Info.plist "$OUT/Contents/Info.plist"
cp web/index.html web/thumbnail.png web/thumbnail@2x.png "$OUT/Contents/Resources/"
codesign --force --deep --sign - "$OUT"
echo "Built $OUT"
echo "Installing (double-click equivalent)…"
killall legacyScreenSaver "legacyScreenSaver (Wallpaper)" 2>/dev/null || true
open "$OUT"
