---
name: hajime-docs
description: はじめのドキュメント(docs/ 以下の使う人向けの文書・開発者向けの文書・要件・仕様・ADR，README，CONTRIBUTING，SECURITY，コードのコメント，PR の説明)を書く・直すときの決まり．Diátaxis による分け方，frontmatter，将来のドキュメントサイト(Starlight)に載せるための書き方，日本語の文体を含む．Markdown を書くとき，設計を変えて文書の更新が要るとき，ADR や仕様を書くとき，「ドキュメント」「説明を書いて」「README」と言われたときは必ず使う．Use for any documentation, spec, ADR, README or comment writing in this repository.
---

# ドキュメントの決まり

地図は `docs/README.md`，サイトの計画は `docs/site/PLAN.md`．

## どこに書くか

書く前に，その文書の目的を 1 つに決める．混ざっていたら分ける．

| 目的 | 置き場所 | 書き方 |
|---|---|---|
| 初めての人が順に進めて学ぶ | `docs/user/tutorials/` | 番号付きの手順．途中で選択肢を出さない |
| 目的があって作業する | `docs/user/how-to/` | 題は「〜する」．前提・手順・確かめ方 |
| 設定やキーを調べる | `docs/user/reference/` | 表．説明の文章は短く |
| 理由やしくみを理解する | `docs/user/explanation/` | 文章．手順を書かない |
| 作る人が構成と決まりを知る | `docs/dev/` | ARCHITECTURE・GUIDELINES などに追記 |
| 判断の理由を残す | `docs/dev/adr/` | `0000-template.md` に従う |
| 何を作るか決める | `docs/specs/` | 要件の ID(R-xx)と受け入れ条件 |

## サイトに載せるための決まり

- `docs/user/` のページには frontmatter の `title` と `description` を書く
- リンクは相対パス．GitHub でもサイトでも同じリンクで開ける
- 図は SVG かテキストの図．画像の中に文字を焼き込まない
- 英語は `<名前>.en.md`．日本語を先に書く
- 1 ページに見出しの 2 階層(`##` と `###`)まで．深くなったらページを分ける

## 文体

- 日本語の文章は `japanese-writing` スキル(利用者の環境に入っている)の決まりに従う．無い環境では次を守る
  - 句読点は「，」と「．」
  - README と使う人向けの文書は「です・ます」，`docs/dev/` とスキルとコードのコメントは「だ・である」か体言止め
  - 比喩・誇張(非常に，極めて)・記号の多用を避け，何がどうなるかを具体的に書く
- コードのコメントは「なぜそうするか」を書く．何をしているかはコードで読めるようにする
- 文書の中の値(色・寸法・既定値)は，置き場所のファイルを示して抜粋にとどめる．値を二重に持たないため

## 設計とあわせて更新する文書

| 変えたもの | 更新する文書 |
|---|---|
| ディレクトリ・層・モジュール | `docs/dev/ARCHITECTURE.md` と `hajime-architecture/scripts/check_layers.py` |
| 置き場所・名前・書き方の決まり | `docs/dev/GUIDELINES.md` |
| 保存先・通信・外から読むファイル | `docs/dev/SECURITY-MODEL.md` |
| 色・寸法・テーマ | `design/tokens/tokens.json` と `docs/dev/DESIGN-SYSTEM.md` |
| 利用者が触れる設定やキー | `docs/user/reference/` |
| 判断そのもの | 新しい ADR |

## 終わる前の確認

- [ ] 目的が 1 つに絞れている(上の表のどれか 1 行)
- [ ] frontmatter・相対リンク・図の決まりを守っている
- [ ] 文中の値が置き場所のファイルと食い違っていない
- [ ] 句読点と文体がそろっている
