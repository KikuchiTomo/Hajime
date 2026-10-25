# 原則の具体例

SKILL.md の SOLID と DRY の項目を，このリポジトリで起きる形で示す．

## 単一責任

悪い形(azooKey-Desktop の `azooKeyMacInputController` に近い):

```swift
final class InputController: IMKInputController {
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        // キーの解釈，ローマ字の変換，変換エンジンの呼び出し，
        // 候補ウィンドウの位置の計算，設定の読み込みがすべてここにある
    }
}
```

よい形:

```swift
final class S90InputController: IMKInputController {
    // CompositionRoot が作って渡す．このクラスは OS との受け渡しだけをする
    private let session: InputSession
    private let keyTranslator: NSEventKeyTranslator
    private let presenter: ClientActionPresenter

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let key = keyTranslator.translate(event) else { return false }
        let actions = session.handle(key, context: contextProvider.current(for: sender))
        presenter.apply(actions, to: sender)
        return actions.consumesKey
    }
}
```

## 開放閉鎖

入力方式を足すたびに `InputSession` の `switch` を書き換えないよう，方式ごとの読みの組み立ては protocol の実装にする．

```swift
protocol ReadingComposer: Sendable {
    func compose(_ key: KeyEvent, into reading: Reading) -> ComposeResult
}
struct RomajiComposer: ReadingComposer { ... }
struct KanaComposer: ReadingComposer { ... }
struct EnglishPassthroughComposer: ReadingComposer { ... }
```

一方，`ScriptVariant`(そのまま・カタカナ・半角カタカナ・全角英数・半角英数)は種類が増えても数個で，使う側で網羅を確かめたいので enum のままにする．

## インターフェース分離

```swift
// 悪い: 設定画面しか使わない操作まで，入力の処理が知ってしまう
protocol Storage { func settings() ...; func save(_:) ...; func importDictionary(_:) ...; func clearLearning() ... }

// よい: 使う側ごとに切る
protocol SettingsReading: Sendable { func current() -> Settings }
protocol LearningRecording: Sendable { func record(_ committed: CommittedText) }
protocol UserDictionaryImporting { func importEntries(from data: Data) throws -> ImportReport }
```

## DRY と，まとめないほうがよい重複

- まとめる: ¥ キーの割り当ての判断は `YenKeyPolicy` の 1 か所．macOS と Windows のアダプタは結果を受け取るだけ
- まとめない: macOS の仮想キーコードと Windows の仮想キーコードから `KeyEvent` への表．形は似ていても，変わる理由(OS の仕様)が別

## テストの Fake

```swift
// core/Tests/Support/FakeConverter.swift
struct FakeConverter: KanaKanjiConverting {
    var table: [String: [Candidate]]
    func convert(_ reading: Reading, options: ConvertOptions) async throws -> [Candidate] {
        // 本物と同じく，空の読みには空の配列を返す(事後条件をそろえる)
        table[reading.text] ?? []
    }
}
```
