#!/bin/bash
# Builds "Eye Care.app" into ./build.
#   ./build.sh            build only
#   ./build.sh --run      build and launch
#   ./build.sh --install  build, copy to /Applications and launch
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Eye Care.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/EyeCare"

if [ ! -f build/AppIcon.icns ]; then
    mkdir -p build
    swift scripts/make-icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
    rm -rf build/AppIcon.iconset
fi

pkill -x EyeCare 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/EyeCare"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
echo "Built $APP"

case "${1:-}" in
    --run)
        open "$APP" ;;
    --install)
        rm -rf "/Applications/Eye Care.app"
        cp -R "$APP" /Applications/
        open "/Applications/Eye Care.app"
        echo "Installed to /Applications/Eye Care.app" ;;
esac
