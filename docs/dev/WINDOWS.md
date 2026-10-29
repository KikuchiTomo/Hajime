# Windows 版の作り

構成の判断は ADR [0003](adr/0003-windows-out-of-process-engine.md)(変換を別のプロセスで行う)と [0010](adr/0010-ipc-message-format.md)(メッセージの形式)．通信の安全は [SECURITY-MODEL.md](SECURITY-MODEL.md) の「Windows のプロセス間通信」．

## プロセスと置き場所

| プロセス | 置き場所 | 言語 | 役割 |
|---|---|---|---|
| `hajime_tsf.dll` | `apps/windows/crates/tsf` | Rust | TSF のテキストサービス．キーをエンジンに送り，返った操作で入力欄を更新する．32 ビットと 64 ビットの 2 つを入れる |
| `hajime-engine-host.exe` | `core/Sources/hajime-engine-host` | Swift | core の `InputSession` を動かす．ログオンのたびに 1 つ動く(`HKLM\...\Run`) |
| `hajime-candidate-ui.exe` | `apps/windows/crates/candidate-ui` | Rust | 候補の一覧・分岐図・案内・モードの札・手書きの窓を Direct2D で描く．エンジンが立ち上げる |
| `hajime-settings.exe` | `apps/windows/crates/settings` | Rust | 設定の画面．設定の読み書きはエンジンに頼む |

```
アプリのプロセス              hajime-engine-host                 hajime-candidate-ui
┌──────────────┐  key など   ┌────────────────────┐  UiCommand  ┌──────────────┐
│ hajime_tsf.dll  │────────────→│ EngineService      │────────────→│ 候補ウィンドウ │
│              │←────────────│  └ InputSession    │             └──────────────┘
└──────────────┘  edit       │ FileSettingsStore  │←──── hajime-settings.exe(readSettings・writeSettings)
                             └────────────────────┘
```

