#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$PWD/target}"
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
<key>CFBundleShortVersionString</key><string>1.1.5</string>
<key>CFBundleVersion</key><string>8</string>
<key>LSUIElement</key><false/>
<key>LSMinimumSystemVersion</key><string>10.15</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

# The app bundle is an intermediate; distribute a drag-to-Applications DMG.
STAGE=$(mktemp -d "$OUT/.dmg-stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT HUP INT TERM
ditto "$APP" "$STAGE/Shared Clipboard.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/安装说明.txt" <<'INSTALL'
共享剪贴板

将 Shared Clipboard 拖入 Applications（应用程序），然后从应用程序中打开。
安装后可以推出此磁盘映像。再次点击程序图标即可打开剪贴板历史主窗口。

当前为预览版，使用 ad-hoc 签名，尚未完成 Apple 公证。
INSTALL
hdiutil create -ov -format UDZO -fs HFS+ -volname "共享剪贴板" \
  -srcfolder "$STAGE" "$OUT/SharedClipboard-1.1.5-macos-universal.dmg"
hdiutil verify "$OUT/SharedClipboard-1.1.5-macos-universal.dmg"
