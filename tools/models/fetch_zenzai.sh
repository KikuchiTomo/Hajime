#!/bin/sh
# Zenzai のモデルを取得し，SHA-256 を確かめる．リポジトリには入れず，リポジトリの外に置く．
# 取得元とバージョンを変えるときは，core/Sources/HajimeEngine/ZenzaiModel.swift の値と docs/dev/adr/0006-zenzai.md を一緒に変える．
#
# 使い方: tools/models/fetch_zenzai.sh [置き場所(既定: リポジトリの 1 つ上の models/)]
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
destination=${1:-"$root/../models"}
file="zenz-v3.2-small-Q5_K_M.gguf"
# Hugging Face の Miwa-Keita/zenz-v3.2-small-gguf(Apache-2.0)．コミットを固定する
url="https://huggingface.co/Miwa-Keita/zenz-v3.2-small-gguf/resolve/c67e03e07d215c869f591b274c1631170d3e11fe/ggml-model-Q5_K_M.gguf"
# 予備の取得元．Hugging Face から取れないとき(止まっている，消えた)に使う．同じファイルを GitHub の Releases に置いてある
mirror="https://github.com/KikuchiTomo/Hajime/releases/download/models%2Fzenz-v3.2-small-c67e03e/$file"
expected="29c223d4c23327b80fd13ebb5ab2555057a46317997d5da391584ffbef0db673"

mkdir -p "$destination"
if [ ! -f "$destination/$file" ]; then
  if ! curl -sL --fail -o "$destination/$file.download" "$url"; then
    echo "Hugging Face から取れなかったので，予備の取得元から取ります" >&2
    curl -sL --fail -o "$destination/$file.download" "$mirror"
  fi
  mv "$destination/$file.download" "$destination/$file"
fi
actual=$(shasum -a 256 "$destination/$file" | awk '{ print $1 }')
if [ "$actual" != "$expected" ]; then
  echo "SHA-256 が一致しません．ファイルを消します: $actual" >&2
  rm -f "$destination/$file"
  exit 1
fi
echo "確かめました: $destination/$file"
