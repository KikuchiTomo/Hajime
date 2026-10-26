#!/bin/sh
# 入力ソースの表示名(InfoPlist.strings)を，ビルドしたアプリの中に書く．Xcode のビルドの最後に呼ばれる．
# 名前は S90_DISPLAY_NAME(本番は s90，開発版は s90 Dev)．入れるときに make install-macos NAME=… で変えられる．
# これが無いと，入力ソースの名前が com.apple.inputmethod.Japanese のように ID のまま出る
set -eu
resources="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
name="${S90_DISPLAY_NAME:-$PRODUCT_NAME}"
# strings の文字列の中に書くので，" と \ と改行は使えない
case "$name" in
  *'"'* | *'\'* | *'
'*)
    echo "入力メニューの名前に \" と \\ と改行は使えません" >&2
    exit 1
    ;;
esac
mkdir -p "$resources/ja.lproj" "$resources/en.lproj"
cat > "$resources/ja.lproj/InfoPlist.strings" <<STRINGS
CFBundleName = "${name}";
CFBundleDisplayName = "${name}";
"com.apple.inputmethod.Japanese" = "${name}";
"com.apple.inputmethod.Roman" = "${name}（英字）";
STRINGS
cat > "$resources/en.lproj/InfoPlist.strings" <<STRINGS
CFBundleName = "${name}";
CFBundleDisplayName = "${name}";
"com.apple.inputmethod.Japanese" = "${name} (Japanese)";
"com.apple.inputmethod.Roman" = "${name} (English)";
STRINGS
