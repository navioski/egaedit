#!/bin/sh
# Build the native macOS app into "EGA Edit.app" next to this script.
set -e
cd "$(dirname "$0")"

APP="EGA Edit.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 Sources/*.swift -o "$APP/Contents/MacOS/EGAEdit"

cp Resources/glyphs.bin "$APP/Contents/Resources/"
cp Resources/glyphs.json "$APP/Contents/Resources/"
cp Resources/WELCOME.TXT "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "built $APP"
