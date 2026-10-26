#!/bin/sh
# リポジトリに書いた OS ごとのバージョンを出す(docs/dev/adr/0008-versioning.md)．
# 使い方: tools/release/version.sh macos|windows
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
case "${1:-}" in
  macos) sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' "$root/apps/macos/project.yml" ;;
  windows) sed -n '/^\[workspace.package\]/,/^\[/s/^version = "\(.*\)"/\1/p' "$root/apps/windows/Cargo.toml" ;;
  *) echo "使い方: $0 macos|windows" >&2; exit 2 ;;
esac
