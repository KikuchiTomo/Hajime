#!/bin/sh
# リリースのタグ(macos/v0.0.2・windows/v0.1.0)から OS とバージョンを読み，リポジトリに書いたバージョンと同じかを確かめる．
# 出力は GitHub Actions の出力の形(platform=…・version=…・tag=…)
# 使い方: tools/release/check_tag.sh <タグ>
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
tag=${1:-}
case "$tag" in
  macos/v*|windows/v*) ;;
  *) echo "タグは macos/vX.Y.Z か windows/vX.Y.Z にしてください: $tag" >&2; exit 1 ;;
esac
platform=${tag%%/*}
version=${tag#*/v}
if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "タグのバージョンが X.Y.Z の形ではありません: $tag" >&2
  exit 1
fi
written=$("$root/tools/release/version.sh" "$platform")
if [ "$written" != "$version" ]; then
  echo "タグのバージョン($version)と，リポジトリに書いたバージョン($written)が違います．tools/release/bump_patch.sh $platform で上げてからタグを付けてください" >&2
  exit 1
fi
printf 'platform=%s\nversion=%s\ntag=%s\n' "$platform" "$version" "$tag"
