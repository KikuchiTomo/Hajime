#!/bin/sh
# Zenzai のモデル(small と xsmall)をビルドしたアプリの中に入れる．Xcode のビルドの最後に呼ばれる．
# モデルはリポジトリの外(tools/models/fetch_zenzai.sh の置き場所)にある．無いモデルは入れずに終わる(small が無ければ Zenzai なしで動く)
set -eu
destination="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Zenzai"
for file in zenz-v3.2-small-Q5_K_M.gguf zenz-v3.2-xsmall-Q5_K_M.gguf; do
  model="${SRCROOT}/../../../models/$file"
  if [ -f "$model" ]; then
    mkdir -p "$destination"
    cp -f "$model" "$destination/"
    echo "Zenzai のモデルを入れました: $file"
  else
    echo "warning: Zenzai のモデルがありません: ${file}．tools/models/fetch_zenzai.sh で取得してください"
  fi
done
