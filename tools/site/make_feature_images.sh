#!/bin/bash
# 公式サイトのトップページの画像(apps/docs-site/static/images/hero.webp と features/ の一部)を，
# Debug でビルドした Hajime Debug が書き出した画面(SnapshotRenderer)から作る．
# 窓の外の背景を消して影を付け，サイトのほかの写真と同じ茶色の背景に並べる．
# トップの画像は，既存の写真(features/candidate-tree.webp)のテキストエディットの窓の中身を描き直して作る．
# 候補ウィンドウや設定の見た目を変えたら作り直してコミットする．ImageMagick が要る
# 使い方:
#   "apps/macos/build/Build/Products/Debug/Hajime Debug.app/Contents/MacOS/Hajime Debug" --render-snapshots
#   tools/site/make_feature_images.sh [書き出した画面のディレクトリ]
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
snapshots=${1:-$HOME/Library/Containers/men.haji.inputmethod.debug/Data/tmp/hajime-snapshots}
images="$root/apps/docs-site/static/images"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# 背景の色は，既存の写真の壁紙の上と下からとった
top='rgb(149,100,55)'
bottom='rgb(112,68,32)'

# 窓の外の背景(四隅とつながった同じ色)を透明にし，縮めて影を付ける．$3 は縮める率(%)
window() {
  local source="$snapshots/$1.png" output="$work/$2.png" scale=${3:-100} w h
  w=$(magick identify -format %w "$source")
  h=$(magick identify -format %h "$source")
  magick "$source" -alpha set -fuzz 4% -fill none \
    -draw "color 0,0 floodfill" -draw "color $((w - 1)),0 floodfill" \
    -draw "color 0,$((h - 1)) floodfill" -draw "color $((w - 1)),$((h - 1)) floodfill" \
    -resize "${scale}%" \
    \( +clone -background black -shadow 50x16+0+12 \) +swap -background none -layers merge +repage "$output"
}

# 窓の背景と窓の色が同じもの(手書きの画面)は，切り抜かずに角を丸めて影を付ける
panel() {
  local source="$snapshots/$1.png" output="$work/$2.png" scale=${3:-100} w h
  magick "$source" -resize "${scale}%" "$work/resized.png"
  w=$(magick identify -format %w "$work/resized.png")
  h=$(magick identify -format %h "$work/resized.png")
  magick "$work/resized.png" \( -size "${w}x$h" xc:none -fill white -draw "roundrectangle 0,0,$((w - 1)),$((h - 1)),20,20" \) \
    -compose DstIn -composite -compose over \
    \( +clone -background black -shadow 50x16+0+12 \) +swap -background none -layers merge +repage "$output"
}

# 幅 1400 の茶色の背景に窓を置く．$1 出力の名前，$2 高さ，残りは「窓:x:y」(c なら真ん中)
scene() {
  local name=$1 height=$2 spec file x y w h
  shift 2
  local layers=()
  for spec in "$@"; do
    IFS=: read -r file x y <<<"$spec"
    w=$(magick identify -format %w "$work/$file.png")
    h=$(magick identify -format %h "$work/$file.png")
    [ "$x" = c ] && x=$(((1400 - w) / 2))
    [ "$y" = c ] && y=$(((height - h) / 2))
    layers+=("$work/$file.png" -geometry "+$x+$y" -composite)
  done
  magick -size "1400x$height" "gradient:$top-$bottom" "${layers[@]}" -quality 82 "$images/features/$name.webp"
}

window list-glass-dark list
scene candidate-list 600 list:c:c

window suggestion-glass-dark suggestion
window prediction-glass-dark prediction
scene suggestion-prediction 520 suggestion:300:105 prediction:830:190

window correction-glass-dark english
scene english-words 520 english:c:c

window homophone-list-glass-dark meaning
scene meaning 640 meaning:c:c

for kind in emoji kaomoji symbol; do window "palette-$kind-glass-dark" "palette-$kind" 52; done
scene palette 680 palette-emoji:62:c palette-kaomoji:497:c palette-symbol:932:c

panel handwriting-dark handwriting 85
scene handwriting 680 handwriting:c:c

for theme in washi neon nordic terminal; do window "branch-$theme" "theme-$theme" 42; done
scene themes 720 theme-washi:50:40 theme-neon:715:40 theme-nordic:50:375 theme-terminal:715:375

# トップの画像: 窓の中身(題の下)を窓の色で塗り，入力中の文と下線を書いて，分岐図と語の意味を置く
font="/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc"
window homophone-branch-glass-dark hero-branch 74
magick "$images/features/candidate-tree.webp" -fill 'rgb(30,30,30)' -draw "rectangle 74,96 1324,600" \
  -font "$font" -pointsize 27 -fill 'rgb(235,235,235)' -annotate +85+124 "写真を撮る" \
  -fill 'rgb(62,113,214)' -draw "rectangle 85,127 166,128" -draw "rectangle 166,126 220,129" \
  "$work/hero-branch.png" -geometry +28+95 -composite -quality 85 "$images/hero.webp"
echo "作りました: $images/hero.webp と $images/features/"
