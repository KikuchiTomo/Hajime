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
├── S90IPC/           Windows のエンジンとの通信のメッセージ型(protocol/ から生成)
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

- **S90Domain**: 入力の状態(`InputState`)，抽象化したキー(`KeyEvent`)，入力方式(`InputMethodKind`: ローマ字・かな・EN)，種類の変換(`ScriptVariant`: ひらがな・カタカナ・半角カタカナ・全角英数・半角英数)，¥ キーの割り当て(`YenKeyPolicy`)，アプリのプロファイル(`AppProfile`)，補正の判定規則．OS の API も変換エンジンも知らない
- **S90Application**: `InputSession`(キーを受けて状態を進め，画面への指示 `ClientAction` の列を返す)，`LiveConversionPolicy`，`TypoCorrectionService`，`ProfileResolver`．外部とは `Ports/` の protocol 越しにだけ話す
  - ポートの例: `KanaKanjiConverting`，`EnglishLexicon`，`SettingsStore`，`UserDictionaryStore`，`LearningStore`，`Clock`
- **S90Engine**: `AzooKeyConverterAdapter` が `KanaKanjiConverting` を実装する．azooKey の型はこのモジュールの外に出さない
- **S90Persistence**: ファイルに保存する実装．保存先とファイルの権限は `docs/dev/SECURITY-MODEL.md` に従う

## キー入力から画面までの流れ

```
OS のキーイベント
  → (アダプタ) KeyEvent に変換        apps/macos: NSEvent，apps/windows: WPARAM/LPARAM
  → InputSession.handle(KeyEvent, context)   context = 今のアプリのプロファイル・入力欄の種類
  → [ClientAction]                    例: setMarkedText，commit，showCandidates，showModeIndicator
  → (アダプタ) OS の API で反映         apps/macos: IMKTextInput，apps/windows: ITfComposition
```

`InputSession` は同期的に結果を返します．今の変換エンジン(Zenzai を使わない azooKey)は 1 キーあたり p95 で 30ms ほどで終わるので，変換もこの中で行っています(R-01 の計測)．Zenzai のような重い変換を入れるときは，読みだけを先に返して結果を後から送る形に変え，ADR を足します．

分岐図(ADR 0007)の文節と枝は `LatticeBuilder` が作り，候補ウィンドウに出す内容は `PanelBuilder` が組み立てます．`InputSession` はキーと状態の移り変わりだけを受け持ちます．

アダプタは `ClientAction` を OS の操作に置き換えるだけで，判断をしません．macOS と Windows で動きが食い違うのを防ぐためです．

## Windows のプロセス

| プロセス | 言語 | 役割 |
|---|---|---|
| TSF の DLL(`apps/windows/crates/tsf`) | Rust | キーを受け取り，エンジンに送り，結果を入力欄に反映する．入力先のアプリの中で動くので，重い処理と大きな依存を持たない |
| `s90-engine-host` | Swift | core を動かす．ユーザーのログオン中に 1 つだけ動く |
| 候補ウィンドウ(`apps/windows/crates/candidate-ui`) | Rust | 候補とモード表示を描く．入力先のアプリの権限や UI スレッドに影響されないよう別のプロセスにする |

通信の形式は `protocol/` に定義し，Swift と Rust の両方のコードをそこから生成します．手で二重に書かないためです．

## 設定とデザインの値

- 色・寸法・動きの長さ: `design/tokens/` が唯一の置き場所．Swift・Rust・CSS(ドキュメントサイト)向けのコードは `tools/tokens` が生成する
- 既定の設定値: `core/Sources/S90Domain/Settings/DefaultSettings.swift` に集める．アプリごとの既定プロファイルも同じ場所に置く
- 文言: macOS は `Localizable.xcstrings`，Windows は `apps/windows/resources/strings/<言語>.toml`．キーは両方で同じ名前にする

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
