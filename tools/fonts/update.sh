#!/bin/sh
# Windows の候補ウィンドウの既定の書体 Kiwi Maru(SIL OFL 1.1)を取ってきてハッシュを確かめ，data/fonts/ に置く．
# 配布物(tools/windows/stage.ps1)は fonts\ に入れる．版を上げるときは commit と sha256 を書き換え，差分を PR にする．
#
# 使い方: tools/fonts/update.sh
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
commit="130fcfb0ff422fec96b335616b2ca99f91914792"
base="https://raw.githubusercontent.com/google/fonts/$commit/ofl/kiwimaru"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fetch() {
  curl -sL --fail -o "$work/$1" "$base/$1"
  echo "$2  $work/$1" | shasum -a 256 -c - >/dev/null
}
fetch KiwiMaru-Regular.ttf b0c3103b2639f690c1fcb44e060058383174bfd2eb72e6635bc9869b374dee87
fetch KiwiMaru-Medium.ttf b2659f300a7d48c3f29eb273ffc5e1b26cc416ac8c37ff6bb2f3e43c2f4d235a
fetch OFL.txt 07ceae7a6e3294cbbd0fdf6e35226550566a1cce9fd226d0f8a57f3d34c664fe
mkdir -p "$root/data/fonts"
cp "$work/KiwiMaru-Regular.ttf" "$work/KiwiMaru-Medium.ttf" "$root/data/fonts/"
cp "$work/OFL.txt" "$root/LICENSES/OFL-1.1-KiwiMaru.txt"
echo "書きました: data/fonts/KiwiMaru-Regular.ttf，data/fonts/KiwiMaru-Medium.ttf，LICENSES/OFL-1.1-KiwiMaru.txt"
