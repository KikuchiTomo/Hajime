# apps/windows

Windows の TSF テキストサービス(Rust の DLL)・候補ウィンドウ・インストーラーを置く Cargo のワークスペース．
変換は `core/` の `s90-engine-host` が別のプロセスで行う(ADR 0003)．crate の分け方は `.claude/skills/s90-windows/SKILL.md`．

| crate | 中身 |
|---|---|
| `crates/ipc` | エンジンとのメッセージ(`protocol/schema.json` から生成)，その区切り方，名前付きパイプの接続 |
| `crates/tsf` | TSF のテキストサービスの DLL(`s90_tsf.dll`)．キーをエンジンに送り，返った操作を入力欄に反映する |

## 確かめる

Rust のバージョンは `rust-toolchain.toml` で固定している．

```sh
cd apps/windows
cargo fmt --check
cargo clippy --all-targets --locked -- -D warnings
cargo test --locked
```

`crates/ipc` と，`crates/tsf` のキーの置き換え(`key`)・受け取るキーの判断(`filter`)・下線の区間(`plan`)は OS に依存しないので，macOS でもテストできる．
COM の部分(`crates/tsf/src/com`)は Windows でだけビルドする．GitHub Actions の `windows` のワークフローが，DLL の公開する関数が `DllGetClassObject`・`DllCanUnloadNow`・`DllRegisterServer`・`DllUnregisterServer` だけであることも確かめる．
