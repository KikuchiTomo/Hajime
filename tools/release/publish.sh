#!/bin/sh
# 作った macOS と Windows の配布物を，GitHub の 1 つのリリースに置く．配布物の SHA-256 の一覧(SHA256SUMS.txt)も一緒に置く．
# 説明は，前のリリースのタグからマージした PR の一覧(GitHub が作る What's Changed)と，コントリビューター(その間のコミットの作者．ボットを除く)をメンションした一覧にする．
# 使い方: tools/release/publish.sh <タグ> <バージョン> <配布物の置き場所>
# GH_TOKEN が要る(GitHub Actions の github.token)
set -eu
tag=$1
version=$2
dist=$3
"$(dirname "$0")/checksums.sh" "$dist"
files=$(find "$dist" -maxdepth 1 -type f \( -name '*.pkg' -o -name '*.msi' \) | sort)
repository=${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}
previous=$(git ls-remote --tags --refs origin 'refs/tags/v*' | sed 's|.*refs/tags/||' | sort -V | awk -v tag="$tag" '$0 == tag { print last; exit } { last = $0 }')
if [ -n "$previous" ]; then
  logins=$(gh api --paginate "repos/$repository/compare/$previous...$tag" --jq '.commits[].author.login // empty')
  changes=$(gh api "repos/$repository/releases/generate-notes" -f tag_name="$tag" -f previous_tag_name="$previous" --jq .body)
else
  logins=$(gh api --paginate "repos/$repository/commits?sha=$tag" --jq '.[].author.login // empty')
  changes=$(gh api "repos/$repository/releases/generate-notes" -f tag_name="$tag" --jq .body)
fi
mentions=$(printf '%s\n' "$logins" | grep -v '\[bot\]$' | grep -v '^$' | sort -u | sed 's/^/@/' | paste -sd ' ' -)
notes=$changes
if [ -n "$mentions" ]; then notes=$(printf '%s\n\n## コントリビューター\n\n%s\n' "$notes" "$mentions"); fi
# shellcheck disable=SC2086
gh release create "$tag" --verify-tag --latest \
  --title "v$version" --notes "$notes" \
  $files "$dist/SHA256SUMS.txt"
echo "置きました: $tag"
