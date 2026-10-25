#!/bin/sh
# 入れた入力メソッドを止めて消す．
#
# 使い方: tools/macos/uninstall.sh [Release|Dev] [--purge]
#   --purge: 学習データと設定(サンドボックスのコンテナ)も消す
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
. "$root/tools/macos/variant.sh"
variant "${1:-Dev}"
purge=${2:-}

if [ -d "$destination/$app_name.app" ]; then
  swift "$root/tools/macos/input_source.swift" disable "$destination/$app_name.app"
fi
pkill -x "$app_name" 2>/dev/null || true
sudo rm -rf "$destination/$app_name.app"
echo "消しました: $destination/$app_name.app"

if [ "$purge" = "--purge" ]; then
  rm -rf "$HOME/Library/Containers/$bundle_id"
  echo "学習データと設定も消しました: ~/Library/Containers/$bundle_id"
fi
