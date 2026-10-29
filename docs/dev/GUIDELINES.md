# ガイドライン

設計の全体像は [ARCHITECTURE.md](ARCHITECTURE.md) にあります．ここには，ファイルの置き場所・名前・書き方の決まりを書きます．

## 開発環境

- ツールは mise で揃える(`mise.toml`)．入口は `make`
  - `make setup` / `make check` / `make test` / `make tokens`
- 依存を増やすときは，理由と代わりに検討したものを PR に書く．依存の監査は `docs/dev/SECURITY-MODEL.md` の「供給網」に従う
- Swift のパッケージは revision か exact で固定する．Rust は `Cargo.lock` をコミットし，CI は `--locked` で動かす

## 置き場所の決め方

新しいコードを書くときは，次の順に考えて置き場所を決める．

1. OS の API を呼ぶか．呼ぶなら `apps/<OS>/` のアダプタ．呼ばないなら `core/`
2. 外部(ファイル・変換エンジン・時刻・ネットワーク)に触れるか．触れるなら `HajimeApplication/Ports/` に protocol を足し，実装を `HajimeEngine` か `HajimePersistence` に置く
3. 状態を進める処理か．進めるなら `HajimeApplication` のユースケース．値の計算だけなら `HajimeDomain`

迷ったら内側(Domain 寄り)に置き，外部に触れる部分だけを外に出す．テストを書きやすいからです．

## 名前

- Swift
  - 型は PascalCase，関数・変数は camelCase．ファイル名は中心となる型の名前と同じにする
  - protocol は能力を表す名前にする(`KanaKanjiConverting`，`SettingsStoring`)．実装は技術名を前に付ける(`AzooKeyConverterAdapter`，`FileSettingsStore`)
  - テストは `<対象>Tests.swift`
- Rust
  - crate 名は kebab-case，モジュールは snake_case
  - `unsafe` を含むモジュールは `ffi` か `com` という名前の中に閉じ込める
- ID(プロファイル・テーマ・トークン)は kebab-case

## 書き方

- **値をコードに直接書かない**．色と寸法は `design/tokens/`，設定の既定値は `DefaultSettings.swift`，文言は各 OS の文言ファイル
  - コードに残す定数は，意味のある名前を付けて型の中か ファイルの先頭に置く
- 依存はコンストラクタ(イニシャライザ)で受け取る．具象を組み立てるのは composition root(`apps/macos/Hajime/CompositionRoot.swift` と `core/Sources/hajime-engine-host/main.swift`)だけ
- シングルトンとグローバルな可変状態を作らない．`static var` が要りそうになったら，所有者を決めて注入する
- 1 つの型に 1 つの理由でしか変更が入らないようにする．入力メソッドのコントローラに変換・候補の表示・設定の読み込みを同居させない(azooKey-Desktop の `azooKeyMacInputController` が 1000 行を超えたのを繰り返さない)
- 同じ判断を 2 か所に書かない．macOS と Windows の両方に同じ分岐が要るなら，それは `core/` の仕事
- `switch` は網羅させ，`default` で握りつぶさない．ケースが増えたときにコンパイラに知らせてもらうため
- エラーは型で返す(`throws` か `Result`)．`try!`，`fatalError`，Rust の `unwrap` は，テストと「起こったらプログラムの誤り」と言える箇所だけ．入力先のアプリを巻き込んで落とすわけにはいかない
- Swift は Swift 6 の言語モード(厳格な並行性チェック)で書く．UI に触る型は `@MainActor`
  - 例外は macOS のアプリのターゲット(`apps/macos`)だけ．InputMethodKit に並行性の注釈が無く，Swift 6 では入力コントローラを書けないため，Swift 5 の言語モードにしている．判断はすべて core に置くので，検査の甘い範囲はアダプタに限られる
- コメントは日本語で「なぜそうするか」を書く．何をしているかはコードで読めるようにする

## テスト

- `HajimeDomain` と `HajimeApplication` に処理を足したら，テストも足す．ポートはテスト用の実装(`Fake<名前>`)を `core/Tests/Support/` に置いて使い回す
- 入力の流れは「キーの列 → 期待する `ClientAction` の列」の表で書く(`InputSessionScenarioTests`)．要件(R-xx)の受け入れ条件はここで確かめる
- 変換結果そのもの(どの漢字になるか)はエンジンの性能なので，core のテストでは固定の結果を返す Fake を使う
- Windows の TSF は単体テストが難しいので，`ClientAction` から COM の呼び出しへの変換だけを関数に切り出して試す
- 本物の Zenzai を使うテスト(環境変数 `HAJIME_ZENZAI_MODEL` があるときだけ動く)と 1 キーの処理時間(R-01)は，`make test-zenzai` で Release ビルドで動かす．`make test` はモデルがあればこれも動かし，無ければ飛ばしたことを最後に表示する．CI はモデルをキャッシュして毎回動かす

## コミットと PR

- main へはスカッシュマージだけで入れる．PR のタイトルがそのまま main のコミットになる(`docs/dev/REPOSITORY.md`)
- PR のタイトルとコミットは Conventional Commits．日本語で 1 行．スコープを必ず付ける(`core`，`macos`，`windows`，`protocol`，`design`，`docs`，`adr`，`skills`，`ci`，`repo`，`deps`)
- PR は `.github/PULL_REQUEST_TEMPLATE.md` に従う．要件の ID(R-xx)と ADR があれば書く
- 設計の判断を変える PR には ADR を足す(`docs/dev/adr/README.md`)
