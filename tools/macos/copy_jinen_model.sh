#!/bin/sh
# 合議(ADR 0016 の案 2)に使う Jinen モデル(small と xsmall)をビルドしたアプリの中に入れる．Xcode のビルドの最後に呼ばれる．
# モデルはリポジトリの外(tools/models/fetch_zenzai.sh の置き場所)にある．無いモデルは入れずに終わる(どちらも無ければ合議なしで動く)
set -eu
destination="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Jinen"
for file in jinen-v2-small-Q5_K_M.gguf jinen-v2-xsmall-Q5_K_M.gguf; do
  model="${SRCROOT}/../../../models/$file"
  if [ -f "$model" ]; then
    mkdir -p "$destination"
    cp -f "$model" "$destination/"
    echo "Jinen モデルを入れました: $file"
  else
    echo "warning: Jinen モデルがありません: ${file}．tools/models/fetch_zenzai.sh で取得してください"
  fi
done
