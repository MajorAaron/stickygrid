#!/bin/bash
# Assembles a runnable StickyGrid.app bundle from the Swift package build.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="1.0"
BUNDLE_ID="com.aaronmajor.stickygrid"
APP="build/StickyGrid.app"

swift build -c release --product StickyGrid

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/StickyGrid "$APP/Contents/MacOS/StickyGrid"
printf 'APPL????' > "$APP/Contents/PkgInfo"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>StickyGrid</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>StickyGrid</string>
    <key>CFBundleDisplayName</key>
    <string>StickyGrid</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>${BUNDLE_ID}.capture</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>stickygrid</string>
            </array>
        </dict>
    </array>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
                <string>New Sticky Note from Selection</string>
            </dict>
            <key>NSMessage</key>
            <string>newNoteFromSelection</string>
            <key>NSPortName</key>
            <string>StickyGrid</string>
            <key>NSSendTypes</key>
            <array>
                <string>NSStringPboardType</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
fi

# Re-sign after assembling: a stale signature vs. modified Info.plist makes
# `open` fail with a cryptic LaunchServices error.
codesign --force --deep --sign - "$APP"

echo "Built $APP — launch with: open $APP"
