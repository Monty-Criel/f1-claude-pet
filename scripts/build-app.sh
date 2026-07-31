#!/usr/bin/env bash
# Assemble F1DockPet.app around the SwiftPM binary.
#
# Why this exists: macOS will not display an NSStatusItem for a process that
# isn't a bundled application. The status item is created quite happily and
# `button` is non-nil, it simply never appears — so the menu bar control only
# works from a real .app. Bundling also gives the pet its own identity for
# Accessibility, instead of inheriting whatever granted the terminal.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-debug}"
APP="$ROOT/F1DockPet.app"
BIN="$ROOT/.build/$CONFIG/F1DockPet"

(cd "$ROOT" && swift build -c "$CONFIG")

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/F1DockPet"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>F1DockPet</string>
    <key>CFBundleDisplayName</key>       <string>F1 Dock Pet</string>
    <key>CFBundleExecutable</key>        <string>F1DockPet</string>
    <key>CFBundleIdentifier</key>        <string>com.nibel.f1dockpet</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <!-- Agent app: no Dock icon, no menu bar of its own, just the status item. -->
    <key>LSUIElement</key>               <true/>
    <key>NSHighResolutionCapable</key>   <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so the Accessibility grant sticks to a stable identity instead of
# being revoked every time the binary changes.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "built $APP"
