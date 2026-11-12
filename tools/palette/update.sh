#!/bin/sh
# 絵文字・記号・顔文字のパレットの表(data/palette/palette.tsv)を作り直す．素材を取ってきてハッシュを確かめ，
# 漢字を含む名前の読みを macOS の日本語の解析で求めてから，tools/palette/build.py で表にする．
# バージョンを上げるときは url と sha256 を書き換え，差分を PR にする．macOS で動かす(読みを求めるのに Foundation を使う)．
#
# 使い方: tools/palette/update.sh
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
unicode="https://www.unicode.org/Public/17.0.0"
cldr="https://raw.githubusercontent.com/unicode-org/cldr/release-49/common"
emoji_data="https://raw.githubusercontent.com/iamcal/emoji-data/e77759c296ed37beb0dbd63908b43d8619509c6d"
azookey="https://raw.githubusercontent.com/azooKey/azooKey_emoji_dictionary_storage/eb15a8d1ea7c0688932d468024e62aa9c2d961c4"
mozc="https://raw.githubusercontent.com/google/mozc/85590f17409ebff387285f9665f362ede83ebd8e/src/data/emoticon"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/source"

fetch() {
    curl -sL --fail -o "$work/source/$1" "$2"
    echo "$3  $work/source/$1" | shasum -a 256 -c - >/dev/null
}

fetch emoji-test.txt "$unicode/emoji/emoji-test.txt" 1d8a944f88d7952f7ef7c5167fef3c67995bcae24543949710231b03a201acda
fetch UnicodeData.txt "$unicode/ucd/UnicodeData.txt" 2e1efc1dcb59c575eedf5ccae60f95229f706ee6d031835247d843c11d96470c
fetch ja.xml "$cldr/annotations/ja.xml" 74b6889ca7ad882b547e388a1e36a576ab4bdf00d12f59381eea286be44b15d3
fetch en.xml "$cldr/annotations/en.xml" 14d0e9bb5003c085250df4ac7bd7ba1e26d92e74174d7a3a2f42dc16e07fb155
fetch ja_derived.xml "$cldr/annotationsDerived/ja.xml" 9e0c15fb0eeae7c7dd088cd082bcf55580a156a0e6b569f2ebc251b7b06c628f
fetch en_derived.xml "$cldr/annotationsDerived/en.xml" a4a6c1a4c341d94179cb116623c5f44c47400a5bc55da483423ef7430ecf622e
fetch emoji.json "$emoji_data/emoji.json" 8736d721991e48c41c57acc46b65e5d32258a45e4bcdebcc6012f420f81e775d
fetch emoji_all_E17.0.txt "$azookey/EmojiDictionary/emoji_all_E17.0.txt" 25ed57b62849d05170db028a2f7a2e4365fe652638c6eb89f7f861066dab3da0
fetch emoticon.tsv "$mozc/emoticon.tsv" 366558b380bef07dda26822c9100d1efabee539f7961b2c6363d4614c4a762c4
fetch categorized.tsv "$mozc/categorized.tsv" 4497c16a706de418b05e73eaddbce13e5d3390e7c2de71200b28c0c97ae5c4fc

python3 -I "$root/tools/palette/build.py" collect "$work/source" "$root/tools/palette/symbols.txt" > "$work/words.txt"
swift "$root/tools/palette/readings.swift" < "$work/words.txt" > "$work/readings.tsv"
mkdir -p "$root/data/palette"
python3 -I "$root/tools/palette/build.py" build "$work/source" "$root/tools/palette/symbols.txt" "$root/tools/palette/names.txt" \
    "$work/readings.tsv" "$root/data/palette/palette.tsv"
echo "書きました: data/palette/palette.tsv"
