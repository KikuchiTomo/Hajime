#!/bin/sh
# 配布物(.pkg)を作る．Zenzai のモデルを入れた本番のアプリを /Library/Input Methods に入れる .pkg になる．
#
# 使い方: tools/macos/package.sh
# 出力:   apps/macos/build/dist/s90.tokyo-IME-<版>.pkg
#
# 署名と公証は，使える証明書と設定があるときだけ行う．
#   S90_APP_IDENTITY        アプリの署名．無ければ install.sh と同じ決め方(入っている版の証明書，無ければ Apple Development)
#   S90_INSTALLER_IDENTITY  .pkg の署名．無ければ Developer ID Installer の証明書．どちらも無ければ署名しない
#   S90_NOTARY_PROFILE      公証に使う notarytool のキーチェーンのプロファイル名．無ければ公証しない
#                           (作り方: xcrun notarytool store-credentials <名前>)
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)

. "$root/tools/macos/variant.sh"
variant Release
find_identity() {
  security find-identity -v -p "$1" | awk -F '"' -v kind="$2" '$0 ~ kind { print $2; exit }'
}
# アプリの署名は，指定が無ければ install.sh と同じ決め方(すでに入っている版の証明書)にする．
# 違うチームの証明書で署名すると，入れたときに起動の途中で止まるため(variant.sh)．
# ほかの人に配るときは S90_APP_IDENTITY に Developer ID Application の証明書を指定する
app_identity=${S90_APP_IDENTITY:-$(signing_identity)}
installer_identity=${S90_INSTALLER_IDENTITY:-$(find_identity basic "Developer ID Installer")}
notary_profile=${S90_NOTARY_PROFILE:-}

"$root/tools/models/fetch_zenzai.sh"

cd "$root/apps/macos"
xcodegen generate --quiet
work="build/package"
rm -rf "$work"
mkdir -p "$work/root" "$work/scripts" build/dist
xcodebuild -project S90IME.xcodeproj -scheme S90IME -configuration Release -derivedDataPath build build -quiet
# 拡張属性(._ のファイル)を配布物に入れない
ditto --norsrc --noextattr "build/Build/Products/Release/$app_name.app" "$work/root/$app_name.app"
app="$work/root/$app_name.app"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")

if [ -n "$app_identity" ]; then
  entitlements=$(find build/Build/Intermediates.noindex -path "*Release*" -name "$app_name.app.xcent" | head -1)
  case "$app_identity" in
    "Developer ID Application"*) timestamp="--timestamp" ;;
    *) timestamp="--timestamp=none" ;;
  esac
  codesign --force --deep --options runtime "$timestamp" --entitlements "$entitlements" --sign "$app_identity" "$app"
  echo "アプリの署名: $app_identity"
else
  echo "アプリの署名に使える証明書が無いので，アドホック署名のままにします"
fi

if [ -n "$notary_profile" ]; then
  ditto -c -k --sequesterRsrc --keepParent "$app" "$work/app.zip"
  xcrun notarytool submit "$work/app.zip" --keychain-profile "$notary_profile" --wait
  xcrun stapler staple "$app"
fi

cp "$root/tools/macos/pkg/postinstall" "$work/scripts/postinstall"
chmod +x "$work/scripts/postinstall"
# 入れる場所を動かさない(OS は入力メソッドを決まった場所からしか読まない)
pkgbuild --analyze --root "$work/root" "$work/component.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$work/component.plist"
COPYFILE_DISABLE=1 pkgbuild --root "$work/root" --component-plist "$work/component.plist" --scripts "$work/scripts" \
  --identifier "$bundle_id" --version "$version" --install-location "/Library/Input Methods" "$work/component.pkg"
sed -e "s/@VERSION@/$version/g" "$root/tools/macos/pkg/distribution.xml" > "$work/distribution.xml"
output="build/dist/s90.tokyo-IME-$version.pkg"
rm -f "$output"
if [ -n "$installer_identity" ]; then
  productbuild --distribution "$work/distribution.xml" --package-path "$work" --sign "$installer_identity" "$output"
  echo ".pkg の署名: $installer_identity"
  if [ -n "$notary_profile" ]; then
    xcrun notarytool submit "$output" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple "$output"
  fi
else
  productbuild --distribution "$work/distribution.xml" --package-path "$work" "$output"
  echo "Developer ID Installer の証明書が無いので，.pkg は署名していません(ほかの Mac では開くときに警告が出ます)"
fi
echo "作りました: apps/macos/$output"
