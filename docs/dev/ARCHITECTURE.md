# アーキテクチャ

s90.tokyo IME は，azooKey のかな漢字変換エンジン(AzooKeyKanaKanjiConverter)を使った日本語入力システムです．
入力の状態の扱い・候補の作り方・補正の判定はすべて OS に依存しない Swift のパッケージ(`core/`)に置き，
macOS と Windows のアプリは，OS のキー入力を受け取って結果を画面に出すだけの薄い層にします．

決めた理由は `docs/dev/adr/` にあります．この文書には今の形だけを書きます．

## 全体の構成

```
            macOS                                      Windows
┌────────────────────────────┐        ┌──────────────────────────────────────────┐
│ apps/macos                 │        │ apps/windows                             │
│  InputMethodKit のアダプタ │        │  TSF テキストサービス(Rust の DLL)       │
│  候補ウィンドウ(AppKit)    │        │   各アプリのプロセスに読み込まれる       │
│  設定アプリ(SwiftUI)       │        │        │ 名前付きパイプ(protocol/)       │
│        │ 関数呼び出し      │        │        ▼                                 │
│        ▼                   │        │  s90-engine-host(Swift，1 ユーザー 1 つ) │
│  core(S90Core)             │        │   core(S90Core)                          │
└────────────────────────────┘        │  候補ウィンドウ(Rust，別プロセス)       │
                                      └──────────────────────────────────────────┘
```

macOS では入力メソッドが独立したプロセスとして動くので，core をそのままリンクします．
Windows の TSF の DLL は入力先のすべてのアプリのプロセスに読み込まれます．辞書とモデルをアプリごとに読み込むわけにはいかないため，変換はユーザーごとに 1 つ立ち上げるエンジンのプロセスで行います(ADR 0003)．

## core の層

```
core/Sources/
├── S90Domain/        何にも依存しない．型と純粋なロジック
├── S90Application/   ユースケースとポート(protocol)．S90Domain だけに依存
├── S90Engine/        変換のポートの実装．AzooKeyKanaKanjiConverter のアダプタ
├── S90Persistence/   設定・ユーザー辞書・学習データの保存のポートの実装
├── S90IPC/           Windows のエンジンとの通信．メッセージ型(protocol/ から生成)，要求をセッションに渡す EngineService，名前付きパイプ
├── s90-engine-host/  Windows 用のエンジンのプロセス(composition root のひとつ)
└── s90-playground/   入れずにターミナルで変換を試す道具(make try．composition root のひとつ)
```

依存の向きは外側から内側だけです．

```
apps/macos ─────────┐
s90-engine-host ────┼─→ S90Application ─→ S90Domain
S90Engine ──────────┤
S90Persistence ─────┘
```

- **S90Domain**: 値と規則だけを置く．OS の API も変換エンジンも知らない
  - 入力: 抽象化したキー(`KeyEvent`)，入力モードとアプリのプロファイル(`InputMode`，`AppProfile`)，候補(`Candidate`)，ライブ変換の見せ方(`LiveConversionRule`)，ターミナルの行の状態(`CommandLineState`)，使い方の回数(`UsageCounts`)
  - 読み: ローマ字とかなの組み立て(`Composition`，`RomajiTable`，`KanaLayout`)
  - 分岐図: 文節と枝(`SegmentLattice`)
  - 補正: 英単語(`TypoCorrectionRule`)と日本語の打ち間違い(`ReadingCorrectionRule`)の判定，英字で打った語を英語にするか日本語にするか(`WordLanguageJudge`)
  - 記号と日付: `SymbolDictionary`，`SymbolSequence`，`DateExpressions`
  - 中身の確かめ: SHA-256(`SHA256Digest`．CryptoKit の無い Windows で，Zenzai のモデルや取り込んだ辞書の索引を確かめる)
  - 設定: `Settings` と既定値・上限(`DefaultSettings`)，記号の表(`SymbolTable`)，字種(`ScriptVariant`)，キー設定の表(`Keymap`・`KeymapCommand`・`KeymapPreset`．ADR 0009)
- **S90Application**: `InputSession`(キーを受けて状態を進め，画面への指示 `ClientAction` の列を返す)と，その部品．エンジンにない候補を足す `SupplementedConverter`．外部とは `Ports/` の protocol 越しにだけ話す
  - 部品: 英単語の補正(`EnglishWordCorrector`)，語の英語・日本語の見分け(`WordLanguageClassifier`．設定の画面で試す `WordLanguagePreview`)，「nn」の読み(`NasalReadingResolver`)，分岐図(`LatticeBuilder`，`PanelBuilder`)，ターミナルの行(`TerminalLine`)
  - 入力方式: ローマ字入力は `InputSession` の共通の処理が受け持つ．ほかの方式は `InputStyleHandling` を実装して足す(`EnglishInput` が英字入力と英字入力(自動)，`KanaInput`)
  - ポート: `KanaKanjiConverting`，`EnglishLexicon`，`SettingsReading`・`SettingsStoring`・`SettingsObserving`，`CalendarReading`，`UsageRecording`・`UsageReading`
