# 設計の判断の記録(ADR)

設計の判断を 1 つずつ記録します．ADR は Architecture Decision Record の略です．

- ファイル名は `NNNN-<kebab-case の題>.md`．番号は欠番を作らず増やす
- 書き方は [0000-template.md](0000-template.md)
- 決めたあとで判断を変えるときは，元の ADR を書き換えずに新しい ADR を足し，元の状態を「置き換え(NNNN)」にする

| 番号 | 題 | 状態 |
|---|---|---|
| [0001](0001-monorepo-and-forks.md) | 製品は新しいリポジトリで作り，azooKey は fork を参照する | 採用 |
| [0002](0002-shared-swift-core.md) | 入力の処理は OS に依存しない Swift のパッケージに置く | 採用 |
| [0003](0003-windows-out-of-process-engine.md) | Windows では変換を別のプロセスで行う | 採用 |
| [0004](0004-docs-site.md) | ドキュメントサイトは Starlight で作る | 提案 |
| [0005](0005-candidate-presentation.md) | 候補の出し方は一覧と文節格子の 2 つにし，文節が 2 つ以上なら文節格子にする | 採用 |
