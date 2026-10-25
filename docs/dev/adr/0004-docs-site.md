# 0004 ドキュメントサイトは Starlight で作る

- 状態: 提案
- 日付: 2026-10-25

## 背景

使う人向けの文書と作る人向けの文書を 1 つのサイトにまとめたい．日本語と英語を出し分け，ブランドの見た目にそろえたい．外部のサービスに頼らずに検索したい．

## 判断

Astro の Starlight を使う．本文は `docs/` に置いたまま，サイトのソース(`apps/docs-site/`)から読み込む．詳しい計画は `docs/site/PLAN.md`．

## 検討したほかの案

| 案 | 採らなかった理由 |
|---|---|
| DocC | Swift の API の文書には向くが，使う人向けの文書と Windows の文書には合わない |
| VitePress | 候補として残す．言語の切り替えと検索は Starlight と同等にできる．Starlight の方が Diátaxis の 4 つの節を並べるサイドバーの設定が簡単 |
| MkDocs Material | Python の依存が増え，s90.tokyo のサイト(Vite と TypeScript)と道具がそろわない |

## 結果

サイトを作るのは機能がそろってから．それまでは frontmatter と相対リンクの決まりだけを守る．
