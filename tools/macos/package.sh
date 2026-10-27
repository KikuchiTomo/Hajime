#!/bin/sh
# 配布物(.pkg)を作る．Zenzai のモデルを入れた本番のアプリを /Library/Input Methods に入れる .pkg になる．
#
# 使い方: tools/macos/package.sh
# 出力:   apps/macos/build/dist/s90.tokyo-IME-<バージョン>.pkg
#
# 署名と公証は，使える証明書と設定があるときだけ行う．
#   S90_APP_IDENTITY        アプリの署名(名前か SHA-1)．無ければ，公証するときは Developer ID Application，
#                           しないときは make install-macos と同じ決め方(入っているバージョンと同じチームの証明書．variant.sh)
#   S90_INSTALLER_IDENTITY  .pkg の署名．無ければ Developer ID Installer の証明書．どちらも無ければ署名しない
#   S90_NOTARY_PROFILE      公証に使う notarytool のキーチェーンのプロファイル名．無ければ公証しない(手元に入れる .pkg)
#                           (作り方: xcrun notarytool store-credentials <名前>)
#   S90_NOTARY_KEYCHAIN     公証のプロファイルを入れたキーチェーン．無ければ既定のキーチェーン(CI は ci_signing.sh が作る)
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)

. "$root/tools/macos/variant.sh"
variant Release
# productbuild の --sign は証明書の名前(Common Name)を受け取る(man productbuild)．同じ名前が 2 つあると選べないので止める
installer_identity=${S90_INSTALLER_IDENTITY:-$(identities basic | awk -F '\t' '$2 ~ /^Developer ID Installer/ { print $2; exit }')}
if [ -n "$installer_identity" ]; then
  # 同じ証明書が 2 つのキーチェーンに出ることがあるので，SHA-1 で重ねずに数える
  installer_count=$(identities basic | awk -F '\t' -v name="$installer_identity" '$2 == name { print $1 }' | sort -u | wc -l | tr -d ' ')
  if [ "$installer_count" -eq 0 ]; then
    echo "「${installer_identity}」という名前の証明書がありません．証明書の名前をそのまま指定してください(security find-identity -v -p basic で確かめられます)" >&2
    exit 1
  fi
  if [ "$installer_count" -gt 1 ]; then
    echo "「${installer_identity}」という名前の証明書が 2 つあり，.pkg の署名に使う証明書を選べません．古い方をキーチェーンから外してください" >&2
    exit 1
  fi
fi
notary_profile=${S90_NOTARY_PROFILE:-}
notary_keychain=${S90_NOTARY_KEYCHAIN:-}
# 公証に出して結果を待つ．受け付けられなければ(Accepted でなければ)，Apple の審査の記録(問題のあるファイルと理由)を出して止まる
notarize() {
  set -- "$1" --keychain-profile "$notary_profile"
  if [ -n "$notary_keychain" ]; then set -- "$@" --keychain "$notary_keychain"; fi
  file=$1
  shift
  result=$(xcrun notarytool submit "$file" "$@" --wait --output-format json)
  submission=$(printf '%s' "$result" | plutil -extract id raw -o - -)
  status=$(printf '%s' "$result" | plutil -extract status raw -o - -)
  echo "公証の結果: $status($submission)"
  if [ "$status" != "Accepted" ]; then
    xcrun notarytool log "$submission" "$@"
    echo "公証が受け付けられませんでした．上の記録の issues に，直すファイルと理由があります" >&2
    exit 1
  fi
}
if [ -n "${S90_APP_IDENTITY:-}" ]; then
  app_identity=$S90_APP_IDENTITY
elif [ -n "$notary_profile" ]; then
  # ほかの人に配る .pkg．公証には Developer ID の署名が要る
  app_identity=$(code_signing_identities | awk -F '\t' '$2 ~ /^Developer ID Application/ { print $1; exit }')
else
  # 手元に入れる .pkg．入っているバージョンと違うチームで署名すると起動の途中で止まるので，同じチームの証明書にする
  app_identity=$(signing_identity) || exit 1
fi
app_identity_name=$(identity_name "$app_identity")
app_identity_name=${app_identity_name:-$app_identity}
if [ -n "$notary_profile" ]; then
  case "$app_identity_name" in
    "Developer ID Application"*) ;;
    *) echo "公証するには Developer ID Application の証明書で署名します(今の選択: ${app_identity_name:-なし})．S90_APP_IDENTITY で指定してください" >&2; exit 1 ;;
  esac
fi

"$root/tools/models/fetch_zenzai.sh"

