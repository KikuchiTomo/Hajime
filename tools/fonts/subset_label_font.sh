#!/bin/sh
# 候補ウィンドウの番号・種類の行・モードの札に使う BIZ UDゴシック を，使う字だけに絞る．
# 元のフォントは 4.6MB あり，そのままリポジトリに入れると重いため．
# ラベルに新しい漢字を使うときは design/fonts/label-glyphs.txt に足してから実行し直す．
#
# 使い方: tools/fonts/subset_label_font.sh <BIZUDGothic-Regular.ttf のパス>
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
source_font=$1
out="$root/apps/macos/S90IME/Resources/Fonts/BIZUDGothic-Labels.ttf"
# ASCII・ひらがな・カタカナ・全角英数・半角カタカナ・記号
unicodes="U+0020-007E,U+00A5,U+3000-303F,U+3040-309F,U+30A0-30FF,U+FF01-FF9F,U+2190-2193,U+21E5"
pyftsubset "$source_font" --unicodes="$unicodes" --text-file="$root/design/fonts/label-glyphs.txt" \
  --layout-features='*' --output-file="$out"
echo "wrote $out"
