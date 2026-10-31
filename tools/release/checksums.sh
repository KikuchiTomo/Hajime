#!/bin/sh
# 配布物(.pkg と .msi)の SHA-256 の一覧を，配布物の置き場所に SHA256SUMS.txt として書く．両方の OS の配布物がそろっていなければ止まる
# 使い方: tools/release/checksums.sh <配布物の置き場所>
set -eu
dist=$1
for pattern in '*.pkg' '*.msi'; do
  if [ -z "$(find "$dist" -maxdepth 1 -type f -name "$pattern")" ]; then
    echo "配布物($pattern)がありません: $dist" >&2
    exit 1
  fi
done
files=$(find "$dist" -maxdepth 1 -type f \( -name '*.pkg' -o -name '*.msi' \) -exec basename {} \; | sort)
# shellcheck disable=SC2086 # ファイル名に空白は無い(Hajime-<バージョン>.pkg・.msi)
(cd "$dist" && sha256sum $files > SHA256SUMS.txt)
