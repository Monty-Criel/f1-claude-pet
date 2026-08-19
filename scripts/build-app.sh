#!/usr/bin/env bash
# Assemble F1ClaudePet.app around the SwiftPM binary.
#
# Why this exists: macOS will not display an NSStatusItem for a process that
# isn't a bundled application. The status item is created quite happily and
# `button` is non-nil, it simply never appears — so the menu bar control only
# works from a real .app. Bundling also gives the pet its own identity for
# Accessibility, instead of inheriting whatever granted the terminal.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-debug}"
APP="$ROOT/F1ClaudePet.app"
BIN="$ROOT/.build/$CONFIG/F1ClaudePet"

(cd "$ROOT" && swift build -c "$CONFIG")

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/F1ClaudePet"

# Icon, rendered from the same sprite the pet drives so the two never drift.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
"$BIN" --export-icon "$ICONSET/icon_1024.png" >/dev/null
for size in 16 32 128 256 512; do
    sips -z $size $size          "$ICONSET/icon_1024.png" --out "$ICONSET/icon_${size}x${size}.png"    >/dev/null 2>&1
    sips -z $((size*2)) $((size*2)) "$ICONSET/icon_1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null 2>&1
done
rm -f "$ICONSET/icon_1024.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null \
    || echo "warning: iconutil failed, app will use the default icon"

# Real engine recordings (CC BY-SA, see Resources/Sounds/CREDITS.md) ride in
# the bundle; the bare binary falls back to synthesis without them.
if [ -d "$ROOT/Resources/Sounds" ]; then
    mkdir -p "$APP/Contents/Resources/Sounds"
    cp "$ROOT/Resources/Sounds/"*.m4a "$APP/Contents/Resources/Sounds/" 2>/dev/null || true
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>F1ClaudePet</string>
    <key>CFBundleDisplayName</key>       <string>F1 Claude Pet</string>
    <key>CFBundleExecutable</key>        <string>F1ClaudePet</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundleIdentifier</key>        <string>com.nibel.f1claudepet</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.9.0-beta</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>LSMinimumSystemVersion</key>    <string>15.0</string>
    <!-- Agent app: no Dock icon, no menu bar of its own, just the status item. -->
    <key>LSUIElement</key>               <true/>
    <key>NSHighResolutionCapable</key>   <true/>
</dict>
</plist>
PLIST

# Sign with the stable "F1DockPet Dev" certificate when it exists (created by
# scripts/setup-signing.sh). TCC keys the Accessibility grant on the signing
# identity: with the certificate it survives rebuilds; with ad-hoc fallback it
# is revoked on every rebuild and macOS re-prompts.
# "F1DockPet Dev" is the signing cert label, kept from before the rename —
# the label is invisible and swapping certs would needlessly change the code
# identity that the Accessibility grant is anchored to.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/F1DockPet Dev/{print $2; exit}')
if [ -n "$IDENTITY" ]; then
    codesign --force --deep --sign "$IDENTITY" "$APP"
else
    echo "warning: no 'F1DockPet Dev' identity — ad-hoc signing, Accessibility will not persist"
    codesign --force --deep --sign - "$APP" 2>/dev/null || true
fi

echo "built $APP"
