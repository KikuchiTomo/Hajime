#!/bin/sh
# バージョンの PATCH とビルド番号を 1 つずつ上げる(docs/dev/adr/0008-versioning.md)．
# 使い方: tools/release/bump_patch.sh macos
set -eu
platform=${1:-}
case "$platform" in
  macos) file="$(cd "$(dirname "$0")/../.." && pwd)/apps/macos/project.yml" ;;
  *) echo "使い方: $0 macos" >&2; exit 2 ;;
esac
version=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' "$file")
build=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"/\1/p' "$file")
major=${version%%.*}; rest=${version#*.}; minor=${rest%%.*}; patch=${rest#*.}
case "$major$minor$patch$build" in *[!0-9]*|"") echo "バージョンの書き方が読めません: $version ($build)" >&2; exit 1 ;; esac
next="$major.$minor.$((patch + 1))"
sed -i '' "s/MARKETING_VERSION: \"$version\"/MARKETING_VERSION: \"$next\"/; s/CURRENT_PROJECT_VERSION: \"$build\"/CURRENT_PROJECT_VERSION: \"$((build + 1))\"/" "$file"
echo "$platform: v$version → v$next (ビルド $((build + 1)))．タグは $platform/v$next"
