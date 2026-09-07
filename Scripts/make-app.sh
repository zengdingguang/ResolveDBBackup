#!/bin/bash
# 构建 ResolveDBBackup 并打包为可直接运行的 .app（菜单栏应用）。
# 用法: ./Scripts/make-app.sh  （在工程根目录 ResolveDBBackup/ 下执行，或任一路径执行）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ResolveDBBackup"
APP_DISPLAY_NAME="水螅ResolveBackup"
BUILD_DIR="$ROOT/.build-arch"
UNIVERSAL_BIN="$BUILD_DIR/universal/$APP_NAME"
APP_BUNDLE="$ROOT/dist/$APP_DISPLAY_NAME.app"

echo "==> 构建双架构 (arm64 + x86_64) —— 分别编译后 lipo 合并"
swift build -c release --arch arm64 --scratch-path "$BUILD_DIR/arm64" --package-path "$ROOT"
swift build -c release --arch x86_64 --scratch-path "$BUILD_DIR/x86_64" --package-path "$ROOT"
mkdir -p "$BUILD_DIR/universal"
lipo -create \
    "$BUILD_DIR/arm64/arm64-apple-macosx/release/$APP_NAME" \
    "$BUILD_DIR/x86_64/x86_64-apple-macosx/release/$APP_NAME" \
    -output "$UNIVERSAL_BIN"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$UNIVERSAL_BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 图标（v1.7.6）：App 图标 + 菜单栏图标均为自定义水螅剪影（白底黑图，原始渲染模式）
cp "$ROOT/Scripts/icon/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$ROOT/Assets/icons/menubar_icon.png" "$APP_BUNDLE/Contents/Resources/menubar_icon.png"
# v1.6.8：设置页打赏收款二维码
cp "$ROOT/Scripts/donation_qr.png" "$APP_BUNDLE/Contents/Resources/donation_qr.png"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleExecutable</key><string>ResolveDBBackup</string>
    <key>CFBundleIdentifier</key><string>com.resolvedbbackup.app</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>ResolveDBBackup</string>
    <key>CFBundleDisplayName</key><string>水螅ResolveBackup</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>1.7.7</string>
    <key>CFBundleVersion</key><string>34</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Zengdingguang Keylight</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

echo "==> 已生成: $APP_BUNDLE"
echo "    启动: open \"$APP_BUNDLE\""
