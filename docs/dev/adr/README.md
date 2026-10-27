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
| [0005](0005-candidate-presentation.md) | 候補の出し方は一覧と文節格子の 2 つにし，文節が 2 つ以上なら文節格子にする | 置き換え(0007) |
| [0006](0006-zenzai.md) | かな漢字変換に Zenzai を使う | 採用 |
| [0007](0007-branch-map.md) | 変換の候補は文の分岐図で出す | 採用 |
| [0008](0008-versioning.md) | バージョン番号の付け方 | 採用 |
| [0009](0009-keymap.md) | キー操作は状態・キー・コマンドの表で決める | 採用 |
| [0010](0010-ipc-message-format.md) | Windows のプロセス間のメッセージは長さ付きの JSON にし，定義から両方の言語の型を作る | 採用 |
| [0011](0011-distribution.md) | 配布の経路 | 採用 |
| [0012](0012-linux.md) | Linux 版の組み立て | 提案 |
| [0013](0013-windows-settings-direct2d.md) | Windows の設定の画面は Direct2D で描く | 採用 |
| [0014](0014-zenzai-on-slow-machines.md) | Zenzai が遅い環境では，打鍵が止まる前の表示に Zenzai を使わず，打鍵の合間に追いかけて求める | 採用 |
| [0015](0015-windows-setup-wizard.md) | Windows 版にインストール後の再起動の案内と，実演つきの初期設定ウィザードを置く | 採用 |
