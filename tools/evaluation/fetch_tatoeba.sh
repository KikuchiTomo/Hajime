#!/bin/sh
# かな漢字変換の評価に使う Tatoeba の日本語の文(人が付けたふりがな付き)を取得し，hajime-playground --evaluate が読む TSV にする．
# データは CC BY 2.0 FR(https://tatoeba.org/ja/terms_of_use)なので，リポジトリには入れず，リポジトリの外に置く．
# 書き出しは毎週更新され版を固定できないので，取得した日によって選ばれる文が少し変わる．前後を比べるときは同じ TSV を使う．
#
# 使い方: tools/evaluation/fetch_tatoeba.sh [置き場所(既定: リポジトリの 1 つ上の evaluation/)]
# 置き場所に tatoeba.tsv(約 2,000 文)と tatoeba-all.tsv(約 10 万文)を書く
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
destination=${1:-"$root/../evaluation"}
url="https://downloads.tatoeba.org/exports/transcriptions.tar.bz2"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -sL --fail -o "$work/transcriptions.tar.bz2" "$url"
tar -xjf "$work/transcriptions.tar.bz2" -C "$work"
mkdir -p "$destination"
python3 -I "$root/tools/evaluation/tatoeba.py" "$work/transcriptions.csv" "$destination/tatoeba.tsv"
python3 -I "$root/tools/evaluation/tatoeba.py" "$work/transcriptions.csv" "$destination/tatoeba-all.tsv" --all
echo "書きました: $destination/tatoeba.tsv，$destination/tatoeba-all.tsv"
