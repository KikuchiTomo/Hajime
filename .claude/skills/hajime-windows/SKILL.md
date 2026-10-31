---
name: hajime-windows
description: Hajime の Windows 版(apps/windows の Rust の Cargo ワークスペース．TSF テキストサービスの DLL，候補ウィンドウ，インストーラー，hajime-engine-host との名前付きパイプの通信)を書く・直す・レビューするときの決まり．COM，unsafe，panic の扱い，スレッド，TSF の composition，InputScope を含む．.rs ファイル，Cargo.toml，TSF，COM，Win32，名前付きパイプ，Windows のインストーラーに触れるときは必ず使う．Use whenever working on Windows, Rust, TSF or COM code in this repository.
---

# Windows 版の決まり

構成は `docs/dev/adr/0003-windows-out-of-process-engine.md`，通信の安全は `docs/dev/SECURITY-MODEL.md` を先に読む．判断は core(Swift)にあり，Windows 側はキーの受け渡しと `ClientAction` の反映だけを行う．

## crate の分け方

```
apps/windows/
├── Cargo.toml          ワークスペース．依存の版はここで揃える
├── crates/
│   ├── tsf/            TSF テキストサービスの DLL(cdylib)．入力先のアプリに読み込まれる
│   ├── ipc/            名前付きパイプの接続とメッセージ(protocol/ から生成した型)
│   ├── candidate-ui/   候補ウィンドウのプロセス(Direct2D と DirectWrite)
│   ├── tokens/         design/tokens から生成した色と寸法
│   └── launcher/       ログオン時に engine-host と candidate-ui を立ち上げる
└── installer/          WiX の定義
```

`tsf` は `ipc` と `tokens` 以外に依存しない．入力先のアプリに読み込まれるコードを小さく保つため．

## TSF の DLL

- 公開する COM のオブジェクトは `ITfTextInputProcessorEx`，`ITfKeyEventSink`，`ITfThreadMgrEventSink`，`ITfCompositionSink`，`ITfDisplayAttributeProvider`
- メソッドの実装はすべて `com::guard(|| { ... })` で包み，panic を `E_FAIL` にする(`references/com-patterns.md`)
- `OnTestKeyDown` は IME が処理するかどうかだけを素早く返す．ここでエンジンと通信しない．判断に要る状態(変換中か，入力方式)は DLL の中に写しを持つ
- エンジンとの通信には時間の上限(既定 50ms)を設け，超えたら読みのまま返して後から結果を反映する
- InputScope がパスワードのときは composition を始めない
- 書き込みは `ITfEditSession` の中だけ．`RequestEditSession` は `TF_ES_READWRITE | TF_ES_ASYNCDONTCARE`

## unsafe

- `unsafe` は `com` と `ffi` のモジュールの中だけに書く．それ以外のモジュールの先頭には `#![forbid(unsafe_code)]` を置く
- ブロックごとに `// SAFETY:` で，守られている不変条件を書く
- 生のポインタを構造体のフィールドに持たない．windows クレートの COM の型(`ITfContext` など)で持つ

## エラーと panic

- ライブラリの crate は `thiserror` でエラー型を作る．`anyhow` は `launcher` と開発用のツールだけ
- `unwrap` と `expect` は `#[cfg(test)]` の中だけ．Clippy の `unwrap_used` と `expect_used` を deny にする
- ログは `tracing`．入力の中身を持つ型の `Debug` は中身を伏せる

## 検査

- `cargo fmt --check`，`cargo clippy --all-targets -- -D warnings`，`cargo test --locked`
- `cargo deny check`(ライセンスと脆弱性)
- DLL の公開シンボルが `DllGetClassObject`，`DllCanUnloadNow`，`DllRegisterServer`，`DllUnregisterServer` だけであることを CI で確かめる

## azooKey-Windows を読むとき

`../upstream/azooKey-Windows/crates/client/` が TSF の実装．gRPC(tonic)を使っているが，このプロジェクトでは DLL を小さくするために `protocol/` の軽い形式にする．構成の参考にとどめ，コードを持ち込むときは `hajime-upstream-port` スキルに従う．
