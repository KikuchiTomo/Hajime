#!/bin/sh
# かな漢字変換の辞書(hajime-dictionary)を取得し，SHA-256 を確かめて展開する．リポジトリには入れず，リポジトリの外に置く．
# 版とハッシュを変えるときは，core/Sources/HajimeEngine/BundledDictionary.swift と tools/dictionary/fetch_dictionary.ps1 を一緒に変える．
#
# 使い方: tools/dictionary/fetch_dictionary.sh [置き場所(既定: リポジトリの 1 つ上の models/)]
# 置き場所の hajime-dictionary-<版>/Dictionary に展開する
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
destination=${1:-"$root/../models"}
version="0.5.3"
# https://github.com/KikuchiTomo/hajime-dictionary の Releases
url="https://github.com/KikuchiTomo/hajime-dictionary/releases/download/v$version/hajime-dictionary-$version.tar.gz"
expected="af10cad7cc14565f82748200cf9cdd5402a9aff293c32d044170ab1190a2681a"
# 展開した Dictionary/SHA256SUMS の SHA-256(BundledDictionary.expectedManifestSHA256 と同じ値)
manifest="c5672a2bdc38f636cddf0853b1ea9ceb2acf85f0a0d565779030d529c20cb478"

directory="$destination/hajime-dictionary-$version"
if [ -f "$directory/Dictionary/SHA256SUMS" ] && echo "$manifest  $directory/Dictionary/SHA256SUMS" | shasum -a 256 -c - >/dev/null 2>&1; then
  echo "確かめました: $directory/Dictionary"
  exit 0
fi
mkdir -p "$destination"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -sL --fail -o "$work/dictionary.tar.gz" "$url"
echo "$expected  $work/dictionary.tar.gz" | shasum -a 256 -c - >/dev/null || { echo "辞書の SHA-256 が一致しません" >&2; exit 1; }
tar -xzf "$work/dictionary.tar.gz" -C "$work"
echo "$manifest  $work/hajime-dictionary-$version/Dictionary/SHA256SUMS" | shasum -a 256 -c - >/dev/null || { echo "辞書の一覧の SHA-256 が一致しません" >&2; exit 1; }
(cd "$work/hajime-dictionary-$version/Dictionary" && shasum -a 256 -c SHA256SUMS >/dev/null) || { echo "辞書のファイルの SHA-256 が一覧と一致しません" >&2; exit 1; }
rm -rf "$directory"
mv "$work/hajime-dictionary-$version" "$directory"
echo "確かめました: $directory/Dictionary"
