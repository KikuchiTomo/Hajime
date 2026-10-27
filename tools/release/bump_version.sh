#!/bin/sh
# バージョンの PATCH か MINOR と，ビルド番号を 1 つ上げる(docs/dev/adr/0008-versioning.md)．
# MINOR を上げるときは PATCH を 0 に戻す．macOS 版と Windows 版の MINOR はそろえる(同じ MINOR なら同じ機能)
# 使い方: tools/release/bump_version.sh macos|windows [patch|minor]
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
platform=${1:-}
level=${2:-patch}
case "$level" in
  patch|minor) ;;
  *) echo "使い方: $0 macos|windows [patch|minor]" >&2; exit 2 ;;
esac

bump() {
  major=${version%%.*}; rest=${version#*.}; minor=${rest%%.*}; patch=${rest#*.}
  case "$major$minor$patch$build" in *[!0-9]*|"") echo "バージョンの書き方が読めません: $version ($build)" >&2; exit 1 ;; esac
  if [ "$level" = minor ]; then next="$major.$((minor + 1)).0"; else next="$major.$minor.$((patch + 1))"; fi
  next_build=$((build + 1))
}

case "$platform" in
  macos)
    file="$root/apps/macos/project.yml"
    version=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' "$file")
    build=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"/\1/p' "$file")
    bump
    sed -i '' "s/MARKETING_VERSION: \"$version\"/MARKETING_VERSION: \"$next\"/; s/CURRENT_PROJECT_VERSION: \"$build\"/CURRENT_PROJECT_VERSION: \"$next_build\"/" "$file"
    ;;
  windows)
    file="$root/apps/windows/Cargo.toml"
    lock="$root/apps/windows/Cargo.lock"
    version=$(sed -n '/^\[workspace.package\]/,/^\[/s/^version = "\(.*\)"/\1/p' "$file")
    build=$(sed -n '/^\[workspace.metadata.s90\]/,/^\[/s/^build = \([0-9]*\)/\1/p' "$file")
    bump
    sed -i '' "/^\[workspace.package\]/,/^\[/s/^version = \"$version\"/version = \"$next\"/; /^\[workspace.metadata.s90\]/,/^\[/s/^build = $build/build = $next_build/" "$file"
    # Cargo.lock の自分の crate の版も合わせる(CI は --locked でビルドする)
    for crate in candidate-ui ipc settings tokens tsf; do
      sed -i '' "/^name = \"$crate\"$/{n;s/^version = \"$version\"/version = \"$next\"/;}" "$lock"
    done
    ;;
  *) echo "使い方: $0 macos|windows [patch|minor]" >&2; exit 2 ;;
esac
echo "$platform: v$version → v$next (ビルド $next_build)．タグは $platform/v$next"
