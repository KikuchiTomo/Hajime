---
name: hajime-security
description: Hajime のセキュリティとプライバシーの決まりに従って実装・レビューする．IME は利用者のすべてのキー入力を受け取るため，入力文字列・候補・学習データ・ユーザー辞書・ログ・クラッシュレポート・ファイルの読み書き・設定の保存・クリップボード・通信(LLM 連携，アップデート)・Windows の名前付きパイプ・TSF の DLL・unsafe・依存の追加・CI のワークフローに触れる変更では必ず使う．「ログを足す」「デバッグ出力」「ファイルをインポート」「API キー」「外部と通信」が出てきたら，セキュリティの話に見えなくても使うこと．Use for any change touching user input, logging, persistence, IPC, network, unsafe code, dependencies or CI.
---

# Hajime のセキュリティを守る

決まりの本体は `docs/dev/SECURITY-MODEL.md`．作業の前に読み，変更がどの「守るもの」に触れるかを最初に書き出す．

IME の不具合は，パスワードの漏えいや，入力先のアプリ(Windows では DLL が読み込まれたすべてのプロセス)の異常終了につながる．速さや書きやすさよりこちらを優先する．

## 変更の種類ごとに確かめること

触れたものに当てはまる行をすべて確かめる．詳しい理由と例は `references/checklist.md`．

| 触れたもの | 確かめること |
|---|---|
| 入力文字列・読み・候補 | ログ・`print`・`os_log`・`tracing`・エラーメッセージ・クラッシュレポートに中身が出ない．`description` や `Debug` の実装にも出さない(`references/checklist.md` の「型で漏れを防ぐ」) |
| パスワード欄 | macOS の Secure Input，Windows の InputScope で素通しになる．学習しない |
| 学習・ユーザー辞書の保存 | 保存先が SECURITY-MODEL.md のとおり．権限が本人だけ(0600 / 所有者だけの ACL)．書き込みは一時ファイルからの置き換えで，途中で落ちても壊れない |
| 外から読むファイル | 読む前に大きさを確かめる．パースの失敗は `throws` で返す．パスを利用者の入力から組み立てない．テーマにコードを含めない |
| 通信 | 既定で無効(オプトイン)．送る内容を利用者が画面で確かめられる．API キーはキーチェーン / 資格情報マネージャー．ハードコードしない |
| 追加で取得するファイル | SHA-256 をリポジトリに書き，一致しなければ読み込まない |
| Windows の名前付きパイプ | 本人の SID だけの ACL，`PIPE_REJECT_REMOTE_CLIENTS`，メッセージの長さの上限，接続元のプロセスの確認 |
| `unsafe` / COM | `ffi`・`com` モジュールの中だけ．ブロックごとに `// SAFETY:` で理由を書く．COM の境界で panic を受け止める |
| 依存の追加・更新 | revision かロックファイルで固定．ライセンスとメンテナンスの状況を PR に書く |
| GitHub Actions | アクションを SHA で固定．`permissions` を最小に．`pull_request_target` で fork のコードを動かさない．秘密を fork の PR に渡さない |

## 型で漏れを防ぐ

入力の中身を持つ型は，`CustomStringConvertible` / `CustomDebugStringConvertible`(Rust は `Debug`)で中身を伏せる．うっかり `print(reading)` や `{:?}` で出しても漏れないようにするため．

```swift
struct Reading: Sendable, Equatable {
    let text: String
}
extension Reading: CustomStringConvertible, CustomDebugStringConvertible {
    // ログに出たときに中身が漏れないよう，長さだけを出す
    var description: String { "Reading(length: \(text.count))" }
    var debugDescription: String { description }
}
```

## レビューで指摘するときの書き方

指摘は「何が・どの経路で・どこに漏れる(壊れる)か」を 1 文で書き，深刻さを付ける．

```
[高] TypoCorrectionService.swift:42 補正前の文字列を logger.debug に渡しており，Console.app から入力内容が読める
```

深刻さの目安: 入力内容の漏えい・任意のコードの実行・入力先のアプリの異常終了は「高」．権限の誤りやサイズの上限の欠落は「中」．防御を重ねるための提案は「低」．

## 終わる前の確認

- [ ] 変更が触れた「守るもの」を書き出し，上の表の該当行をすべて確かめた
- [ ] 入力の中身がどの出力先にも出ないことを，`grep` で `print(`，`os_log`，`Logger`，`NSLog`，`tracing::`，`println!`，`dbg!` を探して確かめた
- [ ] 新しい通信・保存先・外から読むファイルがあれば SECURITY-MODEL.md を更新した