- 判断はすべて core にある．DLL はキーを `KeyInput` に置き換え，返った `EditOperation`(確定・組み立て中の文字・モード)を入力欄に反映するだけ
- `ClientAction` をどのプロセスが受け持つかは `HajimeIPC` の `RoutedActions` が決める
- `OnTestKeyDown` はエンジンに問い合わせない．応答に入っている `SessionState`(組み立て中か，モード，今の状態で受け取るキー)の写しで答える
- 打鍵が止まったときの表示の切り替えと打ち間違いの見直しは，エンジンが待つ時間を返し，DLL がタイマーで `wake` を送る
- DLL はキーの返事を `keyResponseMilliseconds`(50ms)まで待ち，間に合わなければタイマーで後から反映する．変換のキー(Space・変換)だけは `conversionResponseMilliseconds`(250ms)まで待つ．Zenzai で文全体を変換し直すので CPU では 100ms ほどかかり，後から反映すると変換が出るまでに間が空くため
- DLL のタイマーは，入力先のアプリのスレッドごとに作るメッセージ専用の窓に付ける(`crates/tsf/src/com/timer.rs`)．窓の無いタイマー(`SetTimer(None, …)`)の知らせは宛先の窓が無く，アプリのメッセージの処理によっては配られないため．配られないと，Space の変換の遅れた返事・打鍵が止まったときの変換・打ち間違いの見直しが画面に出ない(0.1.4 で起きた)
- タスクバーの入力モードの表示は，言語バーの項目(`GUID_LBI_INPUTMODE`．`crates/tsf/src/com/langbar.rs`)で出す．右クリックのメニューの項目は macOS の入力メニューと同じ(`crates/tsf/src/menu.rs`)で，選んだ操作は `menu` の要求でエンジンに頼む
- 設定の「キー配列」(ABC・US・Dvorak・Colemak)は，DLL がキーの位置(スキャンコード)から文字を引く表(`crates/tsf/src/layout.rs`)で打つ．Windows で配列を読み込むと利用者の配列の一覧が変わるため，OS の配列は切り替えない．ローマ字入力と英字入力のときだけ使い，Ctrl・Alt を押したショートカットは OS の配列のまま
- 打ち間違いの訂正は Zenzai で 1 文に 1 秒ほどかかるので，エンジンが裏で求める(`ZenzaiTypoService`)．求めているあいだは短い間隔(`EngineService.correctionPollMilliseconds`)の `wake` を頼み，求め終わったあとの `wake` で見直しの結果を返す．Space では訂正を待たずにすぐ変換を出し(`.awaitCorrections`)，訂正が届いたあとの `wake` で，そのあいだにキーを押していなければ直した変換に入れ替える(`InputSession.applyLateCorrections`．求めるのは `DefaultSettings.lateCorrectionTimeout` まで)．間に合わなかった `wake` の応答も，キーの応答と同じくあとで反映する
- 設定のファイルは macOS と同じ形式．エンジンが 2 秒ごとに更新の時刻を見て，変わっていれば読み直す
- 設定の同期(R-15)はエンジンが動かす．選んだフォルダはパスで覚え(`PathSyncCoordinator`)，macOS と同じ時機(起動時・設定を変えて少し待ったとき・一定の間隔)で同期する．同期の手順は macOS と共有する(`FolderSyncRunner`)
- 辞書の取り込み・設定のバックアップ・除外設定の CSV・決まりの一覧の読み書きは，設定の画面がパスを渡してエンジンに頼む(`SettingsFiles`)．時間がかかるので，エンジンは名前付きパイプの接続のスレッドで終わるまで待って答え，そのあいだもほかの接続(入力)には答える(`EngineService.reply`)
- 設定の画面(`crates/settings`)は設定のファイルを直接読まず，項目の名前と JSON の値でエンジンに読み書きを頼む(`readSettingsFields`・`writeSettingsFields`)．値の確かめ(範囲・一覧の形・上限)はエンジンが設定のファイルを読むときと同じに行い，画面は書いたあとに返った値を出す．項目の名前と値の範囲・上限は `protocol/settings-catalog.json`(core の `DefaultSettings` から作る写し．`make settings-catalog` で作り直し，古ければ core のテストが落ちる)から読み，既定値はエンジンに頼んで読む
- 設定の画面のページと項目の並びは macOS の `SettingsView` と同じ(`crates/settings/src/pages.rs`)．文言は `UIStrings` と同じものを `strings.rs` に置き，Windows で言い方が違うものだけを変える
- 設定の画面は 1 枚の窓に Direct2D で描く(ADR [0013](adr/0013-windows-settings-direct2d.md))．部品は子の窓にせず状態として持ち(`app/page.rs`)，文字を打つ欄だけ枠の無い EDIT を使い回す．窓を先に出し，エンジンへの接続と設定の読み込みは別のスレッドで行う．つながらなければ同じフォルダのエンジンを起動し(`app/mod.rs`)，間隔をおいてつなぎ直す
- 候補ウィンドウは同じセッションで 1 つだけ動かす(名前付きのミューテックス)．エンジンは新しくつないできた候補ウィンドウに切り替えて前の接続を閉じるので，2 つ動くと互いの接続を閉じ合い，出している候補が消える
- `.ui` のパイプはエンジンから候補ウィンドウへの一方向．エンジンは読みを待たない(同期の I/O のハンドルでは，読みを待っているあいだ同じハンドルへの書き込みも止まるため)

## 手書き入力

手書きの窓(R-14)は候補ウィンドウのプロセスが出す(`candidate-ui/src/handwriting`)．フォーカスを奪わない窓(`WS_EX_NOACTIVATE`)なので，書いたり候補を押したりしても入力先のアプリはフォーカスを持ったまま．

1. 手書き入力のキーで，エンジンが窓を開いたセッションを覚え，候補ウィンドウに `showHandwriting` を送る
2. 線を書き終えて少し待つと(`DefaultSettings.handwritingRecognitionDelay`)，Windows の手書き認識(`Windows.UI.Input.Inking`)で読み，候補を並べる．日本語の認識器が無ければ案内を出す
3. 候補を押すと，候補ウィンドウはエンジンのパイプにつないで `handwritingChosen` を送る．エンジンはこの要求を，実行ファイルが `hajime-candidate-ui.exe` の接続からだけ受ける
4. DLL はエンジンから押し込まれる口を持たないので，窓を開いているあいだエンジンは短い間隔の `wakeAfterMilliseconds` を返し，DLL の `wake` で選んだ文字を `commit` にして返す．窓を閉じるか，入力先から外れたら(`deactivate`)取りに来るのをやめる

