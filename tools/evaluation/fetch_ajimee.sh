#!/bin/sh
# かな漢字変換の評価に使う AJIMEE-Bench を取得し，SHA-256 を確かめて，hajime-playground --evaluate が読む TSV にする．
# データは CC-BY-SA 3.0 なので，リポジトリには入れず，リポジトリの外に置く．
# 上げるときは commit と sha256 を書き換える．
#
# 使い方: tools/evaluation/fetch_ajimee.sh [置き場所(既定: リポジトリの 1 つ上の evaluation/)]
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
destination=${1:-"$root/../evaluation"}
# https://github.com/azooKey/AJIMEE-Bench の JWTD_v2/v1/evaluation_items.json．コミットを固定する
commit="401666cd56d1a570c2021798b64b6da4396bfd45"
sha256="e9eb668fd6aa14b1e26436f429b5550108af0a1dfd443b8cea0bcb3ab3028fca"
url="https://raw.githubusercontent.com/azooKey/AJIMEE-Bench/$commit/JWTD_v2/v1/evaluation_items.json"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -sL --fail -o "$work/evaluation_items.json" "$url"
echo "$sha256  $work/evaluation_items.json" | shasum -a 256 -c - >/dev/null
mkdir -p "$destination"
python3 -I "$root/tools/evaluation/ajimee.py" "$work/evaluation_items.json" "$destination/ajimee.tsv"
echo "書きました: $destination/ajimee.tsv"
