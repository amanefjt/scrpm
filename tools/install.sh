#!/bin/bash
# scrpm を Release ビルドして /Applications/scrpm.app に配置し直すスクリプト。
#
# 背景: xcodebuild でビルドしただけでは ~/Code/scrpm/build/Release/scrpm.app が
# 更新されるだけで、普段 Dock / Spotlight から起動している /Applications/scrpm.app
# には反映されない。「コードを直したのにアプリの挙動が変わらない」と感じたら、
# 大抵はこのコピーをサボっているのが原因なので、このスクリプトで一括して行う。
#
# 使い方: ~/Code/scrpm/tools/install.sh
set -euo pipefail

# このスクリプト自身の場所からリポジトリルートを特定する（どこから実行しても動くように）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="scrpm.app"
INSTALLED_APP="/Applications/$APP_NAME"
BUILT_APP="$REPO_ROOT/build/Release/$APP_NAME"

cd "$REPO_ROOT"

echo "==> Release ビルド中..."
xcodebuild -project scrpm.xcodeproj -target scrpm -configuration Release build

if [ ! -d "$BUILT_APP" ]; then
    echo "エラー: ビルド成果物が見つかりません: $BUILT_APP" >&2
    exit 1
fi

echo "==> 起動中の scrpm を終了..."
osascript -e 'quit app "scrpm"' 2>/dev/null || true
sleep 1

echo "==> $INSTALLED_APP を新しいビルドで置き換え..."
rm -rf "$INSTALLED_APP"
cp -R "$BUILT_APP" "$INSTALLED_APP"

echo "==> 起動..."
open "$INSTALLED_APP"

echo "完了: $INSTALLED_APP を更新して起動しました。"