## Windows で使わないもの

Vision(手書き．Windows では候補ウィンドウが Windows の手書き認識を使う)と `os` の Logger は Apple の OS だけで作る．同期の辞書の索引の SHA-256 は CryptoKit の代わりに `SHA256Digest` で求める．英単語の辞書は Windows のスペルチェッカー(ISpellChecker)を使う(`WindowsSpellCheckerLexicon`．C の口 `CWindowsSpellCheck` を通す)．英語のスペルチェッカーが入っていなければ，英単語の綴りの補正だけが効かなくなる．

## Zenzai

Windows でも trait `Zenzai` を入れてビルドする．llama.cpp は上流の azooKey-Windows と同じ b4846 の Windows 向けのビルド(AVX 版)を `tools/windows/fetch_llama.ps1` で取り，SHA-256 を確かめてから使う．展開した場所は，`swift build -Xswiftc -L<場所>` でリンクの探す場所(`llama.lib`)に，`PATH` で実行時の探す場所(`llama.dll`・`ggml*.dll`)に足す．`LIB` を書き換えると clang が MSVC のライブラリを自分で探さなくなるので使わない．

モデルは `tools/windows/fetch_zenzai.ps1` で取り(取得元とハッシュは `tools/models/fetch_zenzai.sh` と同じ)，インストール先の `Zenzai\` に置く．エンジンは起動のたびに大きさと SHA-256(`SHA256Digest`)を確かめ，合わなければ Zenzai なしで動く．

## ビルドと確かめ

手元の Mac でも，rustup で `x86_64-pc-windows-msvc` の target を足せば `cargo clippy --target x86_64-pc-windows-msvc` でコンパイルまでは確かめられる(リンクはできない)．Windows でのビルドとテストは GitHub Actions の `CI Windows` のワークフロー(`.github/workflows/ci-windows.yml`)で，インストーラーは `Package Windows`(`.github/workflows/package-windows.yml`)で作る．PR を出す前のブランチでも `gh workflow run ci-windows.yml --ref <ブランチ>` で動かせる．

| ジョブ | 内容 |
|---|---|
| `rust-windows`(ci-windows) | `apps/windows` の `cargo fmt --check`・`clippy`・`test`．候補ウィンドウの見本を PNG に書き出して成果物 `candidate-ui-snapshots` にする．DLL の公開する関数が 4 つだけかを `tools/windows/check_exports.ps1` で確かめる |
| `core-windows`(ci-windows) | core と `hajime-engine-host` を Zenzai 入りで Windows でビルドし，core のテスト(名前付きパイプの往復を含む)を動かす |
| `package-windows`(package-windows) | release でビルドし，`tools/windows/stage.ps1` で llama.cpp の DLL と Zenzai のモデルと一緒に集めて，WiX で `Hajime-<バージョン>.msi` を作る |

Windows 向けの Rust のコードは，Mac でも型の検査まではできる．rustup で `x86_64-pc-windows-msvc` の標準ライブラリを入れ，`apps/windows` で `cargo clippy --target x86_64-pc-windows-msvc -p candidate-ui --all-targets` を動かす(リンクはしない)．

Swift は swift.org の Windows 版(6.3.3)を `compnerd/gha-setup-swift` で，Rust は `apps/windows/rust-toolchain.toml` の版を，WiX は `dotnet tool` の 6.0.2 を使う．

Windows の機械で試すときは，`package-windows` のジョブが作る MSI を入れる(`docs/user/how-to/install-windows.md`)．DLL だけを入れ替えるときは，管理者のコマンドプロンプトで `regsvr32 /u` で外してから置き換え，`regsvr32` で登録し直す．TSF の DLL はアプリに読み込まれたままになるので，置き換えたあとはアプリを開き直す．

## 候補ウィンドウの描き方

配置と色は `candidate-ui` の `scene`(OS に依らない)が macOS の `CandidateView`・`BranchView` と同じ決め方で決め，`app::render` が Direct2D でなぞる．テーマの色と書体は `theme::ResolvedTheme` が設定(カスタムテーマを含む)と OS の外観から決める．

- 窓は DWM に合成を任せ(`DwmExtendFrameIntoClientArea`)，描かなかったところを透けさせる．角丸の形と影は中身の側が描く
- glass は，Windows 11 で DWM の背景(`DWMSBT_TRANSIENTWINDOW`)を使えるときだけ地をすりガラスにする．このときは角の丸み・縁・影も OS が描く．使えないとき(Windows 10・ハイコントラスト)は `glass.light`・`glass.dark` の色で地を塗る
- 選択の色は Windows のアクセントカラー(`AccentPalette`)．ライト・ダークは `AppsUseLightTheme`，「コントラストを上げる」はハイコントラスト，動きを止めるのは「アニメーション効果」がオフのとき
- ナレーターが動いているときは，選んでいる候補(文字種)・注目している文節・案内を UI オートメーションの知らせ(`UiaRaiseNotificationEvent`)で読み上げてもらう．同じ文は続けて読ませない
- 見本の画像は，デバッグビルドの `hajime-candidate-ui.exe --render-snapshots <ディレクトリ>` で macOS と同じ名前(`list-glass-light.png` など)で書き出す

## 設定の画面の速さ

`hajime-settings.exe --measure <ファイル>` で測る(窓はふつうに出し，測り終えたら閉じる)．2026-10-27 に手元の PC(DPI 100%)で測った値:

| 項目 | 値 |
|---|---|
| 起動から窓を描き終えるまで | 約 20ms |
| 起動から設定を読み終えるまで(エンジンへの接続を含む) | 約 250ms |
| ページを開く(部品を作り，エンジンから読み，値を映して置く) | 平均 8ms．利用表記のページは長文を組むので初回だけ約 30ms |
| ページを初めて描く(Direct2D に描かせるまでの CPU の時間) | 平均 1ms |
| ページを 2 回目から描く | 平均 0.4ms |
| 送るときの 1 フレーム | 描く時間 0.8ms．間隔は画面の合成に揃う |

## 初期設定ウィザードとインストール後の再起動

ADR [0015](adr/0015-windows-setup-wizard.md)．macOS 版はまだ無いので，Windows 版もリリースしない．

- **再起動**: インストーラーは入れ終えたら(上書きでも)`ScheduleReboot` で再起動を求める．確認は Windows Installer の標準のもので，自前の画面は作らない．文字入力のサービスの DLL は，起動しているアプリには読み込まれないため
- **起動**: HKLM の `Run` に `hajime-settings.exe --setup-if-needed` を入れる．ログオンのたびに起動し，済んでいれば(HKCU `Software\haji.men\IME` の `SetupCompleted` が 1)窓を出さずにすぐ終わる．済んだことはエンジンの設定のファイルには書かない(利用者ごと・PC ごとの記録で，同期しない)
- **開き直す**: 設定の画面の「情報」の「初期設定をやり直す」で，同じ実行ファイルを `--setup` で起動する．ウィザードの窓がもうあれば開かない
- **作り**: `crates/settings` の `wizard.rs`(ページと選ぶ値．OS に依らない)，`demo.rs`(実演の台本)，`app/wizard.rs`(窓)．値はページを離れるときにエンジンに書く(`SettingsModel::set_all`)．「あとで」・窓を閉じたときは済んだことにしない(次のログオンでまた出す)．「完了」「設定を開く」で済んだことにする
- **見本の撮影**: `hajime-settings.exe --setup --offline --theme dark --step window` のように開く．`--offline` はエンジンにつながず見本の値で開き，値も済んだことも書かない．`--step` はページの名前(`welcome`・`switch`・`characters`・`liveconversion`・`window`・`focus`・`correction`・`features`・`appearance`・`done`)
- **CPU**: 止まっているコマのあいだは時計で次のコマを待つ．手元の PC で，最後のページ(動かない)は 10 秒で CPU 0ms，候補の窓の実演を繰り返すページは 10 秒で約 140ms だった

## 決まっていないこと・まだ無いもの

- 配布物の署名(Authenticode)
