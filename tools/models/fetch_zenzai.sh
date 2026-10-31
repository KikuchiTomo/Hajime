#!/bin/sh
# Zenzai のモデル(small と xsmall)を取得し，SHA-256 を確かめる．リポジトリには入れず，リポジトリの外に置く．
# 取得元とバージョンを変えるときは，core/Sources/HajimeEngine/ZenzaiModel.swift の値・tools/windows/fetch_zenzai.ps1・docs/dev/adr/0006-zenzai.md を一緒に変える．
#
# 使い方: tools/models/fetch_zenzai.sh [置き場所(既定: リポジトリの 1 つ上の models/)]
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
destination=${1:-"$root/../models"}
mkdir -p "$destination"

# 1 つのモデルを取って確かめる．取得元は Hugging Face(コミットを固定)．取れないとき(止まっている，消えた)は，
# 同じファイルを置いた GitHub の Releases(予備の取得元)から取る
fetch() {
  file=$1 url=$2 mirror=$3 expected=$4
  if [ ! -f "$destination/$file" ]; then
    if ! curl -sL --fail -o "$destination/$file.download" "$url"; then
      echo "Hugging Face から取れなかったので，予備の取得元から取ります: $file" >&2
      curl -sL --fail -o "$destination/$file.download" "$mirror"
    fi
    mv "$destination/$file.download" "$destination/$file"
  fi
  actual=$(shasum -a 256 "$destination/$file" | awk '{ print $1 }')
  if [ "$actual" != "$expected" ]; then
    echo "SHA-256 が一致しません．ファイルを消します: $file $actual" >&2
    rm -f "$destination/$file"
    exit 1
  fi
  echo "確かめました: $destination/$file"
}

# Miwa-Keita/zenz-v3.2-small-gguf(Apache-2.0)
fetch "zenz-v3.2-small-Q5_K_M.gguf" \
  "https://huggingface.co/Miwa-Keita/zenz-v3.2-small-gguf/resolve/c67e03e07d215c869f591b274c1631170d3e11fe/ggml-model-Q5_K_M.gguf" \
  "https://github.com/KikuchiTomo/Hajime/releases/download/models%2Fzenz-v3.2-small-c67e03e/zenz-v3.2-small-Q5_K_M.gguf" \
  "29c223d4c23327b80fd13ebb5ab2555057a46317997d5da391584ffbef0db673"
# Miwa-Keita/zenz-v3.2-xsmall-gguf(Apache-2.0)．設定の「Zenzai のモデル」で速さを優先するときと併用するときに使う
fetch "zenz-v3.2-xsmall-Q5_K_M.gguf" \
  "https://huggingface.co/Miwa-Keita/zenz-v3.2-xsmall-gguf/resolve/4f5423f0fad41a73b1242eb96fe5c12ae4fdca83/ggml-model-Q5_K_M.gguf" \
  "https://github.com/KikuchiTomo/Hajime/releases/download/models%2Fzenz-v3.2-xsmall-4f5423f/zenz-v3.2-xsmall-Q5_K_M.gguf" \
  "00c64b3d318045a708d0cad5434faccab10f5481a49e6362864551fd0995fa58"
