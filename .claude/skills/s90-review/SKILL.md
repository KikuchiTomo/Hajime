---
name: s90-review
description: s90.tokyo IME の変更(作業中の差分，ブランチ，PR)を，このリポジトリの決まり(層と依存，SOLID/DRY，セキュリティとプライバシー，デザイン，ドキュメント，テスト)に照らしてレビューする．「レビューして」「見て」「確認して」「PR を出す前に」と言われたとき，実装を終えてコミットや PR に進む前には必ず使う．GitHub にはコメントせず，会話の中で指摘する．Use before committing or opening a PR, and whenever asked to review changes in this repository.
---

# s90.tokyo IME のレビュー

レビューは 1 回で全部を見ようとせず，観点ごとに分けて見る．観点ごとの決まりは各スキルにあるので，ここでは順序と出力の形だけを決める．

## 手順

1. 差分を集める: `git diff --stat main...HEAD` と `git diff main...HEAD`(作業中なら `git diff`)．PR なら `gh pr diff <番号>`
2. 変更が触れた範囲を一覧にする(core の層・macOS・Windows・protocol・design・docs・CI・依存)
3. 下の観点を順に見る．各観点で読むスキルを開き，その「終わる前の確認」を当てはめる
4. 機械的に確かめられるものは実行する
   - `python3 -I .claude/skills/s90-architecture/scripts/check_layers.py`
   - `python3 -I tools/tokens/check_contrast.py`
   - `make check` と `make test`(用意されていれば)
5. 指摘を下の形でまとめる

| 順 | 観点 | 読むスキル |
|---|---|---|
| 1 | セキュリティとプライバシー | `s90-security` |
| 2 | 層と依存，SOLID/DRY | `s90-architecture` |
| 3 | 言語ごとの書き方 | `s90-swift`，`s90-windows` |
| 4 | 要件とテスト | `docs/specs/REQUIREMENTS.md` の受け入れ条件 |
| 5 | 見た目 | `s90-design` |
| 6 | 文書の更新漏れ | `s90-docs` の「設計とあわせて更新する文書」 |

セキュリティを先に見るのは，ほかの指摘で直すうちに見落とされやすいため．

## 出力の形

```
## 結論
<そのまま入れてよいか，直してから入れるか，を 1 文で>

## 指摘
[高] <ファイル>:<行> <何が問題か．どの経路で何が起きるか>
  提案: <どう直すか>
[中] ...
[低] ...

## 確かめたこと
- check_layers.py: ok
- check_contrast.py: ok
- テスト: <実行した / 実行できなかった理由>
```

- 深刻さ: 高 = 入力内容の漏えい・入力先のアプリの異常終了・データの破損・要件の受け入れ条件を満たさない．中 = 層の違反・テストの欠落・値の直書き．低 = 名前・読みやすさ・より単純な書き方の提案
- 指摘は行を特定できる形で書く．「全体的に」で始まる指摘はしない
- 良い点を並べる節は作らない．指摘が無い観点は「確かめたこと」に 1 行書くだけにする
- 確かめていないことを確かめたように書かない．実行できなかった検査はその理由を書く
