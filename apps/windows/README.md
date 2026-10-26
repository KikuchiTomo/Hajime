# apps/windows

Windows の TSF テキストサービス(Rust の DLL)・候補ウィンドウ・インストーラーを置く Cargo のワークスペース．
変換は `core/` の `s90-engine-host` が別のプロセスで行う(ADR 0003)．crate の分け方は `.claude/skills/s90-windows/SKILL.md`．

| crate | 中身 |
|---|---|
| `crates/ipc` | エンジンとのメッセージ(`protocol/schema.json` から生成)と，その区切り方 |

## 確かめる

Rust のバージョンは `rust-toolchain.toml` で固定している．

```sh
cd apps/windows
cargo fmt --check
cargo clippy --all-targets --locked -- -D warnings
cargo test --locked
```

`crates/ipc` は OS に依存しないので macOS でもテストできる．
