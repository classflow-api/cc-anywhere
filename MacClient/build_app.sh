#!/bin/bash
# Copyright (c) 2026 北京友联互动信息技术有限公司. All rights reserved.
#
# 把 SwiftPM 产出的裸 binary 打包成 macOS .app Bundle，含 Info.plist + AppIcon.icns。
# 用法：
#   bash build_app.sh          # debug 构建
#   bash build_app.sh release  # release 构建
#
# 产出：MacClient/.build/CCAnywhere.app
# 启动：open .build/CCAnywhere.app  （或拖到 /Applications）
#
# 设计：每次执行会从 Sources/CCAnywhere/Resources 同步最新 Info.plist + AppIcon.icns，
#       Binary 用最新 swift build 产物覆盖，可重复执行不副作用。

set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-debug}"
case "$CONFIG" in
  debug|release) ;;
  *) echo "用法: $0 [debug|release]"; exit 2 ;;
esac

echo "→ swift build -c $CONFIG"
swift build -c "$CONFIG"

# 定位最新 binary（SwiftPM 产物路径依赖 arch + config）
BIN=""
for candidate in \
  ".build/$CONFIG/CCAnywhere" \
  ".build/arm64-apple-macosx/$CONFIG/CCAnywhere" \
  ".build/x86_64-apple-macosx/$CONFIG/CCAnywhere"; do
  if [ -x "$candidate" ]; then BIN="$candidate"; break; fi
done
if [ -z "$BIN" ]; then
  echo "找不到 swift build 的 CCAnywhere 产物" >&2
  exit 3
fi

# Bundle 用中文文件名："遥指.app"，确保 Dock / Finder / LaunchServices 一切
# 缓存层级都直接看到中文名（避免靠 CFBundleDisplayName 还要绕缓存刷新）。
APP=".build/遥指.app"
# 清理任何旧的英文名 bundle（避免 Dock 残留两个图标）
rm -rf ".build/CCAnywhere.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 同步 Info.plist + AppIcon.icns（每次都从源覆盖，保持单一来源）
cp "Sources/CCAnywhere/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "Sources/CCAnywhere/Resources/AppIcon.icns" ]; then
  cp "Sources/CCAnywhere/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# 覆盖 binary
cp "$BIN" "$APP/Contents/MacOS/CCAnywhere"

# 触发 LaunchServices 重新识别（Dock 图标 / 应用名缓存）
touch "$APP"
/usr/bin/lsregister -f "$APP" 2>/dev/null || \
  /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$APP" 2>/dev/null || true

echo "✓ 打包完成：$PWD/$APP"
echo "  启动：open '$APP'"
