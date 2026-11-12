import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

/// 確定した直後に，確定する前に戻す(キー設定の表の「確定の取り消し」．R-17)
@Suite("確定の取り消し")
@MainActor
struct CommitUndoScenarioTests {
    /// 「きょう｜あめ」の 2 つの文節に分けて変換する変換器
    private static func converter() -> FakeConverter {
        FakeConverter(["きょうあめ": [("今日雨", nil)], "きょう": [("今日", nil), ("京", nil)], "あめ": [("雨", nil), ("飴", nil)]])
    }

    /// 「今日｜雨」を変換し，後ろの文節を「飴」に選び直して確定し，入力先の入力位置の前に確定した文字があるようにする
    private static func committed(_ settings: Settings = DefaultSettings.settings, converter: FakeConverter = converter()) -> Harness {
        let harness = Harness(converter: converter, settings: settings)
        harness.context.precedingText = "昨日は"
        harness.type("kyou")
        harness.press(.space, .option)
        harness.type("ame")
        harness.press(.space)
        harness.press(.right)
        harness.press(.space)
        harness.press(.enter)
        harness.context.precedingText = "昨日は" + harness.committed
        return harness
    }

    @Test("確定した直後の ⌃⌫ で，確定した文字を消して確定する前の分岐図に戻す(文節の区切り・選んだ候補・注目している文節)．学習も取り消す")
    func undoesConversion() {
        let converter = Self.converter()
        let harness = Self.committed(converter: converter)
        #expect(harness.committed == "今日飴")
        let learned = converter.committed.map(\.text)
        harness.press(.backspace, .control)
        #expect(harness.lastResult.handled)
        #expect(harness.committed.isEmpty)
        #expect(harness.marked.text == "今日飴")
        #expect(harness.lattice?.columns.map(\.text) == ["今日", "飴"])
        #expect(harness.lattice?.columns.map(\.isFocused) == [false, true])
        #expect(harness.lattice?.note?.text == "確定を取り消しました")
        #expect(converter.forgotten.map(\.text) == learned)
        #expect(converter.reopenCount == 1)
        #expect(converter.leftContext == "昨日は")
    }

    @Test("取り消したあとは続けて選び直せ，確定し直すと学ぶ．Esc は確定する前の変更の取り消しの段から戻す")
    func continuesAfterUndo() {
        let converter = Self.converter()
        let harness = Self.committed(converter: converter)
        harness.press(.backspace, .control)
        harness.press(.left)
        harness.press(.space)
        harness.press(.enter)
        #expect(harness.committed == "京飴")
        #expect(converter.committed.suffix(2).map(\.text) == ["京", "飴"])

        let escaped = Self.committed()
        escaped.press(.backspace, .control)
        escaped.press(.escape)
        #expect(escaped.lattice?.columns.map(\.text) == ["今日", "雨"])
    }

    @Test("読みのまま・ライブ変換のまま確定した直後は，組み立て中の文字に戻す")
    func undoesComposing() {
        let harness = Harness(converter: FakeConverter(["きょう": [("今日", nil)]]))
        harness.type("kyou")
        harness.settle()
        harness.press(.enter)
        #expect(harness.committed == "今日")
        harness.context.precedingText = harness.committed
        harness.press(.backspace, .control)
        #expect(harness.committed.isEmpty)
        #expect(harness.marked.text == "今日")
        #expect(harness.lattice == nil && harness.panel == nil)
        // 打ち続けられる
        harness.type("ha")
        #expect(harness.marked.text.hasSuffix("は"))
    }

    @Test("アプリから読める前の文字列より長い文を確定したときも，読めた分が確定した文の終わりなら取り消す")
    func undoesLongCommit() {
        let harness = Harness(converter: FakeConverter())
        harness.type(String(repeating: "a", count: DefaultSettings.maximumLeftContextLength + 5))
        harness.press(.enter)
        #expect(harness.committed.count == DefaultSettings.maximumLeftContextLength + 5)
        harness.context.precedingText = String(harness.committed.suffix(DefaultSettings.maximumLeftContextLength))
        harness.press(.backspace, .control)
        #expect(harness.committed.isEmpty)
        #expect(harness.marked.text.count == DefaultSettings.maximumLeftContextLength + 5)
        // 読めた分が短ければ(入力欄の頭に近い)，確定した文の終わりでも取り消さない
        let short = Harness(converter: FakeConverter())
        short.type(String(repeating: "a", count: DefaultSettings.maximumLeftContextLength + 5))
        short.press(.enter)
        short.context.precedingText = String(short.committed.suffix(3))
        short.press(.backspace, .control)
        #expect(!short.lastResult.handled)
    }

