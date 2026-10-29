# セキュリティの確認項目の詳細

## 目次

1. 入力内容の漏えい
2. パスワード欄
3. 保存
4. 外から読むファイル
5. 通信
6. Windows のプロセス間通信
7. unsafe と COM
8. 供給網と CI

## 1. 入力内容の漏えい

漏れる経路は「ログ」だけではない．次をすべて疑う．

- `print`，`debugPrint`，`NSLog`，`os_log`，`Logger`(Swift)，`println!`，`eprintln!`，`dbg!`，`tracing` のマクロ(Rust)
- エラーの `localizedDescription` や `Display` に入力を埋め込む
- `assert` / `precondition` のメッセージ
- クラッシュレポート(macOS の診断情報，Windows の WER)に残るスタックの文字列
- 分析ツールやテレメトリ(このプロジェクトでは入れない)
- UI テストのスクリーンショット(CI の成果物として公開される)

`os_log` / `Logger` を使うときは，入力に由来する値を補間しない．長さや件数のような数値だけを `privacy: .public` で出す．

## 2. パスワード欄

- macOS: `IsSecureEventInputEnabled()` が真のあいだ，IME にはキーが届かない．届いた場合もアプリ側の不具合なので，変換も学習もせずに素通しする
- Windows: `ITfInputScope` で `IS_PASSWORD`，`IS_NUMBER_FULLWIDTH` などを確かめる．パスワードのときは TSF の composition を始めない

## 3. 保存

- 書き込みは同じディレクトリの一時ファイルに書いてから置き換える(macOS は `Data.write(to:options: [.atomic])`，Windows は `ReplaceFileW`)
- 作るときに権限を付ける．作ってから `chmod` すると，そのあいだに読まれる
- 学習データの暗号化は今はしない(ディスクの暗号化と OS のユーザーの分離に任せる)．入れるかどうかは ADR で決める

## 4. 外から読むファイル

- ローマ字表，ユーザー辞書のインポート，テーマ，azooKey の辞書のファイル
- 上限の例: ローマ字表 1MB，インポートする辞書 50MB．値は `DefaultSettings.swift`
- Zip を展開するときは，展開先の外を指すパス(`../`)と，展開後の大きさの上限を確かめる

## 5. 通信

- 通信する機能は core に入れず，別のモジュールにして，composition root で有効なときだけ組み立てる
- 送る内容は最小にする．前後の文脈を送るときは，送る範囲を利用者が設定で決める
- TLS の検証を外すコードを書かない

## 6. Windows のプロセス間通信

- パイプ名: `\\.\pipe\hajime.<セッション ID>.<ユーザーの SID>`
- セキュリティ記述子: 本人の SID に読み書き，それ以外は拒否
- AppContainer のアプリから接続させる必要があるときは，ACL に `ALL APPLICATION PACKAGES` を足す前に ADR を書く
- 受け取ったメッセージは，長さ → 版 → 種類 → 中身の順に検証する

## 7. unsafe と COM

- `unsafe` ブロックごとに `// SAFETY:` で，どの不変条件が守られているかを書く
- COM のメソッドの実装は `catch_unwind` で包み，panic を `E_FAIL` にする
- 参照の数の扱い(`AddRef` / `Release`)は windows クレートの型に任せ，手で数えない

## 8. 供給網と CI

- `Package.resolved` と `Cargo.lock` をコミットする
- Dependabot の PR は，変更履歴を読んでから入れる．メジャー版の更新は別の PR に分ける
- ワークフローの先頭に `permissions: contents: read` を置き，必要なジョブだけで広げる
- リリースの署名鍵は GitHub の Environments に置き，保護ルールで main からだけ使えるようにする
