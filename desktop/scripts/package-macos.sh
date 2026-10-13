#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export CARGO_TARGET_DIR="$PWD/target"
export MACOSX_DEPLOYMENT_TARGET=10.15
cargo build --release --locked --target aarch64-apple-darwin
cargo build --release --locked --target x86_64-apple-darwin
TARGET=$(cargo metadata --no-deps --format-version 1 | python3 -c 'import json,sys;print(json.load(sys.stdin)["target_directory"])')
OUT="$PWD/out"
APP="$OUT/Shared Clipboard.app"
mkdir -p "$APP/Contents/MacOS"
lipo -create "$TARGET/aarch64-apple-darwin/release/shared-clipboard" "$TARGET/x86_64-apple-darwin/release/shared-clipboard" -output "$APP/Contents/MacOS/shared-clipboard"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>chat.clawkit.shared-clipboard</string>
<key>CFBundleName</key><string>Shared Clipboard</string>
<key>CFBundleDisplayName</key><string>共享剪贴板</string>
<key>CFBundleExecutable</key><string>shared-clipboard</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.2</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>10.15</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/SharedClipboard-1.1.2-macos-universal.zip"