cd "$root/apps/macos"
xcodegen generate --quiet
work="build/package"
rm -rf "$work"
mkdir -p "$work/root" "$work/scripts" build/dist
xcodebuild -project S90IME.xcodeproj -scheme S90IME -configuration "$configuration" -destination "generic/platform=macOS" -derivedDataPath build build -quiet
# 拡張属性(._ のファイル)を配布物に入れない
ditto --norsrc --noextattr "build/Build/Products/$configuration/$app_name.app" "$work/root/$app_name.app"
app="$work/root/$app_name.app"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")

entitlements=$(find build/Build/Intermediates.noindex -path "*$configuration*" -name "$app_name.app.xcent" | head -1)
# 中の部品(Frameworks の dylib とフレームワーク)から順に署名し，最後にアプリを権限つきで署名する(Apple の勧める順．--deep は部品を取りこぼすことがある)
sign_app() {
  for nested in "$app/Contents/Frameworks/"*; do
    [ -e "$nested" ] || continue
    codesign --force "$@" "$nested"
  done
  codesign --force "$@" --entitlements "$entitlements" "$app"
}
if [ -n "$app_identity" ] && [ "$app_identity" != "-" ]; then
  case "$app_identity_name" in
    "Developer ID Application"*)
      timestamp="--timestamp"
      # ほかの人に配るアプリには，デバッグのための権限(Xcode が開発用のビルドに足す get-task-allow)を付けない．
      # 付いていると公証で受け付けられない
      cp "$entitlements" "$work/entitlements.plist"
      entitlements="$work/entitlements.plist"
      # 権限の名前の「.」を入れ子の区切りと読まれないよう，「\.」と書く
      if plutil -extract 'com\.apple\.security\.get-task-allow' raw "$entitlements" >/dev/null 2>&1; then
        plutil -remove 'com\.apple\.security\.get-task-allow' "$entitlements"
      fi
      if plutil -extract 'com\.apple\.security\.get-task-allow' raw "$entitlements" >/dev/null 2>&1; then
        echo "デバッグのための権限(get-task-allow)を外せませんでした" >&2
        exit 1
      fi
      ;;
    *) timestamp="--timestamp=none" ;;
  esac
  sign_app --options runtime "$timestamp" --sign "$app_identity"
  echo "アプリの署名: $app_identity_name"
else
  # 証明書が無いときはアドホック署名にする．ハードンドランタイムは付けない．
  # ハードンドランタイムの付いたアプリは，チームの同じ署名の部品しか読み込めず(Library Validation)，
  # チームの無いアドホック署名では同梱の llama.framework を読み込めずに起動の途中で止まる
  sign_app --timestamp=none --sign -
  echo "アプリの署名に使える証明書が無いので，アドホック署名にします(ハードンドランタイムなし)"
fi
# 署名を確かめる．ハードンドランタイムが付いていてチームが無いと，同梱の部品を読み込めない
codesign --verify --deep --strict "$app"
signature=$(codesign -dv "$app" 2>&1)
if printf '%s\n' "$signature" | grep -q '^CodeDirectory.*flags=.*runtime' && printf '%s\n' "$signature" | grep -q '^TeamIdentifier=not set'; then
  echo "アプリにハードンドランタイムが付いていて，署名にチームがありません．同梱の部品を読み込めず起動できないので，作るのをやめます" >&2
  exit 1
fi

if [ -n "$notary_profile" ]; then
  ditto -c -k --sequesterRsrc --keepParent "$app" "$work/app.zip"
  notarize "$work/app.zip"
  xcrun stapler staple "$app"
fi

cp "$root/tools/macos/pkg/postinstall" "$work/scripts/postinstall"
chmod +x "$work/scripts/postinstall"
# 入れる場所を動かさない(OS は入力メソッドを決まった場所からしか読まない)
pkgbuild --analyze --root "$work/root" "$work/component.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$work/component.plist"
COPYFILE_DISABLE=1 pkgbuild --root "$work/root" --component-plist "$work/component.plist" --scripts "$work/scripts" \
  --identifier "$bundle_id" --version "$version" --install-location "$destination" "$work/component.pkg"
sed -e "s/@VERSION@/$version/g" "$root/tools/macos/pkg/distribution.xml" > "$work/distribution.xml"
output="build/dist/s90.tokyo-IME-$version.pkg"
rm -f "$output"
if [ -n "$installer_identity" ]; then
  productbuild --distribution "$work/distribution.xml" --package-path "$work" --sign "$installer_identity" "$output"
  echo ".pkg の署名: $installer_identity"
  if [ -n "$notary_profile" ]; then
    notarize "$output"
    xcrun stapler staple "$output"
    # 公証した .pkg は，Gatekeeper の検査で警告なしに開けることを確かめる
    spctl --assess --type install --verbose "$output"
  fi
else
  productbuild --distribution "$work/distribution.xml" --package-path "$work" "$output"
  echo "Developer ID Installer の証明書が無いので，.pkg は署名していません(ほかの Mac では開くときに警告が出ます)"
fi
echo "作りました: apps/macos/$output"
