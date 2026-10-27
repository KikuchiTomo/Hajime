#!/bin/sh
# 作った配布物を GitHub の Releases に置く．配布物の SHA-256 の一覧(SHA256SUMS.txt)も一緒に置く．
# 説明はコントリビューター(同じ OS の前のタグからのコミットの作者．ボットを除く)をメンションした一覧だけにする．
# 使い方: tools/release/publish.sh <タグ> <macos|windows> <バージョン> <配布物の置き場所>
# GH_TOKEN が要る(GitHub Actions の github.token)
set -eu
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
# コントリビューターは，同じ OS の前のタグからのコミットの作者(もう片方の OS のタグとの差にしない)
repository=${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}
previous=$(git ls-remote --tags --refs origin "refs/tags/$platform/v*" | sed 's|.*refs/tags/||' | sort -V | awk -v tag="$tag" '$0 == tag { print last; exit } { last = $0 }')
if [ -n "$previous" ]; then
  logins=$(gh api --paginate "repos/$repository/compare/$previous...$tag" --jq '.commits[].author.login // empty')
else
  logins=$(gh api --paginate "repos/$repository/commits?sha=$tag" --jq '.[].author.login // empty')
fi
mentions=$(printf '%s\n' "$logins" | grep -v '\[bot\]$' | grep -v '^$' | sort -u | sed 's/^/@/' | paste -sd ' ' -)
notes=""
if [ -n "$mentions" ]; then notes=$(printf '## コントリビューター\n\n%s\n' "$mentions"); fi
# 1.0.0 になるまでは試用のバージョンとして出す
prerelease=""
case "$version" in 0.*) prerelease="--prerelease" ;; esac
# shellcheck disable=SC2086
gh release create "$tag" --verify-tag $prerelease \
  --title "v$version-$platform" --notes "$notes" \
  $files "$dist/SHA256SUMS.txt"
echo "置きました: $tag"
