#!/bin/sh
# 入力ソースの表示名(InfoPlist.strings)を，ビルドしたアプリの中に書く．Xcode のビルドの最後に呼ばれる．
# アプリと日本語の入力モードの名前は HAJIME_DISPLAY_NAME(本番は Hajime IME，開発版は Hajime IME Dev)．
# 英字の入力モードの名前は，そのあとに HAJIME_ROMAN_MODE_SUFFIX(日本語の環境)か HAJIME_ROMAN_MODE_SUFFIX_EN(英語の環境)を付けたもの．
# 入れるときに make install-macos NAME=… で名前を変えられる．
# これが無いと，入力ソースの名前が com.apple.inputmethod.Japanese のように ID のまま出る
set -eu
resources="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
name="${HAJIME_DISPLAY_NAME:-$PRODUCT_NAME}"
roman="$name${HAJIME_ROMAN_MODE_SUFFIX:+ $HAJIME_ROMAN_MODE_SUFFIX}"
roman_english="$name${HAJIME_ROMAN_MODE_SUFFIX_EN:+ $HAJIME_ROMAN_MODE_SUFFIX_EN}"
# strings の文字列の中に書くので，" と \ と改行は使えない
case "$roman$roman_english" in
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
"com.apple.inputmethod.Roman" = "${roman}";
STRINGS
cat > "$resources/en.lproj/InfoPlist.strings" <<STRINGS
CFBundleName = "${name}";
CFBundleDisplayName = "${name}";
"com.apple.inputmethod.Japanese" = "${name}";
"com.apple.inputmethod.Roman" = "${roman_english}";
STRINGS
