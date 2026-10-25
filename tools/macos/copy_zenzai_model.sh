#!/bin/sh
# Zenzai のモデルをビルドしたアプリの中に入れる．Xcode のビルドの最後に呼ばれる．
# モデルはリポジトリの外(tools/models/fetch_zenzai.sh の置き場所)にある．無ければ入れずに終わる(Zenzai なしで動く)
set -eu
model="${SRCROOT}/../../../models/zenz-v3.2-small-Q5_K_M.gguf"
destination="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Zenzai"
if [ -f "$model" ]; then
  mkdir -p "$destination"
  cp -f "$model" "$destination/"
  echo "Zenzai のモデルを入れました"
else
  echo "warning: Zenzai のモデルがありません．tools/models/fetch_zenzai.sh で取得すると Zenzai が有効になります"
fi