- **S90Engine**: `AzooKeyConverterEngine` と `AzooKeyConverterSession` が `KanaKanjiConverting` を実装する．Zenzai のモデルの確認(`ZenzaiModel`)もここ．azooKey の型はこのモジュールの外に出さない
- **S90Persistence**: ファイルと OS から読む値の実装(`FileSettingsStore`，`FileUsageStore`，`UserDictionaryFile`，`SystemCalendar`，郵便番号の表 `PostalCodeFile`，Vision で手書きを読む `VisionHandwritingRecognizer`，取り込んだ辞書の索引を同期のフォルダと運ぶ `DictionaryFileSync`)．OS の機能は Foundation のほかに CoreGraphics・Vision・CryptoKit だけを使う．本人だけが読み書きできるファイルの読み書きは `ProtectedFile` にまとめる．保存先とファイルの権限は `docs/dev/SECURITY-MODEL.md` に従う

## キー入力から画面までの流れ

```
OS のキーイベント
  → (アダプタ) KeyEvent に変換        apps/macos: NSEvent，apps/windows: WPARAM/LPARAM
  → InputSession.handle(KeyEvent, context)   context = 今のアプリのプロファイル・入力欄の種類
  → [ClientAction]                    例: setMarkedText，commit，showCandidates，showModeIndicator
  → (アダプタ) OS の API で反映         apps/macos: IMKTextInput，apps/windows: ITfComposition
```

`InputSession` は同期的に結果を返します．Zenzai を使っても 1 キーあたり p95 で 40ms ほどで終わるので，変換もこの中で行っています(R-01 の計測)．打鍵が止まったときの表示の切り替え(`settle`)だけは，アダプタのタイマーから呼びます．

分岐図(ADR 0007)の文節と枝は `LatticeBuilder` が作り，候補ウィンドウに出す内容は `PanelBuilder` が組み立てます．`InputSession` はキーと状態の移り変わりだけを受け持ちます．キーの意味はキー設定の表(`Keymap`)で引き，今の状態(入力文字なし・入力中・変換中・英数)で効くコマンドを行います．

アダプタは `ClientAction` を OS の操作に置き換えるだけで，判断をしません．macOS と Windows で動きが食い違うのを防ぐためです．

## Windows のプロセス

| プロセス | 言語 | 役割 |
|---|---|---|
| TSF の DLL(`apps/windows/crates/tsf`) | Rust | キーを受け取り，エンジンに送り，結果を入力欄に反映する．入力先のアプリの中で動くので，重い処理と大きな依存を持たない |
| `s90-engine-host` | Swift | core を動かす．ユーザーのログオン中に 1 つだけ動く |
| 候補ウィンドウ(`apps/windows/crates/candidate-ui`) | Rust | 候補とモード表示を描く．入力先のアプリの権限や UI スレッドに影響されないよう別のプロセスにする |

通信の形式は `protocol/` に定義し，Swift と Rust の両方のコードをそこから生成します．手で二重に書かないためです(ADR 0010)．
Windows でも trait `Zenzai` を入れてビルドします(llama.cpp の取り方は `docs/dev/WINDOWS.md`)．手書きの認識(Vision)も Apple の OS でだけ作ります．同期のフォルダの辞書の索引の SHA-256 は，Apple の OS では CryptoKit で，Windows では `SHA256Digest` で求めます．

DLL はキーを送って入力欄への操作(確定・組み立て中の文字・モード)を受け取るだけで，候補・分岐図・案内はエンジンが候補ウィンドウに直接送ります．`ClientAction` をどのプロセスが受け持つかは `S90IPC` の `RoutedActions` が決めます．

## 設定とデザインの値

- 色・寸法・動きの長さ: `design/tokens/` が唯一の置き場所．Swift・Rust・CSS(ドキュメントサイト)向けのコードは `tools/tokens` が生成する
- 既定の設定値: `core/Sources/S90Domain/Settings/DefaultSettings.swift` に集める．アプリごとの既定プロファイルも同じ場所に置く
- 文言: macOS は今は `apps/macos/S90IME/UI/UIStrings.swift` に集める(多言語にするときに `Localizable.xcstrings` に移す)．Windows は `apps/windows/resources/strings/<言語>.toml`

## ディレクトリ

```
core/            S90Core(Swift Package)．macOS・Windows・Linux でビルドとテストができる
apps/macos/      入力メソッド・候補ウィンドウ・設定アプリ(XcodeGen の project.yml から Xcode プロジェクトを作る)
apps/windows/    Cargo のワークスペース(TSF・候補ウィンドウ・インストーラー)
protocol/        Windows のエンジンとの通信の定義
design/          デザイントークン・テーマ・モックアップ
docs/            ドキュメント(`docs/README.md` が地図)
tools/           生成と検査のスクリプト
.claude/skills/  このリポジトリで Claude Code が従うスキル
```

azooKey の各リポジトリの fork は，このリポジトリには入れず，作業用に `../upstream/` へ clone します(`docs/dev/UPSTREAM.md`)．
