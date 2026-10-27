#!/bin/sh
# 作った配布物を GitHub の Releases に置く．配布物の SHA-256 の一覧(SHA256SUMS.txt)も一緒に置く．
# 説明は tools/release/notes/<OS>.md に，同じ OS の前のタグからの変更の一覧を足したもの．
# 使い方: tools/release/publish.sh <タグ> <macos|windows> <バージョン> <配布物の置き場所>
# GH_TOKEN が要る(GitHub Actions の github.token)
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
tag=$1
platform=$2
version=$3
dist=$4
case "$platform" in
  macos|windows) ;;
  *) echo "OS は macos か windows です: $platform" >&2; exit 2 ;;
esac
files=$(find "$dist" -maxdepth 1 -type f \( -name '*.pkg' -o -name '*.msi' \) | sort)
if [ -z "$files" ]; then
  echo "配布物がありません: $dist" >&2
  exit 1
fi
# shellcheck disable=SC2086,SC2046 # ファイル名に空白は無い(s90.tokyo-IME-<バージョン>.pkg)
(cd "$dist" && sha256sum $(for file in $files; do basename "$file"; done) > SHA256SUMS.txt)
notes="$dist/notes.md"
sed -e "s/@VERSION@/$version/g" "$root/tools/release/notes/$platform.md" > "$notes"
# 変更の一覧は，同じ OS の前のタグから作る(もう片方の OS のタグとの差にしない)
previous=$(git ls-remote --tags --refs origin "refs/tags/$platform/v*" | sed 's|.*refs/tags/||' | sort -V | awk -v tag="$tag" '$0 == tag { print last; exit } { last = $0 }')
start=""
if [ -n "$previous" ]; then start="--notes-start-tag=$previous"; fi
# 1.0.0 になるまでは試用のバージョンとして出す
prerelease=""
case "$version" in 0.*) prerelease="--prerelease" ;; esac
# shellcheck disable=SC2086
gh release create "$tag" --verify-tag $prerelease $start --generate-notes \
  --title "v$version-$platform" --notes-file "$notes" \
  $files "$dist/SHA256SUMS.txt"
echo "置きました: $tag"
