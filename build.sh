#!/bin/bash
# Copyright 2026 The TypingGuard Authors
# SPDX-License-Identifier: Apache-2.0
#
# 编译 TypingGuard.app（需要 Xcode 命令行工具：xcode-select --install）
set -euo pipefail
cd "$(dirname "$0")"

APP="TypingGuard.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

# 图标：没有 AppIcon.icns 时用 make_icon.swift 重新生成
[ -f AppIcon.icns ] || swift make_icon.swift
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "正在编译…"
swiftc -O TypingGuard.swift -o "$APP/Contents/MacOS/TypingGuard" -framework Cocoa

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>TypingGuard</string>
    <key>CFBundleDisplayName</key><string>TypingGuard</string>
    <key>CFBundleIdentifier</key><string>local.typingguard</string>
    <key>CFBundleExecutable</key><string>TypingGuard</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string><string>zh-Hant</string></array>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"

echo "完成：$(pwd)/$APP"
echo "下一步：把它拖进「应用程序」文件夹，然后打开。"
