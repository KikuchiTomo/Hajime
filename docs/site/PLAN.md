# ドキュメントサイトの計画

まだサイトは作りません．あとで作るときに文書を書き直さずに済むよう，今のうちに置き場所と書き方を決めておきます．

## 公開する場所

`ime.s90.tokyo` を案とします．s90.tokyo のブランドサイトからリンクします．

## 載せるもの

| 節 | 元の文書 | 読む人 |
|---|---|---|
| はじめに | `docs/user/tutorials/` | 初めて入れる人 |
| 使いかた | `docs/user/how-to/` | 目的がある人 |
| 設定とキー操作 | `docs/user/reference/` | 調べたい人 |
| しくみ | `docs/user/explanation/` | 理由を知りたい人 |
| 開発 | `docs/dev/`，`docs/specs/`，`docs/dev/adr/` | 貢献したい人 |
| リリースノート | GitHub の Releases から生成 | 更新した人 |

## 生成器

Astro の Starlight を第一候補とします(ADR 0004)．

- Markdown の frontmatter(`title`，`description`)と，日本語・英語の切り替えをそのまま扱える
- 全文検索(Pagefind)がビルド時に作られ，外部のサービスに頼らない
- 見た目を CSS の変数で変えられるので，`design/tokens/tokens.json` から生成した変数をそのまま使える

サイトのソースは `apps/docs-site/` に置き，本文は `docs/` を読み込みます．本文をサイトの中にコピーしないためです．

## 見た目

- `docs/dev/DESIGN-SYSTEM.md` のテーマ(`platinum` と `desk`)を使う．候補ウィンドウのモックアップを，そのままサイトの図として使う
- 外部の CDN・フォント・解析ツールは使わない．IME のプライバシーの方針(`docs/dev/SECURITY-MODEL.md`)とそろえる
- 操作を説明する図は，キーの列と画面の変化の対応がわかるアニメーションにする．「視差効果を減らす」が有効なら静止画にする

## 準備として今から守ること

- `docs/user/` の文書には frontmatter を書く
- 文書どうしのリンクは相対パスで書く(サイトでも GitHub でも同じリンクが使える)
- 図は SVG かテキストの図で書き，画像の中に文字を焼き込まない(翻訳できなくなるため)
