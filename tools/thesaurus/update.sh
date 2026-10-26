#!/bin/sh
# 日本語 WordNet を取ってきてハッシュを確かめ，連想の辞書(R-18)として同梱する data/thesaurus/wordnet-ja.tsv を作り直す．
# バージョンを上げるときは url と sha256 を書き換え，差分を PR にする．
#
# 使い方: tools/thesaurus/update.sh
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
version="wnja 2.1"
url="https://github.com/bond-lab/wnja/releases/download/v2.1/wnja-2.1.tar.xz"
sha256="e6f141db243a78c729f5ef29a0dd2bdf434087dae170ad49b01034f19d9ff584"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -sL --fail -o "$work/wnja.tar.xz" "$url"
echo "$sha256  $work/wnja.tar.xz" | shasum -a 256 -c - >/dev/null
mkdir "$work/extracted"
tar -xJf "$work/wnja.tar.xz" -C "$work/extracted"
mkdir -p "$root/data/thesaurus"
python3 -I "$root/tools/thesaurus/wordnet.py" "$work/extracted/wnja/wnja-2.1.xml" "$root/data/thesaurus/wordnet-ja.tsv" --version "$version"
echo "書きました: data/thesaurus/wordnet-ja.tsv"
