#!/bin/sh
# macOS のアプリのアイコン(Hajime.icns)を，公式サイトの Hajime のマーク(512px の PNG)から作る．
# IME の本体と更新用のアプリの Info.plist の CFBundleIconFile が指し，設定の画面の「情報」と更新の窓に出る．
# マークを差し替えたら作り直してコミットする．元が 512px なので，512@2x(1024px)は作らない
# 使い方: tools/icons/make_app_icon.sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
source="$root/apps/docs-site/static/images/hajime-mark.png"
output="$root/apps/macos/Hajime/Resources/Hajime.icns"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
iconset="$work/Hajime.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$source" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  if [ "$double" -le 512 ]; then
    sips -z "$double" "$double" "$source" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  fi
done
iconutil --convert icns --output "$output" "$iconset"
echo "作りました: $output"
