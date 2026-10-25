#!/bin/sh
# macOS の入力メソッドをビルドし，~/Library/Input Methods に入れて有効にする．
# 使い方: tools/macos/install.sh [Debug|Release]
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
configuration=${1:-Release}
app_name="s90.tokyo IME.app"
destination="$HOME/Library/Input Methods"

cd "$root/apps/macos"
xcodegen generate --quiet
xcodebuild -project S90IME.xcodeproj -scheme S90IME -configuration "$configuration" -derivedDataPath build build -quiet

# 動いている古い版を止めてから入れ替える
pkill -x "s90.tokyo IME" 2>/dev/null || true
mkdir -p "$destination"
rm -rf "$destination/$app_name"
cp -R "build/Build/Products/$configuration/$app_name" "$destination/"
swift "$root/tools/macos/register_input_source.swift" "$destination/$app_name"
echo "入れました: $destination/$app_name"
echo "システム設定 > キーボード > 入力ソース で「s90.tokyo IME」を確かめてください"
