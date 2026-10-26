#!/bin/sh
# 日本郵便の郵便番号データ(UTF-8 形式の全国一括)を取ってきて，「郵便番号<タブ>住所」の表に整える．
# 結果は data/postal/postal-codes.tsv に書く．毎月の更新はこれを動かし，差分を PR にする(docs/dev/POSTAL-CODES.md)．
#
# 使い方: tools/postal/update.sh
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
url="https://www.post.japanpost.jp/service/search/zipcode/download/utf/zip/utf_ken_all.zip"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -sL --fail -o "$work/utf_ken_all.zip" "$url"
unzip -q -o "$work/utf_ken_all.zip" -d "$work"
python3 -I "$root/tools/postal/normalize.py" "$work/utf_ken_all.csv" "$root/data/postal/postal-codes.tsv"
echo "書きました: data/postal/postal-codes.tsv"
