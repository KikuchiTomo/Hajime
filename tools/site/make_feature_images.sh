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

# 幅 1400 の茶色の背景に窓を置く．$1 出力の名前，$2 高さ，残りは「窓:x:y」(c なら真ん中)．
# 高さはどの写真も 672 にし，トップに並べたときの縦横の比をそろえる
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
scene candidate-list 672 list:c:c

window suggestion-glass-dark suggestion
window prediction-glass-dark prediction
scene suggestion-prediction 672 suggestion:300:181 prediction:830:266

window correction-glass-dark english
scene english-words 672 english:c:c

window homophone-list-glass-dark meaning
scene meaning 672 meaning:c:c

for kind in emoji kaomoji symbol; do window "palette-$kind-glass-dark" "palette-$kind" 52; done
scene palette 672 palette-emoji:62:c palette-kaomoji:497:c palette-symbol:932:c

panel handwriting-dark handwriting 85
scene handwriting 672 handwriting:c:c

for theme in washi neon nordic terminal; do window "branch-$theme" "theme-$theme" 42; done
scene themes 672 theme-washi:50:24 theme-neon:715:24 theme-nordic:50:340 theme-terminal:715:340

font="/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc"
# テキストエディットの窓の写真(features/candidate-tree.webp．1400×672)の中身(題の下)を窓の色で塗ったもの．
# 入力中の文や候補の窓を描いた写真は，この上に作り直して窓の大きさと縦横の比をそろえる
textedit="$work/textedit.png"
magick "$images/features/candidate-tree.webp" -fill 'rgb(30,30,30)' -draw "rectangle 74,96 1324,600" "$textedit"
width() { magick -font "$font" -pointsize 27 label:"$1" -format %w info:; }

# 分岐図: 入力中の文(選んでいる文節は太い下線)の下に，今の分岐図を置く
window branch-glass-dark tree 74
lead="私の名前は"
focus="中野です"
from=$((85 + $(width "$lead")))
to=$((from + $(width "$focus")))
magick "$textedit" -font "$font" -pointsize 27 -fill 'rgb(235,235,235)' -annotate +85+124 "$lead$focus" \
  -fill 'rgb(62,113,214)' -draw "rectangle 85,127 $from,128" -draw "rectangle $from,126 $to,129" \
  "$work/tree.png" -geometry +28+95 -composite -quality 85 "$work/candidate-tree.webp"

# ライブ変換と補正: 写真の入力中の文と案内(題の下の帯)を，塗った窓の同じ位置に戻す．高さを 672 にそろえる
for name in live-conversion typo-correction; do
  magick "$textedit" \( "$images/features/$name.webp" -crop 1250x268+74+96 +repage \) -geometry +74+96 -composite \
    -quality 82 "$images/features/$name.webp"
done

# トップの画像: 窓の中身(題の下)を窓の色で塗り，入力中の文と下線を書いて，分岐図と語の意味を置く
window homophone-branch-glass-dark hero-branch 74
magick "$images/features/candidate-tree.webp" -fill 'rgb(30,30,30)' -draw "rectangle 74,96 1324,600" \
  -font "$font" -pointsize 27 -fill 'rgb(235,235,235)' -annotate +85+124 "写真を撮る" \
  -fill 'rgb(62,113,214)' -draw "rectangle 85,127 166,128" -draw "rectangle 166,126 220,129" \
  "$work/hero-branch.png" -geometry +28+95 -composite -quality 85 "$images/hero.webp"
# 分岐図の写真は，トップの画像の元にも使うので最後に置き換える
/bin/cp -f "$work/candidate-tree.webp" "$images/features/candidate-tree.webp"
echo "作りました: $images/hero.webp と $images/features/"
