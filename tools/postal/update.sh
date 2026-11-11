#!/bin/sh
# 日本郵便の郵便番号データ(UTF-8 形式の全国一括)と大口事業所個別番号データを取ってきて，「郵便番号<タブ>住所」の表に整える．
# 結果は data/postal/postal-codes.tsv に書く．毎月の更新はこれを動かし，差分を PR にする(docs/dev/POSTAL-CODES.md)．
#
# 使い方: tools/postal/update.sh
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
base="https://www.post.japanpost.jp/service/search/zipcode/download"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -sL --fail -o "$work/utf_ken_all.zip" "$base/utf/zip/utf_ken_all.zip"
curl -sL --fail -o "$work/jigyosyo.zip" "$base/office/zip/jigyosyo.zip"
unzip -q -o "$work/utf_ken_all.zip" -d "$work"
unzip -q -o "$work/jigyosyo.zip" -d "$work"
offices=$(find "$work" -maxdepth 1 -iname 'jigyosyo.csv' | head -n 1)
python3 -I "$root/tools/postal/normalize.py" "$work/utf_ken_all.csv" "$offices" "$root/data/postal/postal-codes.tsv"
echo "書きました: data/postal/postal-codes.tsv"
