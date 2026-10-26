---
title: 郵便番号のデータ
description: 郵便番号変換(R-13)に使うデータの出典，利用条件，毎月の更新の手順
---

## 出典と利用条件

日本郵便株式会社の「郵便番号データ(住所の郵便番号，UTF-8 版の全国一括)」を使います．

- データ: <https://www.post.japanpost.jp/service/search/zipcode/download/utf/zip/utf_ken_all.zip>
- 説明と利用条件: <https://www.post.japanpost.jp/service/search/zipcode/download/readme.html>
  - 「郵便番号データに限っては日本郵便株式会社は著作権を主張しません．自由に配布していただいて結構です．」と書かれています(2026-10-26 に確かめた)
  - UTF-8 版は 1 つの郵便番号を 1 行に書き，読み仮名は全角カタカナです(<https://www.post.japanpost.jp/service/search/zipcode/download/utf-zip.html>)

## 置き場所

`data/postal/postal-codes.tsv` に「郵便番号<タブ>住所(<タブ>住所…)」の形で置きます(約 12 万行，5MB)．Git にそのまま入れ，毎月の更新は差分で読めるようにします．アプリには `apps/macos/project.yml` で同梱し，利用者の Mac では通信しません．

整え方は `tools/postal/normalize.py` に書いてあります．

- 住所は 都道府県 + 市区町村 + 町域
- 「以下に掲載がない場合」「〜の次に番地がくる場合」「〜一円」は町域を付けない
- 括弧の中(「大通西(１〜１９丁目)」の番地や丁目の範囲)は除く
- 同じ郵便番号に町域がいくつもあれば，重ねずに並べる

## 毎月の更新

日本郵便のデータは毎月末に更新されます．

1. main から `chore/postal-YYYYMM` のブランチを作る
2. `tools/postal/update.sh` を動かす(取ってきて整え，`data/postal/postal-codes.tsv` を書き直す)
3. `git diff --stat` で変わった行の数を見て，極端に多くないか(全体の数 % を超えていないか)を確かめる
4. `make test` を通し，「chore(data): 郵便番号のデータを YYYY 年 MM 月版にする」の PR にする
