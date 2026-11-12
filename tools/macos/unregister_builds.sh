#!/bin/sh
# ビルドしたアプリ(apps/macos/build の中)を LaunchServices の登録から外す．
# xcodebuild はビルドしたアプリを LaunchServices に登録する．入れた入力メソッドと同じバンドル ID のアプリが作業用のフォルダに
# 登録されていると，OS が入れたほうを入力ソースから外すことがある．外れると入力メニューで切り替えられず，
# 入力ソースを消して足し直すまで使えない．ビルドしたあとに呼び，入れたものだけが登録された状態にする
#
# 使い方: tools/macos/unregister_builds.sh
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
build="$root/apps/macos/build"
[ -d "$build" ] || exit 0
# 中に入れた更新用のアプリも別に登録されるので，入れ子の .app も外す．登録されていないアプリでは失敗するが，外す必要が無いので続ける
find "$build" -type d -name '*.app' | while IFS= read -r app; do
  "$lsregister" -u "$app" 2>/dev/null || true
done
