#!/bin/bash
# Builds AltTabber and packages it as a proper macOS .app bundle.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="AltTabber"
BUNDLE_ID="com.vibecode.alttabber"
VERSION="1.0.0"
CONFIG="${1:-release}"   # pass "debug" for a faster build

echo "▸ Compiling ($CONFIG)…"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
APP_DIR="build/$APP_NAME.app"

echo "▸ Assembling bundle…"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleVersion</key>         <string>$VERSION</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key> <string>Vibecoded window switcher.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>AltTabber capture les fenêtres pour afficher leurs vignettes dans le sélecteur.</string>
</dict>
</plist>
PLIST

# A stable signing identity keeps TCC (Accessibility / Screen Recording)
# permissions across rebuilds. Preference order:
#   1. a valid identity (e.g. your "Apple Development" cert)
#   2. the local "AltTabber Self-Signed" cert (./make-identity.sh)
#   3. ad-hoc (permissions reset on every rebuild)
SELF_SIGNED="AltTabber Self-Signed"
VALID_HASH="$(security find-identity -v -p codesigning 2>/dev/null | awk 'match($0, /[0-9A-F]{40}/){print substr($0, RSTART, 40); exit}')"

if [ -n "$VALID_HASH" ]; then
    LABEL="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' 'NR==2{print $2}')"
    echo "▸ Signing with valid identity: ${LABEL:-$VALID_HASH}…"
    codesign --force --deep --sign "$VALID_HASH" "$APP_DIR"
elif security find-identity -p codesigning 2>/dev/null | grep -q "$SELF_SIGNED"; then
    echo "▸ Signing with '$SELF_SIGNED' (stable identity)…"
    codesign --force --deep --sign "$SELF_SIGNED" "$APP_DIR"
else
    echo "▸ Ad-hoc signing (run ./make-identity.sh once for stable permissions)…"
    codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || \
        codesign --force --sign - "$APP_DIR"
fi

echo "✓ Built $APP_DIR"
echo ""
echo "  Lancer :  open \"$APP_DIR\""
echo "  Ou depuis le terminal (logs visibles) :  \"$APP_DIR/Contents/MacOS/$APP_NAME\""
