#!/bin/sh
# 入力ソースの表示名(InfoPlist.strings)を，ビルドしたアプリの中に書く．Xcode のビルドの最後に呼ばれる．
# アプリの名前は HAJIME_DISPLAY_NAME(本番は Hajime IME，開発版は Hajime IME Dev)．
# 入力モードの名前(メニューバーと入力メニューに出る)は，日本語のモードが HAJIME_JAPANESE_MODE_NAME(本番は「はじめ」)，
# 英字のモードが HAJIME_ROMAN_MODE_NAME(本番は「Hajime」)．メニューバーは幅が狭いので，アプリの名前より短くしてある．
# 入れるときに make install-macos NAME=… で名前を変えられる(3 つとも同じ名前になる)．
# これが無いと，入力ソースの名前が com.apple.inputmethod.Japanese のように ID のまま出る
set -eu
resources="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
name="${HAJIME_DISPLAY_NAME:-$PRODUCT_NAME}"
japanese="${HAJIME_JAPANESE_MODE_NAME:-$name}"
roman="${HAJIME_ROMAN_MODE_NAME:-$name}"
# strings の文字列の中に書くので，" と \ と改行は使えない
case "$name$japanese$roman" in
  *'"'* | *'\'* | *'
'*)
    echo "入力メニューの名前に \" と \\ と改行は使えません" >&2
    exit 1
    ;;
esac
mkdir -p "$resources/ja.lproj" "$resources/en.lproj"
for language in ja en; do
  cat > "$resources/$language.lproj/InfoPlist.strings" <<STRINGS
CFBundleName = "${name}";
CFBundleDisplayName = "${name}";
"com.apple.inputmethod.Japanese" = "${japanese}";
"com.apple.inputmethod.Roman" = "${roman}";
STRINGS
done
