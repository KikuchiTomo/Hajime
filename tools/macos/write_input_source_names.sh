#!/bin/sh
# 入力ソースの表示名(InfoPlist.strings)を，ビルドしたアプリの中に書く．Xcode のビルドの最後に呼ばれる．
# 本番(s90.tokyo IME)と開発版(s90.tokyo IME Dev)で名前を変えるため，PRODUCT_NAME から作る．
# これが無いと，入力ソースの名前が com.apple.inputmethod.Japanese のように ID のまま出る
set -eu
resources="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
mkdir -p "$resources/ja.lproj" "$resources/en.lproj"
cat > "$resources/ja.lproj/InfoPlist.strings" <<STRINGS
CFBundleName = "${PRODUCT_NAME}";
CFBundleDisplayName = "${PRODUCT_NAME}";
"com.apple.inputmethod.Japanese" = "${PRODUCT_NAME}";
"com.apple.inputmethod.Roman" = "${PRODUCT_NAME}（英字）";
STRINGS
cat > "$resources/en.lproj/InfoPlist.strings" <<STRINGS
CFBundleName = "${PRODUCT_NAME}";
CFBundleDisplayName = "${PRODUCT_NAME}";
"com.apple.inputmethod.Japanese" = "${PRODUCT_NAME} (Japanese)";
"com.apple.inputmethod.Roman" = "${PRODUCT_NAME} (English)";
STRINGS
