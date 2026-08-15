#!/bin/bash
# 编译并打包 盒盖助手.app（build/盒盖助手.app）
set -euo pipefail
# 用脚本自身绝对目录定位仓库根，兼容「仓库根/LidAssistant/build-app.sh」这类 CI 调用方式
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

swift build -c release

APP="build/盒盖助手.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/LidAssistant "$APP/Contents/MacOS/LidAssistant"
# SwiftPM 产物会保留本机源码绝对路径；发布前移除调试符号，避免暴露用户名与目录。
strip -S "$APP/Contents/MacOS/LidAssistant"
# 授权脚本打进 App 包，便于 brew/下载安装后一键授权
cp "$SCRIPT_DIR/../grant.sh" "$APP/Contents/Resources/grant.sh"
chmod +x "$APP/Contents/Resources/grant.sh"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>盒盖助手</string>
	<key>CFBundleDisplayName</key><string>盒盖助手</string>
	<key>CFBundleIdentifier</key><string>com.lidassistant.menubar2</string>
	<key>CFBundleExecutable</key><string>LidAssistant</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.7.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "✓ 已生成 $APP"
