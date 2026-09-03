#!/bin/bash
# Builds XDRGamma.app from the SwiftPM binary.
set -euo pipefail

cd "$(dirname "$0")"
APP="XDRGamma.app"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/XDRGamma "$APP/Contents/MacOS/XDRGamma"

# Icon. Regenerate with ./make-icon.swift if AppIcon.icns is ever missing.
if [ -f AppIcon.icns ]; then
    cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
    echo "warning: AppIcon.icns missing, building without an icon" >&2
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>XDRGamma</string>
    <key>CFBundleDisplayName</key>     <string>XDR Gamma</string>
    <key>CFBundleIdentifier</key>      <string>app.xdrgamma</string>
    <key>CFBundleExecutable</key>      <string>XDRGamma</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundleIconName</key>        <string>AppIcon</string>
    <!-- Menu bar only, no Dock icon -->
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: without one macOS will not give the app a stable identity.
codesign --force --deep --sign - "$APP"

echo "Done: $(pwd)/$APP"
