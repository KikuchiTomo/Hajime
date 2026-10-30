#!/bin/sh
# リリースのタグ(v0.1.1)からバージョンを読み，リポジトリに書いた macOS と Windows のバージョンがどちらも同じかを確かめる．
# 出力は GitHub Actions の出力の形(version=…・tag=…)
# 使い方: tools/release/check_tag.sh <タグ>
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
tag=${1:-}
version=${tag#v}
if [ "$tag" = "$version" ] || ! printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "タグは vX.Y.Z にしてください: $tag" >&2
  exit 1
fi
for platform in macos windows; do
  written=$("$root/tools/release/version.sh" "$platform")
  if [ "$written" != "$version" ]; then
    echo "タグのバージョン($version)と，リポジトリに書いた $platform のバージョン($written)が違います．tools/release/bump_version.sh で上げてからタグを付けてください" >&2
    exit 1
  fi
done
printf 'version=%s\ntag=%s\n' "$version" "$tag"
