# リポジトリの決まり

GitHub の設定と，ブランチ・PR・マージの決まりです．設定は `tools/github/apply_repository_settings.sh` で当てます．設定を変えるときは，このスクリプトとこの文書を同じ PR で変えます．画面から直接変えると，どう設定したかが残らないためです．

## マージ

- **スカッシュマージだけ**を許しています．マージコミットとリベースマージは使えません
- main のコミットは「PR のタイトル」の 1 行になり，本文は付きません．PR の中のコミットは main には残りません
- マージしたブランチは自動で消えます

PR のタイトルは，そのまま main のコミットになるので，コミットと同じ形で書きます．

```
種類(スコープ): 内容
```

- 種類: `feat` `fix` `docs` `refactor` `perf` `test` `build` `ci` `chore` `revert`
- スコープ: `core` `macos` `windows` `protocol` `design` `docs` `adr` `skills` `ci` `repo` `deps`
- 内容は日本語で 1 行．比喩を使わず，その PR で変えたことだけを書く
- 例: `feat(core): ¥ キーに割り当てる文字をプロファイルごとに決める`

この形になっていないと，`pr-title` の検査が通らずマージできません．Dependabot の PR は英語のタイトルになりますが，形は合っているので通ります．

## main を守るルール(ルールセット「main を守る」)

| ルール | 内容 |
|---|---|
| PR を通す | main に直接 push できない．承認の数は 0(一人で開発しているため．人が増えたら 1 にする) |
| 会話の解決 | PR のレビューのコメントをすべて解決してからマージする |
| 検査 | `lint`(skills・文言・層・コントラスト・生成したファイル)，`core-macos`(core のテスト)，`app-macos`(macOS のアプリのビルド)，`pr-title` が通ること．main の最新を取り込んだ状態で通ること |
| 履歴 | 直線の履歴だけ．force push とブランチの削除はできない |

管理者もこのルールを迂回できません．どうしても必要なときは，スクリプトの `bypass_actors` を変える PR を出します．

## ブランチ

- 名前は `種類/内容`(例: `feat/yen-key-policy`，`fix/candidate-window-position`)
- 手元では bare とワークツリーの構成で，ブランチごとにワークツリーを作る(`git wt new`)

## セキュリティの機能

- Dependabot の脆弱性のアラートと，脆弱性を直す自動の PR
- 秘密情報(API キーなど)の検出と，含まれる push の拒否
- 脆弱性の非公開の報告(`SECURITY.md`)

## 依存の更新(Dependabot)

`.github/dependabot.yml` で，GitHub Actions と Swift のパッケージ(`core/`)を毎週月曜に確かめます．

- 公開から 7 日たっていないバージョンは提案しない(乗っ取られたバージョンを掴まないため)
- GitHub Actions はコミットの SHA で固定し，同じ行の末尾に `# v7.0.1` のようにバージョンを書く．Dependabot はこのコメントも一緒に更新する
- 更新の PR は，変更履歴を読み，CI が通ってからスカッシュマージする．メジャーバージョンの更新は，破壊的な変更が無いかを確かめてから入れる
- 変換エンジンは fork を revision で固定しているので Dependabot の対象になりません．更新の手順は `docs/dev/UPSTREAM.md`

## テンプレート

| 置き場所 | 用途 |
|---|---|
| `.github/ISSUE_TEMPLATE/1-bug.yml` | 不具合 |
| `.github/ISSUE_TEMPLATE/2-feature.yml` | 機能の提案 |
| `.github/ISSUE_TEMPLATE/3-design.yml` | 見た目の提案 |
| `.github/ISSUE_TEMPLATE/4-docs.yml` | 文書の誤りや不足 |
| `.github/PULL_REQUEST_TEMPLATE.md` | PR |
| `.github/release.yml` | リリースノートの節の分け方(ラベルで分ける) |

空の Issue は作れません．脆弱性は Issue ではなく非公開の報告に誘導しています．

## ラベル

`type:` は種類，`scope:` は範囲を表し，コミットの種類とスコープに対応させています．リリースノートは `type:` のラベルで節を分けるので，PR には `type:` のラベルを付けます．
