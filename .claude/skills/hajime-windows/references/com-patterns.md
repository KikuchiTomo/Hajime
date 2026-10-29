# COM の実装の形

## panic を受け止める

```rust
// crates/tsf/src/com/guard.rs
use std::panic::{catch_unwind, AssertUnwindSafe};
use windows::core::{Error, Result};
use windows::Win32::Foundation::E_FAIL;

/// COM のメソッドの本体を包む．Rust の panic が入力先のアプリに伝わると，
/// アプリごと落ちるため，ここで受け止めて E_FAIL を返す．
pub fn guard<T>(body: impl FnOnce() -> Result<T>) -> Result<T> {
    match catch_unwind(AssertUnwindSafe(body)) {
        Ok(result) => result,
        Err(_) => {
            tracing::error!("panic を COM の境界で受け止めました");
            Err(Error::from(E_FAIL))
        }
    }
}
```

`Cargo.toml` の `[profile.release]` で `panic = "unwind"` を保つ(`abort` にすると受け止められない)．

## キーの処理

```rust
impl ITfKeyEventSink_Impl for KeyEventSink_Impl {
    fn OnTestKeyDown(&self, _ctx: Option<&ITfContext>, wparam: WPARAM, lparam: LPARAM) -> Result<BOOL> {
        guard(|| {
            // エンジンに問い合わせず，DLL の中の写しの状態だけで決める
            let key = KeyEvent::from_win32(wparam, lparam);
            Ok(self.state.borrow().would_consume(&key).into())
        })
    }
}
```

## 名前付きパイプ

```rust
// crates/ipc/src/ffi/pipe_security.rs
// 本人の SID だけに読み書きを許すセキュリティ記述子を作る．
// SDDL の例: "D:P(A;;GA;;;<ユーザーの SID>)"
```

接続は `CreateFileW` に `SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION` を付け，サーバーがクライアントになりすまさないようにする．
