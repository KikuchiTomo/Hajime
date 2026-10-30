# ドキュメントサイトの計画

公式サイトは `apps/docs-site/` にあり，`https://haji.men` で公開します．s90.tokyo のブランドサイトからリンクします．

## 載せるもの

| 節 | 元の文書 | 読む人 |
|---|---|---|
| はじめに | `docs/user/tutorials/` | 初めて入れる人 |
| 使いかた | `docs/user/how-to/` | 目的がある人 |
| 設定とキー操作 | `docs/user/reference/` | 調べたい人 |
| しくみ | `docs/user/explanation/` | 理由を知りたい人 |
| 開発 | `docs/dev/`，`docs/specs/`，`docs/dev/adr/` | 貢献したい人 |
| リリースノート | GitHub の Releases から生成 | 更新した人 |

## 生成器と公開

Hugo とテーマの Hextra で作ります．

- `docs/user/` をそのまま「ドキュメント」の節として読み込む．本文をサイトの中にコピーしない
- 全文検索の索引はビルド時に作り，外部のサービスに頼らない
- ダウンロードのボタンは，ビルド時に GitHub の最新のリリースを読んで配布物へ直接リンクする

`make site` でビルドします．出力先は `make site SITE_OUT=<ディレクトリ>` で変えられます．
main で `apps/docs-site/` か `docs/user/` が変わったときと，リリースを出したときに，`.github/workflows/site.yml` が Cloudflare Workers の静的アセットとして公開します．
`haji.men` は Cloudflare のダッシュボードで Worker に付けます．

## 見た目

- `docs/dev/DESIGN-SYSTEM.md` のテーマ(`platinum` と `desk`)を使う．候補ウィンドウのモックアップを，そのままサイトの図として使う
- 外部の CDN・フォント・解析ツールは使わない．IME のプライバシーの方針(`docs/dev/SECURITY-MODEL.md`)とそろえる
- 操作を説明する図は，キーの列と画面の変化の対応がわかるアニメーションにする．「視差効果を減らす」が有効なら静止画にする

## 準備として今から守ること

- `docs/user/` の文書には frontmatter を書く
- 文書どうしのリンクは相対パスで書く(サイトでも GitHub でも同じリンクが使える)
- 図は SVG かテキストの図で書き，画像の中に文字を焼き込まない(翻訳できなくなるため)
