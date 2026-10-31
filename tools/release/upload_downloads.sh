#!/bin/sh
# 作った配布物を Cloudflare R2 に置き，https://haji.men/download/ から配る(apps/docs-site/worker/downloads.js)．
# バージョンのフォルダ(v<バージョン>/)に配布物と SHA256SUMS.txt を置いてから，最新のバージョン(latest.json)を書き換える．
# 使い方: tools/release/upload_downloads.sh <バージョン> <配布物の置き場所>
# R2 の S3 互換 API に AWS CLI で送る．AWS_ACCESS_KEY_ID と AWS_SECRET_ACCESS_KEY(このバケットだけに書ける R2 のアクセスキー)と
# CLOUDFLARE_ACCOUNT_ID が要る
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
version=$1
dist=$(cd "$2" && pwd)
site="$root/apps/docs-site"
# バケットの名前は Worker の設定(wrangler.jsonc の r2_buckets)と同じものを使う
bucket=$(sed -n 's/^ *"bucket_name": *"\([^"]*\)".*/\1/p' "$site/wrangler.jsonc")
if [ -z "$bucket" ] || [ "$(printf '%s\n' "$bucket" | wc -l | tr -d ' ')" -ne 1 ]; then
  echo "wrangler.jsonc から R2 のバケットを 1 つに決められません" >&2
  exit 1
fi

endpoint="https://${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID が要ります}.r2.cloudflarestorage.com"
put() {
  aws s3api put-object --endpoint-url "$endpoint" --region auto \
    --bucket "$bucket" --key "$1" --body "$2" --content-type "$3" --output text --query ETag > /dev/null
}

"$root/tools/release/checksums.sh" "$dist"
pkg=$(find "$dist" -maxdepth 1 -type f -name '*.pkg')
msi=$(find "$dist" -maxdepth 1 -type f -name '*.msi')
for file in "$pkg" "$msi" "$dist/SHA256SUMS.txt"; do
  if [ ! -f "$file" ] || [ "$(printf '%s\n' "$file" | wc -l | tr -d ' ')" -ne 1 ]; then
    echo "配布物がそろっていません: $dist" >&2
    exit 1
  fi
done
folder="v$version"
put "$folder/$(basename "$pkg")" "$pkg" application/octet-stream
put "$folder/$(basename "$msi")" "$msi" application/x-msi
put "$folder/SHA256SUMS.txt" "$dist/SHA256SUMS.txt" "text/plain; charset=utf-8"

# 配布物をすべて置いてから最新のバージョンを切り替える(途中で失敗しても，前のバージョンへの転送が残る)
latest="$dist/latest.json"
printf '{"version":"%s","files":{"macos":"%s/%s","windows":"%s/%s"}}\n' \
  "$version" "$folder" "$(basename "$pkg")" "$folder" "$(basename "$msi")" > "$latest"
put latest.json "$latest" application/json
echo "置きました: https://haji.men/download/$folder/"
