#!/bin/sh
# かな漢字変換の辞書(hajime-dictionary)をビルドしたアプリの中に入れる．Xcode のビルドの最後に呼ばれる．
# 辞書はリポジトリの外(tools/dictionary/fetch_dictionary.sh の置き場所)にある．無ければ入れずに終わる(azooKey に同梱の辞書で動く)
set -eu
dictionary="${SRCROOT}/../../../models/hajime-dictionary-0.1.1/Dictionary"
destination="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Dictionary"
if [ -f "$dictionary/SHA256SUMS" ]; then
  rm -rf "$destination"
  mkdir -p "$destination"
  cp -R "$dictionary/" "$destination/"
  echo "かな漢字変換の辞書を入れました"
else
  rm -rf "$destination"
  echo "warning: かな漢字変換の辞書がありません．tools/dictionary/fetch_dictionary.sh で取得すると Mozc の語を足した辞書を使います"
fi
