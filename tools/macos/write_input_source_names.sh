#!/bin/sh
# 入力ソースの表示名(InfoPlist.strings)を，ビルドしたアプリの中に書く．Xcode のビルドの最後に呼ばれる．
# 名前は，日本語の入力モードとアプリが HAJIME_DISPLAY_NAME(本番ははじめ，開発版ははじめ Dev)，英字の入力モードが HAJIME_DISPLAY_NAME_EN(Hajime)．
# 英語の環境ではアプリの名前も HAJIME_DISPLAY_NAME_EN にする．入れるときに make install-macos NAME=… で日本語の名前を変えられる．
# これが無いと，入力ソースの名前が com.apple.inputmethod.Japanese のように ID のまま出る
set -eu
resources="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
name="${HAJIME_DISPLAY_NAME:-$PRODUCT_NAME}"
english="${HAJIME_DISPLAY_NAME_EN:-$PRODUCT_NAME}"
# strings の文字列の中に書くので，" と \ と改行は使えない
case "$name$english" in
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
"com.apple.inputmethod.Roman" = "${english}";
STRINGS
cat > "$resources/en.lproj/InfoPlist.strings" <<STRINGS
CFBundleName = "${english}";
CFBundleDisplayName = "${english}";
"com.apple.inputmethod.Japanese" = "${name}";
"com.apple.inputmethod.Roman" = "${english}";
STRINGS
