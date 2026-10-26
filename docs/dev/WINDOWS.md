# Windows 版の作り

構成の判断は ADR [0003](adr/0003-windows-out-of-process-engine.md)(変換を別のプロセスで行う)と [0010](adr/0010-ipc-message-format.md)(メッセージの形式)．通信の安全は [SECURITY-MODEL.md](SECURITY-MODEL.md) の「Windows のプロセス間通信」．

## プロセスと置き場所

| プロセス | 置き場所 | 言語 | 役割 |
|---|---|---|---|
| `s90_tsf.dll` | `apps/windows/crates/tsf` | Rust | TSF のテキストサービス．キーをエンジンに送り，返った操作で入力欄を更新する．32 ビットと 64 ビットの 2 つを入れる |
| `s90-engine-host.exe` | `core/Sources/s90-engine-host` | Swift | core の `InputSession` を動かす．ログオンのたびに 1 つ動く(`HKLM\...\Run`) |
| `s90-candidate-ui.exe` | `apps/windows/crates/candidate-ui` | Rust | 候補の一覧・分岐図・案内・モードの札・手書きの窓を Direct2D で描く．エンジンが立ち上げる |
| `s90-settings.exe` | `apps/windows/crates/settings` | Rust | 設定の画面．設定の読み書きはエンジンに頼む |

```
アプリのプロセス              s90-engine-host                 s90-candidate-ui
┌──────────────┐  key など   ┌────────────────────┐  UiCommand  ┌──────────────┐
│ s90_tsf.dll  │────────────→│ EngineService      │────────────→│ 候補ウィンドウ │
│              │←────────────│  └ InputSession    │             └──────────────┘
└──────────────┘  edit       │ FileSettingsStore  │←──── s90-settings.exe(readSettings・writeSettings)
                             └────────────────────┘
```

- 判断はすべて core にある．DLL はキーを `KeyInput` に置き換え，返った `EditOperation`(確定・組み立て中の文字・モード)を入力欄に反映するだけ
- `ClientAction` をどのプロセスが受け持つかは `S90IPC` の `RoutedActions` が決める
- `OnTestKeyDown` はエンジンに問い合わせない．応答に入っている `SessionState`(組み立て中か，モード，今の状態で受け取るキー)の写しで答える
- 打鍵が止まったときの表示の切り替えと打ち間違いの見直しは，エンジンが待つ時間を返し，DLL がタイマーで `wake` を送る
- 設定のファイルは macOS と同じ形式．エンジンが 2 秒ごとに更新の時刻を見て，変わっていれば読み直す
- `.ui` のパイプはエンジンから候補ウィンドウへの一方向．エンジンは読みを待たない(同期の I/O のハンドルでは，読みを待っているあいだ同じハンドルへの書き込みも止まるため)

## 手書き入力

手書きの窓(R-14)は候補ウィンドウのプロセスが出す(`candidate-ui/src/handwriting`)．フォーカスを奪わない窓(`WS_EX_NOACTIVATE`)なので，書いたり候補を押したりしても入力先のアプリはフォーカスを持ったまま．

1. 手書き入力のキーで，エンジンが窓を開いたセッションを覚え，候補ウィンドウに `showHandwriting` を送る
2. 線を書き終えて少し待つと(`DefaultSettings.handwritingRecognitionDelay`)，Windows の手書き認識(`Windows.UI.Input.Inking`)で読み，候補を並べる．日本語の認識器が無ければ案内を出す
3. 候補を押すと，候補ウィンドウはエンジンのパイプにつないで `handwritingChosen` を送る．エンジンはこの要求を，実行ファイルが `s90-candidate-ui.exe` の接続からだけ受ける
4. DLL はエンジンから押し込まれる口を持たないので，窓を開いているあいだエンジンは短い間隔の `wakeAfterMilliseconds` を返し，DLL の `wake` で選んだ文字を `commit` にして返す．窓を閉じるか，入力先から外れたら(`deactivate`)取りに来るのをやめる

## Windows で使わないもの

`core/Package.swift` の trait `Zenzai` を `--disable-default-traits` で外してビルドする(llama.cpp のライブラリをまだ用意していないため)．Vision(手書き．Windows では候補ウィンドウが Windows の手書き認識を使う)・CryptoKit(同期の辞書の索引)・`os` の Logger は Apple の OS だけで作る．英単語の辞書は Windows のスペルチェッカーをつなぐまで空にしている．

## ビルドと確かめ

手元の Mac には Windows 向けの道具がないので，Windows でのビルドとテストは GitHub Actions の `windows` のワークフロー(`.github/workflows/windows.yml`)で行う．PR を出す前のブランチでも `gh workflow run windows.yml --ref <ブランチ>` で動かせる．

| ジョブ | 内容 |
|---|---|
| `rust` | `apps/windows` の `cargo fmt --check`・`clippy`・`test`．DLL の公開する関数が 4 つだけかを `tools/windows/check_exports.ps1` で確かめる |
| `swift` | core と `s90-engine-host` を Windows でビルドし，core のテスト(名前付きパイプの往復を含む)を動かす |
| `package` | release でビルドし，`tools/windows/stage.ps1` で集めて WiX で `s90-tokyo-ime.msi` を作る |

Swift は swift.org の Windows 版(6.3.3)を `compnerd/gha-setup-swift` で，Rust は `apps/windows/rust-toolchain.toml` の版を，WiX は `dotnet tool` の 6.0.2 を使う．

Windows の機械で試すときは，`package` のジョブが作る MSI を入れる(`docs/user/how-to/install-windows.md`)．DLL だけを入れ替えるときは，管理者のコマンドプロンプトで `regsvr32 /u` で外してから置き換え，`regsvr32` で登録し直す．TSF の DLL はアプリに読み込まれたままになるので，置き換えたあとはアプリを開き直す．

## 決まっていないこと・まだ無いもの

- 配布物の署名(Authenticode)
- 候補ウィンドウをマウスで選ぶこと
- 再変換(選んだ文字を読みに戻す)
