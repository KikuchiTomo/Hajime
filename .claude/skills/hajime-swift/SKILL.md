---
name: hajime-swift
description: Hajime の Swift コード(core/ の HajimeCore パッケージ，apps/macos の InputMethodKit・AppKit・SwiftUI)を書く・直す・テストするときの決まり．Swift 6 の並行性(actor，Sendable，@MainActor)，エラーの型，依存の注入，Swift Testing によるテスト，InputMethodKit の注意点を含む．.swift ファイルや Package.swift，project.yml に触れるときは必ず使う．Use whenever writing, editing, testing or reviewing Swift in this repository.
---

# Swift の決まり

置き場所と層は `hajime-architecture` スキルで先に決める．ここには Swift の書き方だけを書く．

## 言語と道具

- Swift 6 の言語モード．厳格な並行性チェックの警告を残さない
- `core/` は macOS・Windows・Linux でビルドする．`#if os(...)` は Engine と Persistence のアダプタの中だけに置き，Domain と Application には書かない
- 形式は `swift-format`(設定は `.swift-format`)，静的検査は SwiftLint
- macOS のアプリは `apps/macos/project.yml`(XcodeGen)から Xcode プロジェクトを作る．`.xcodeproj` はコミットしない(PR の競合を減らすため)

## 型

- 値は `struct` と `enum`．参照の同一性が要るものと OS の型を継承するものだけ `class`(`final` を付ける)
- Domain の型は `Sendable` にする
- 入力の中身を持つ型は `description` で中身を伏せる(`hajime-security` の「型で漏れを防ぐ」)
- 文字の種類の変換(ひらがな → カタカナ，全角 ↔ 半角)は `Character` 単位ではなく Unicode のスカラー値の表で行い，`applyingTransform` には頼らない．OS ごとに結果が違うことがあるため

## 並行性

- UI に触る型(候補ウィンドウ，`IMKInputController` のサブクラス)は `@MainActor`
- 変換エンジンの呼び出しは `actor` の中に閉じ込める．`InputSession` は結果を待たずに読みを返し，結果は `AsyncStream<ClientAction>` で後から流す
- 古い変換結果で画面を上書きしないよう，要求ごとに番号を振り，最新の番号の結果だけを反映する
- `Task.detached` と `DispatchQueue.global` は使わない．並行性の境界がコンパイラから見えなくなるため
- `@unchecked Sendable` と `nonisolated(unsafe)` は使わない．どうしても要るときは理由をコメントに書き，PR で説明する

## エラー

- 回復できるエラーは `throws(具体的なエラー型)` か `Result`．エラー型はモジュールごとの `enum`
- `try!`，`fatalError`，`!` による強制アンラップは，テストと「起きたらプログラムの誤り」と言える箇所だけ．その場合もコメントで理由を書く
- エラーメッセージに入力の中身を入れない

## 依存の注入

```swift
// Application のユースケース．ポートの protocol だけを知る
struct TypoCorrectionService: Sendable {
    private let lexicon: any EnglishLexicon
    private let policy: TypoCorrectionPolicy

    init(lexicon: any EnglishLexicon, policy: TypoCorrectionPolicy) {
        self.lexicon = lexicon
        self.policy = policy
    }
}
```

- イニシャライザで受け取り，プロパティで持つ．プロパティへの後からの代入で差し替えない
- 既定の引数で具象を作らない(`init(lexicon: any EnglishLexicon = BundledLexicon())` は書かない)．具象を知るのは composition root だけ

## テスト

- Swift Testing(`import Testing`，`@Test`，`#expect`)を使う
- 入力の流れはパラメータ化したテストで，キーの列と期待する `ClientAction` の列を表にする．要件の ID をテスト名に入れる

```swift
@Test("R-02: 補正の直後の Space で入力のままに戻る")
func spaceRevertsCorrection() async throws {
    let session = InputSession.make(converter: FakeConverter(table: [:]), lexicon: FakeLexicon(["python"]))
    session.type("pthon")
    #expect(session.markedText == "python")
    session.press(.space)
    #expect(session.markedText == "pthon")
}
```

- Fake は `core/Tests/Support/` に置いて共有する．テストごとに似た Fake を作らない

## InputMethodKit の注意点

詳しくは `references/inputmethodkit.md`．

- `IMKInputController` は入力先のアプリ(クライアント)ごとに作られる．状態を持たせる場合は，アプリをまたいで混ざらないようにする
- `client()` は呼ぶたびに取得し，保持しない
- `handle(_:client:)` は素早く返す．変換を待たない
- 候補ウィンドウは `IMKCandidates` を使わず自前の `NSPanel` で描く(デザインの決まりを守るため)．`NSPanel` は `.nonactivatingPanel` にし，フォーカスを奪わない
