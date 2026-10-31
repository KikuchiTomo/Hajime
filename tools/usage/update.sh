#!/bin/sh
# japanese-usage-dictionary(同音異義語の使い分けの辞書)を取ってきてハッシュを確かめ，同音異義語の注釈(R-08)として
# 同梱する data/usage/usage_dict.txt を置き換える．中身は手を加えずに置く．
# 上げるときは commit と sha256 を書き換え，差分を PR にする．
#
# 使い方: tools/usage/update.sh
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
commit="38d34621238afe66e8e669ff0a37bc84039b6b93"
sha256="9a5ff4ab0be399e01e6aeb8637a166d421299f92a3c39df93fab6bcbaf3e68b8"
url="https://raw.githubusercontent.com/hiroyuki-komatsu/japanese-usage-dictionary/$commit/usage_dict.txt"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -sL --fail -o "$work/usage_dict.txt" "$url"
echo "$sha256  $work/usage_dict.txt" | shasum -a 256 -c - >/dev/null
mkdir -p "$root/data/usage"
cp "$work/usage_dict.txt" "$root/data/usage/usage_dict.txt"
echo "書きました: data/usage/usage_dict.txt"
