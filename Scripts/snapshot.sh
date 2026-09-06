#!/bin/bash
# ============================================================
# ResolveDBBackup 版本快照脚本
# 用法: ./Scripts/snapshot.sh [版本号] [改动说明]
#   例: ./Scripts/snapshot.sh 1.3.0 "新增局域网全扫 + 本地库备份"
# 效果: 把当前完整工程（源码 + README + dist/.app，排除 .build/.DS_Store/backups）
#       快照到 backups/<版本>/<版本>_<时间戳>/，并在 backups/VERSIONS.md 登记。
# 回退: 把对应快照目录里的内容复制回工程根目录即可（或直接用快照里的 .app）。
# 约定: 每次修改前先运行本脚本，形成"上一个版本"的保险。
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/ResolveDBBackup.app/Contents/Info.plist 2>/dev/null || echo 'dev')}"
NOTE="${2:-}"
STAMP="$(date +%Y%m%d_%H%M%S)"
DEST="backups/${VERSION}/${VERSION}_${STAMP}"

mkdir -p "$DEST"

# 复制工程源码/配置/脚本/测试（排除构建产物与自身）
rsync -a --exclude '.build' --exclude '.DS_Store' --exclude 'backups' \
    Package.swift project.yml README.md Scripts Sources Tests Tests-XCTest "$DEST/"

# 复制当前打包好的 .app 产物
if [ -d dist/ResolveDBBackup.app ]; then
    mkdir -p "$DEST/dist"
    rsync -a --exclude '.DS_Store' dist/ResolveDBBackup.app "$DEST/dist/"
fi

# 写版本信息
{
    echo "版本: ${VERSION}"
    echo "快照时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "改动说明: ${NOTE:-（未填写）}"
    echo "回退方法: 将本目录内容复制回工程根目录，然后 ./Scripts/make-app.sh 重新打包即可"
} > "$DEST/INFO.txt"

# 登记到 VERSIONS.md
{
    echo "- **${VERSION}**（${STAMP}）：${NOTE:-（未填写说明）} → \`backups/${VERSION}/${VERSION}_${STAMP}/\`"
} >> backups/VERSIONS.md

echo "✅ 已备份当前版本 ${VERSION} → $DEST"
echo "   说明: ${NOTE:-（未填写说明）}"
