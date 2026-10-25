#!/bin/sh
# macOS の入力メソッドをビルドし，~/Library/Input Methods に入れて有効にする．
#
# 使い方: tools/macos/install.sh [Release|Dev]
#   Release: 本番(s90.tokyo IME)
#   Dev:     開発版(s90.tokyo IME Dev)．本番と別の入力ソース・別の学習データになるので，並べて試せる．最適化は本番と同じ
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
. "$root/tools/macos/variant.sh"
variant "${1:-Release}"

# 署名に使う証明書(決め方は variant.sh の signing_identity)．
# アドホック署名のままだと Gatekeeper に拒まれ，入力ソースとして選べないことがある
identity=$(signing_identity) || exit 1
if [ -z "$identity" ]; then
  echo "Apple Development の証明書が見つからないので，アドホック署名にします(入力ソースとして選べないことがあります)"
  identity="-"
fi
echo "署名: $(identity_name "$identity") $identity"

# Zenzai のモデルを取得してハッシュを確かめる(取得済みなら確かめるだけ)．アプリに入れて Zenzai を有効にするため
"$root/tools/models/fetch_zenzai.sh"

cd "$root/apps/macos"
xcodegen generate --quiet
xcodebuild -project S90IME.xcodeproj -scheme S90IME -configuration "$configuration" -derivedDataPath build build -quiet
built="build/Build/Products/$configuration/$app_name.app"
if [ "$identity" != "-" ]; then
  # ビルドはアドホック署名で行い，できたアプリだけを証明書で署名し直す．
  # xcodebuild に証明書を渡すと，依存パッケージのリソースにまでチームの指定を求められるため
  entitlements=$(find build/Build/Intermediates.noindex -path "*$configuration*" -name "$app_name.app.xcent" | head -1)
  codesign --force --deep --options runtime --timestamp=none --entitlements "$entitlements" --sign "$identity" "$built"
fi

# 動いている古い版を止めてから入れ替える．次にキーを打ったとき OS が新しい版を起こす
pkill -x "$app_name" 2>/dev/null || true
# 置き場所は管理者の権限が要るので sudo を使う(パスワードを聞かれる)
sudo mkdir -p "$destination"
sudo rm -rf "$destination/$app_name.app"
sudo cp -R "$built" "$destination/"
sudo chown -R root:wheel "$destination/$app_name.app"
swift "$root/tools/macos/input_source.swift" enable "$destination/$app_name.app"
echo "入れました: $destination/$app_name.app"
echo "初めて入れたときは，一度ログアウトしてログインし直し，システム設定 > キーボード > 入力ソース で「${app_name}」を足してください"
echo "2 回目からは入れ直すだけで，次にキーを打ったときに新しい版が動きます"
