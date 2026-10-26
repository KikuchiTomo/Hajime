# Windows 版の作り

構成の判断は ADR [0003](adr/0003-windows-out-of-process-engine.md)(変換を別のプロセスで行う)と [0010](adr/0010-ipc-message-format.md)(メッセージの形式)．通信の安全は [SECURITY-MODEL.md](SECURITY-MODEL.md) の「Windows のプロセス間通信」．

## プロセスと置き場所

| プロセス | 置き場所 | 言語 | 役割 |
|---|---|---|---|
| `s90_tsf.dll` | `apps/windows/crates/tsf` | Rust | TSF のテキストサービス．キーをエンジンに送り，返った操作で入力欄を更新する．32 ビットと 64 ビットの 2 つを入れる |
| `s90-engine-host.exe` | `core/Sources/s90-engine-host` | Swift | core の `InputSession` を動かす．ログオンのたびに 1 つ動く(`HKLM\...\Run`) |
| `s90-candidate-ui.exe` | `apps/windows/crates/candidate-ui` | Rust | 候補の一覧・分岐図・案内・モードの札を Direct2D で描く．エンジンが立ち上げる |
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
- タスクバーの入力モードの表示は，言語バーの項目(`GUID_LBI_INPUTMODE`．`crates/tsf/src/com/langbar.rs`)で出す．右クリックのメニューの項目は macOS の入力メニューと同じ(`crates/tsf/src/menu.rs`)で，選んだ操作は `menu` の要求でエンジンに頼む
- 設定の「キー配列」(ABC・US・Dvorak・Colemak)は，DLL がキーの位置(スキャンコード)から文字を引く表(`crates/tsf/src/layout.rs`)で打つ．Windows で配列を読み込むと利用者の配列の一覧が変わるため，OS の配列は切り替えない．ローマ字入力と英字入力のときだけ使い，Ctrl・Alt を押したショートカットは OS の配列のまま
- 打ち間違いの訂正は Zenzai で 1 文に 1 秒ほどかかるので，エンジンが裏で求める(`ZenzaiTypoService`)．求めているあいだは短い間隔(`EngineService.correctionPollMilliseconds`)の `wake` を頼み，求め終わったあとの `wake` で見直しや待たせていた変換(`.awaitCorrections`)の結果を返す．Space の変換を待たせるのは `DefaultSettings.correctionWaitBeforeConversion` まで．間に合わなかった `wake` の応答も，キーの応答と同じくあとで反映する
- 設定のファイルは macOS と同じ形式．エンジンが 2 秒ごとに更新の時刻を見て，変わっていれば読み直す
- 設定の同期(R-15)はエンジンが動かす．選んだフォルダはパスで覚え(`PathSyncCoordinator`)，macOS と同じ時機(起動時・設定を変えて少し待ったとき・一定の間隔)で同期する．同期の手順は macOS と共有する(`FolderSyncRunner`)
- 辞書の取り込み・設定のバックアップ・除外設定の CSV・決まりの一覧の読み書きは，設定の画面がパスを渡してエンジンに頼む(`SettingsFiles`)．時間がかかるので，エンジンは名前付きパイプの接続のスレッドで終わるまで待って答え，そのあいだもほかの接続(入力)には答える(`EngineService.reply`)

## Windows で使わないもの

Vision(手書き)と `os` の Logger は Apple の OS だけで作る．同期の辞書の索引の SHA-256 は CryptoKit の代わりに `SHA256Digest` で求める．英単語の辞書は Windows のスペルチェッカーをつなぐまで空にしている．

## Zenzai

Windows でも trait `Zenzai` を入れてビルドする．llama.cpp は上流の azooKey-Windows と同じ b4846 の Windows 向けのビルド(AVX 版)を `tools/windows/fetch_llama.ps1` で取り，SHA-256 を確かめてから使う．展開した場所は，`swift build -Xswiftc -L<場所>` でリンクの探す場所(`llama.lib`)に，`PATH` で実行時の探す場所(`llama.dll`・`ggml*.dll`)に足す．`LIB` を書き換えると clang が MSVC のライブラリを自分で探さなくなるので使わない．

モデルは `tools/windows/fetch_zenzai.ps1` で取り(取得元とハッシュは `tools/models/fetch_zenzai.sh` と同じ)，インストール先の `Zenzai\` に置く．エンジンは起動のたびに大きさと SHA-256(`SHA256Digest`)を確かめ，合わなければ Zenzai なしで動く．

## ビルドと確かめ

手元の Mac には Windows 向けの道具がないので，Windows でのビルドとテストは GitHub Actions の `windows` のワークフロー(`.github/workflows/windows.yml`)で行う．PR を出す前のブランチでも `gh workflow run windows.yml --ref <ブランチ>` で動かせる．

| ジョブ | 内容 |
|---|---|
| `rust` | `apps/windows` の `cargo fmt --check`・`clippy`・`test`．DLL の公開する関数が 4 つだけかを `tools/windows/check_exports.ps1` で確かめる |
| `swift` | core と `s90-engine-host` を Zenzai 入りで Windows でビルドし，core のテスト(名前付きパイプの往復を含む)を動かす |
| `package` | release でビルドし，`tools/windows/stage.ps1` で llama.cpp の DLL と Zenzai のモデルと一緒に集めて，WiX で `s90-tokyo-ime.msi` を作る |

Swift は swift.org の Windows 版(6.3.3)を `compnerd/gha-setup-swift` で，Rust は `apps/windows/rust-toolchain.toml` の版を，WiX は `dotnet tool` の 6.0.2 を使う．

Windows の機械で試すときは，`package` のジョブが作る MSI を入れる(`docs/user/how-to/install-windows.md`)．DLL だけを入れ替えるときは，管理者のコマンドプロンプトで `regsvr32 /u` で外してから置き換え，`regsvr32` で登録し直す．TSF の DLL はアプリに読み込まれたままになるので，置き換えたあとはアプリを開き直す．

## 決まっていないこと・まだ無いもの

- 配布物の署名(Authenticode)
- 候補ウィンドウをマウスで選ぶこと
- 再変換(選んだ文字を読みに戻す)
