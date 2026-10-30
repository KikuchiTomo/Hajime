#!/bin/sh
# macOS と Windows のバージョンの PATCH か MINOR をそろえて 1 つ上げ，ビルド番号も 1 つ上げる(docs/dev/adr/0008-versioning.md)．
# MINOR を上げるときは PATCH を 0 に戻す．両方のバージョンは同じでなければならない
# 使い方: tools/release/bump_version.sh [patch|minor]
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
level=${1:-patch}
case "$level" in
  patch|minor) ;;
  *) echo "使い方: $0 [patch|minor]" >&2; exit 2 ;;
esac

version=$("$root/tools/release/version.sh" macos)
windows=$("$root/tools/release/version.sh" windows)
if [ "$version" != "$windows" ]; then
  echo "macOS($version)と Windows($windows)のバージョンが違います．そろえてから上げてください" >&2
  exit 1
fi
major=${version%%.*}; rest=${version#*.}; minor=${rest%%.*}; patch=${rest#*.}
case "$major$minor$patch" in *[!0-9]*|"") echo "バージョンの書き方が読めません: $version" >&2; exit 1 ;; esac
if [ "$level" = minor ]; then next="$major.$((minor + 1)).0"; else next="$major.$minor.$((patch + 1))"; fi

# ビルド番号は OS ごとに数える
file="$root/apps/macos/project.yml"
build=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"/\1/p' "$file")
case "$build" in *[!0-9]*|"") echo "macOS のビルド番号が読めません: $build" >&2; exit 1 ;; esac
sed -i '' "s/MARKETING_VERSION: \"$version\"/MARKETING_VERSION: \"$next\"/; s/CURRENT_PROJECT_VERSION: \"$build\"/CURRENT_PROJECT_VERSION: \"$((build + 1))\"/" "$file"

file="$root/apps/windows/Cargo.toml"
lock="$root/apps/windows/Cargo.lock"
build=$(sed -n '/^\[workspace.metadata.hajime\]/,/^\[/s/^build = \([0-9]*\)/\1/p' "$file")
case "$build" in *[!0-9]*|"") echo "Windows のビルド番号が読めません: $build" >&2; exit 1 ;; esac
sed -i '' "/^\[workspace.package\]/,/^\[/s/^version = \"$version\"/version = \"$next\"/; /^\[workspace.metadata.hajime\]/,/^\[/s/^build = $build/build = $((build + 1))/" "$file"
# Cargo.lock の自分の crate のバージョンも合わせる(CI は --locked でビルドする)
for crate in candidate-ui ipc settings tokens tsf; do
  sed -i '' "/^name = \"$crate\"$/{n;s/^version = \"$version\"/version = \"$next\"/;}" "$lock"
done

for platform in macos windows; do
  if [ "$("$root/tools/release/version.sh" "$platform")" != "$next" ]; then
    echo "$platform のバージョンを書き換えられませんでした" >&2
    exit 1
  fi
done
echo "v${version} → v${next}．タグは v${next}"
