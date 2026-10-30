#!/bin/sh
# 作った macOS と Windows の配布物を，GitHub の 1 つのリリースに置く．配布物の SHA-256 の一覧(SHA256SUMS.txt)も一緒に置く．
# 説明はコントリビューター(前のリリースのタグからのコミットの作者．ボットを除く)をメンションした一覧だけにする．
# 使い方: tools/release/publish.sh <タグ> <バージョン> <配布物の置き場所>
# GH_TOKEN が要る(GitHub Actions の github.token)
set -eu
tag=$1
version=$2
dist=$3
# 両方の OS の配布物がそろっていなければ置かない
for pattern in '*.pkg' '*.msi'; do
  if [ -z "$(find "$dist" -maxdepth 1 -type f -name "$pattern")" ]; then
    echo "配布物($pattern)がありません: $dist" >&2
    exit 1
  fi
done
files=$(find "$dist" -maxdepth 1 -type f \( -name '*.pkg' -o -name '*.msi' \) | sort)
# shellcheck disable=SC2086,SC2046 # ファイル名に空白は無い(Hajime-<バージョン>.pkg・.msi)
(cd "$dist" && sha256sum $(for file in $files; do basename "$file"; done) > SHA256SUMS.txt)
repository=${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}
previous=$(git ls-remote --tags --refs origin 'refs/tags/v*' | sed 's|.*refs/tags/||' | sort -V | awk -v tag="$tag" '$0 == tag { print last; exit } { last = $0 }')
if [ -n "$previous" ]; then
  logins=$(gh api --paginate "repos/$repository/compare/$previous...$tag" --jq '.commits[].author.login // empty')
else
  logins=$(gh api --paginate "repos/$repository/commits?sha=$tag" --jq '.[].author.login // empty')
fi
mentions=$(printf '%s\n' "$logins" | grep -v '\[bot\]$' | grep -v '^$' | sort -u | sed 's/^/@/' | paste -sd ' ' -)
notes=""
if [ -n "$mentions" ]; then notes=$(printf '## コントリビューター\n\n%s\n' "$mentions"); fi
# shellcheck disable=SC2086
gh release create "$tag" --verify-tag --latest \
  --title "v$version" --notes "$notes" \
  $files "$dist/SHA256SUMS.txt"
echo "置きました: $tag"