    @Test("確定した直後の変換のキーも確定を取り消す(選んでいる文字が無いので)．読みのまま確定したものは変換して出す")
    func henkanUndoes() {
        let harness = Self.committed()
        harness.press(.henkan)
        #expect(harness.committed.isEmpty)
        #expect(harness.lattice?.columns.map(\.text) == ["今日", "飴"])
        #expect(!harness.lastResult.actions.contains(.requestReconversion))

        let typed = Harness(converter: FakeConverter(["きょう": [("今日", nil), ("京", nil)]]))
        typed.type("kyou")
        typed.press(.enter)
        typed.context.precedingText = typed.committed
        typed.press(.henkan)
        #expect(typed.committed.isEmpty)
        #expect(typed.lattice?.columns.map(\.text) == ["今日"])
    }

    @Test("直後でなければ取り消さず，キーはアプリに渡す(別のキーを押したあと・入力位置の前が確定した文字でないとき・置き換えられない入力先)．変換のキーは選んでいる文字を求める")
    func passesThroughOtherwise() {
        let later = Self.committed()
        later.press(.left)
        later.press(.backspace, .control)
        #expect(!later.lastResult.handled)
        let moved = Self.committed()
        moved.context.precedingText = "昨日は今日飴を"
        moved.press(.backspace, .control)
        #expect(!moved.lastResult.handled)
        #expect(moved.lattice == nil)
        let old = Self.committed()
        old.context.canReplacePrecedingText = false
        old.press(.backspace, .control)
        #expect(!old.lastResult.handled)
        let henkan = Self.committed()
        henkan.context.precedingText = "別の文"
        henkan.press(.henkan)
        #expect(henkan.lastResult.actions == [.requestReconversion])
        // 確定していなければ何もしない
        let fresh = Harness(converter: Self.converter())
        fresh.context.precedingText = "昨日は"
        fresh.press(.backspace, .control)
        #expect(!fresh.lastResult.handled)
    }

    @Test("予測を確定した直後は，⌃⌫ でも補う前の読みに戻す．変換のキーは予測の確定を取り消さない")
    func undoesPrediction() {
        var settings = DefaultSettings.settings
        settings.predictionDisplay = .always
        let make = {
            let converter = FakeConverter(["えぴ": [("エピ", nil)]])
            converter.predictionTexts["えぴ"] = ["エピ", "エピソード"]
            let harness = Harness(converter: converter, settings: settings)
            harness.type("epi")
            harness.press(.tab)
            harness.context.precedingText = harness.committed
            return harness
        }
        let harness = make()
        #expect(harness.committed == "エピソード")
        harness.press(.backspace, .control)
        #expect(harness.committed.isEmpty)
        #expect(harness.marked.text == "えぴ")
        let henkan = make()
        henkan.press(.henkan)
        #expect(henkan.committed == "エピソード")
        #expect(henkan.lastResult.actions == [.requestReconversion])
    }

    @Test("学習を使わずに変換して確定したものを取り消しても，その前の確定の学習は取り消さない")
    func keepsEarlierLearning() {
        let converter = Self.converter()
        var settings = DefaultSettings.settings
        settings.keymap.entries.append(KeymapEntry(.composing, KeyStroke(.function(2)), .convertWithoutLearning))
        let harness = Harness(converter: converter, settings: settings)
        harness.type("kyou")
        harness.press(.space)
        harness.press(.enter)
        harness.type("ame")
        harness.press(.function(2))
        harness.press(.enter)
        harness.context.precedingText = harness.committed
        #expect(harness.committed == "今日雨")
        harness.press(.backspace, .control)
        #expect(harness.committed == "今日")
        #expect(converter.forgotten.isEmpty)
    }

    @Test("取り消すキーはキー設定の表で変えられ，割り当てを消すと取り消さない")
    func customKey() {
        var custom = DefaultSettings.settings
        custom.keymap.entries.removeAll { $0.command == .undoCommit }
        custom.keymap.entries.append(KeymapEntry(.idle, KeyStroke(.character("z"), control: true), .undoCommit))
        let harness = Self.committed(custom)
        harness.press(.backspace, .control)
        #expect(!harness.lastResult.handled)
        harness.press(.character("z"), .control)
        #expect(!harness.lastResult.handled)

        let changed = Self.committed(custom)
        changed.press(.character("z"), .control)
        #expect(changed.committed.isEmpty)
        #expect(changed.lattice?.columns.map(\.text) == ["今日", "飴"])
    }

    @Test("どのひな形も，入力文字なしの Ctrl+Backspace で確定を取り消す", arguments: KeymapPreset.allCases)
    func presets(preset: KeymapPreset) {
        #expect(preset.keymap.command(for: KeyStroke(.backspace, control: true), in: .idle) == .undoCommit)
    }
}
