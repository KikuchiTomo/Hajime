#!/bin/sh
# GitHub Actions で，Developer ID の証明書と公証の資格情報を使い捨てのキーチェーンに入れる(docs/dev/RELEASE.md)．
# 値は環境変数(GitHub の Secrets)から読み，記録に出さない．終わったら cleanup で消す．
#
# 使い方:
#   tools/macos/ci_signing.sh setup     キーチェーンを作り，証明書と公証の資格情報を入れる．
#                                       package.sh に渡す変数を $GITHUB_ENV に書く
#   tools/macos/ci_signing.sh cleanup   キーチェーンと鍵のファイルを消す
#
# setup で読む環境変数:
#   MACOS_CERTIFICATES_P12       Developer ID Application と Developer ID Installer を入れた .p12 を base64 にしたもの
#   MACOS_CERTIFICATES_PASSWORD  .p12 のパスワード
#   MACOS_NOTARY_KEY             App Store Connect の API キー(.p8 の中身)
#   MACOS_NOTARY_KEY_ID          API キーの Key ID
#   MACOS_NOTARY_ISSUER_ID       API キーの Issuer ID
set -eu
work="${RUNNER_TEMP:?RUNNER_TEMP がありません(GitHub Actions の中で動かしてください)}/hajime-signing"
keychain="$work/signing.keychain-db"
profile="hajime-notary"

case "${1:-}" in
  setup)
    : "${MACOS_CERTIFICATES_P12:?}" "${MACOS_CERTIFICATES_PASSWORD:?}" \
      "${MACOS_NOTARY_KEY:?}" "${MACOS_NOTARY_KEY_ID:?}" "${MACOS_NOTARY_ISSUER_ID:?}"
    umask 077
    mkdir -p "$work"
    # キーチェーンのパスワードはこの仕事の中でしか使わないので，その場で作る
    keychain_password=$(openssl rand -hex 24)
    security create-keychain -p "$keychain_password" "$keychain"
    security set-keychain-settings -lut 3600 "$keychain"
    security unlock-keychain -p "$keychain_password" "$keychain"
    printf '%s' "$MACOS_CERTIFICATES_P12" | base64 --decode > "$work/certificates.p12"
    security import "$work/certificates.p12" -k "$keychain" -P "$MACOS_CERTIFICATES_PASSWORD" -T /usr/bin/codesign -T /usr/bin/productbuild >/dev/null
    rm -f "$work/certificates.p12"
    # codesign と productbuild がパスワードを聞かずに鍵を使えるようにする
    security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" >/dev/null
    # 検索するキーチェーンの先頭に足す(package.sh は security find-identity で証明書を探す)
    existing=$(security list-keychains -d user | tr -d '"' | tr -s ' \n' ' ')
    # shellcheck disable=SC2086 # 既存のキーチェーンの場所に空白は無い
    security list-keychains -d user -s "$keychain" $existing
    printf '%s' "$MACOS_NOTARY_KEY" > "$work/notary.p8"
    xcrun notarytool store-credentials "$profile" --key "$work/notary.p8" --key-id "$MACOS_NOTARY_KEY_ID" \
      --issuer "$MACOS_NOTARY_ISSUER_ID" --keychain "$keychain" >/dev/null
    rm -f "$work/notary.p8"
    # 証明書が入ったことを，名前だけ確かめる(鍵の中身は出さない)
    security find-identity -v -p codesigning "$keychain" | grep -q 'Developer ID Application' \
      || { echo "Developer ID Application の証明書がありません" >&2; exit 1; }
    security find-identity -v -p basic "$keychain" | grep -q 'Developer ID Installer' \
      || { echo "Developer ID Installer の証明書がありません" >&2; exit 1; }
    {
      echo "HAJIME_NOTARY_PROFILE=$profile"
      echo "HAJIME_NOTARY_KEYCHAIN=$keychain"
    } >> "${GITHUB_ENV:?}"
    echo "署名と公証の準備ができました"
    ;;
  cleanup)
    if [ -f "$keychain" ]; then security delete-keychain "$keychain" || true; fi
    rm -rf "$work"
    ;;
  *)
    echo "使い方: $0 setup|cleanup" >&2
    exit 2
    ;;
esac
