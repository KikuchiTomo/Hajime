# 外部から取り込んだスキル

次のスキルは [anthropics/skills](https://github.com/anthropics/skills) のコミット `dbd4588f9e1033efb41dad4bef2f7947c8993d44`(2026-10-09)から取り込んだものです．
いずれも Apache License 2.0 で，ライセンスの全文は各ディレクトリの `LICENSE.txt` にあります．中身は変えていません．

| スキル | 使いどころ |
|---|---|
| `skill-creator` | このリポジトリのスキルを作る・直す・評価する(`evals/evals.json` の実行) |
| `frontend-design` | ドキュメントサイトとモックアップの Web の画面の品質の基準 |
| `webapp-testing` | ドキュメントサイトとモックアップを Playwright で確かめる |

`doc-coauthoring` はライセンスの表示が無いため取り込んでいません．

更新するときは，同じリポジトリの新しいコミットから上書きし，この表のコミットを書き換えます．

## このリポジトリ独自のスキル

| スキル | 使いどころ |
|---|---|
| `hajime-architecture` | 置き場所・層・依存の向き・SOLID/DRY |
| `hajime-security` | 入力内容・保存・通信・IPC・unsafe・依存・CI |
| `hajime-swift` | Swift(core と macOS) |
| `hajime-windows` | Rust(TSF と Windows のプロセス) |
| `hajime-design` | 見た目とデザイントークン |
| `hajime-docs` | ドキュメント・ADR・仕様 |
| `hajime-review` | コミットや PR の前のレビュー |
| `hajime-upstream-port` | azooKey の fork からの持ち込み |
