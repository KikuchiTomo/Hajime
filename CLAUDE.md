# CLAUDE.md

Hajime IME は azooKey をもとにした macOS / Windows 向けの日本語入力システム．

作業の前に `docs/dev/ARCHITECTURE.md` と `docs/dev/GUIDELINES.md` を読み，配置・命名・層の決まりに従うこと．
要件は `docs/specs/REQUIREMENTS.md`(R-xx)．設計の判断は `docs/dev/adr/`．

## スキル

作業の種類に応じて `.claude/skills/` のスキルを使う．複数に当てはまるときはすべて使う．

| 作業 | スキル |
|---|---|
| 型・ファイル・モジュールを作る，移す，分ける | `hajime-architecture` |
| 入力内容・ログ・保存・通信・IPC・unsafe・依存・CI に触れる | `hajime-security` |
| Swift を書く | `hajime-swift` |
| Rust / TSF / Windows を書く | `hajime-windows` |
| 見た目・色・寸法・UI | `hajime-design`(Web の画面は `frontend-design` も) |
| 文書・ADR・仕様・コメント | `hajime-docs` |
| コミットや PR の前 | `hajime-review` |
| azooKey の fork から持ち込む | `hajime-upstream-port` |
| スキルを作る・直す | `skill-creator` |

## 決まり(抜粋)

- 製品名は「Hajime IME」と書く(文書・画面の文言・インストーラー・PR のすべて)．「はじめ」「Hajime」だけでは呼ばない
- 入力した文字列・読み・候補をログや通信に出さない．既定では一切通信しない
- 値をコードに直接書かない(色と寸法は `design/tokens/`，既定値は `DefaultSettings.swift`)
- 具象の組み立ては composition root だけ．シングルトンを作らない
- 依存を増やす前に相談する．追加するときは版を固定する
- 変更後は `make check` と `make test` を通す
- 利用者から見える変更は `CHANGELOG.md` の「未リリース」に載せる．リリースノートとアプリの「更新を確認」の変更点になる．行は利用者が書くので，エージェントは `CHANGELOG.md` を書き換えず，会話の中で今回の更新内容(利用者から見える動き・対象の OS・PR 番号)を簡潔に伝えて，書いてもらうよう頼む
- main へは PR のスカッシュマージだけで入れる．PR のタイトルが main のコミットになるので，`種類(スコープ): 内容` の形で日本語 1 行にする(`docs/dev/REPOSITORY.md`)
- azooKey の fork は `../upstream/` にある．このリポジトリには入れない
