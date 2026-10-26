import S90Application
import S90Domain
import S90TestSupport
import Testing

@MainActor
@Suite("入力の機能(テンキー・切り替えのキー・記号・補正・読み違い・計算・送り仮名)")
struct FeatureScenarioTests {
    @Test("R-08: テンキーの数字は，読みを確定してから半角のまま確定する．設定を切れば読みに入れる")
    func keypad() {
        let harness = Harness(converter: FakeConverter(["か": [("蚊", nil)]]))
        harness.type("ka")
        harness.press(.character("1"), isKeypad: true)
        #expect(harness.committed == "蚊1")
        #expect(harness.marked.isEmpty)

        var settings = DefaultSettings.settings
        settings.keypadDirect = false
        let off = Harness(settings: settings)
        off.press(.character("1"), isKeypad: true)
        #expect(off.committed.isEmpty)
        #expect(off.marked.text == "1")
    }

    @Test("R-09: 半角/全角は日本語と英数を入れ替え，変換を「日本語にする」にすれば英数から日本語にする")
    func modeKeys() {
        var settings = DefaultSettings.settings
        settings.modeKeys.henkan = .japanese
        let harness = Harness(settings: settings)
        harness.press(.hankakuZenkaku)
        #expect(harness.session.mode == .direct)
        harness.press(.hankakuZenkaku)
        #expect(harness.session.mode == .japanese)
        harness.press(.eisu)
        #expect(harness.session.mode == .direct)
        harness.press(.henkan)
        #expect(harness.session.mode == .japanese)
    }

    @Test("R-09: 切り替えに使わない変換は Space と同じに変換し，無変換はカタカナにする")
    func henkanMuhenkan() {
        let harness = Harness(converter: FakeConverter(["かな": [("仮名", nil)]]), settings: .listPresentation)
        harness.type("kana")
        harness.press(.muhenkan)
        #expect(harness.marked.text == "カナ")
        let convert = Harness(converter: FakeConverter(["かな": [("仮名", nil)]]))
        convert.type("kana")
        convert.press(.henkan)
        #expect(convert.lattice != nil)
    }

    @Test("R-10: 利用者が変えた記号の決まりで「->」をまとめる")
    func symbolRule() {
        var settings = DefaultSettings.settings
        settings.symbolRules = [SymbolRule(kind: .sequence, input: "->", output: "⟶")]
        let harness = Harness(settings: settings)
        harness.type("a->")
        #expect(harness.marked.text.hasSuffix("⟶"))
    }

    @Test("R-02: 英単語の補正を切れば直さず，直さない語は直さない")
    func englishToggle() {
        var settings = DefaultSettings.settings
        settings.correction.english = false
        let off = Harness(lexicon: FakeLexicon(suggestions: ["pthon": ["python"]]), settings: settings)
        off.type("pthon")
        #expect(off.marked.text != "python")

        var exceptions = DefaultSettings.settings
        exceptions.correction.exceptions = ["pthon"]
        let skip = Harness(lexicon: FakeLexicon(suggestions: ["pthon": ["python"]]), settings: exceptions)
        skip.type("pthon")
        #expect(skip.marked.text != "python")
    }

    @Test("R-02: 利用者が足した置き換えの決まりを，綴りの辞書より先に使う")
    func customRule() {
        var settings = DefaultSettings.settings
        settings.correction.rules = [CorrectionRule(typed: "pthon", word: "Python3")]
        let harness = Harness(lexicon: FakeLexicon(suggestions: ["pthon": ["python"]]), settings: settings)
        harness.type("pthon")
        #expect(harness.marked.text == "Python3")
    }

    @Test("R-02: 日本語の打ち間違いの補正を切れば，打鍵が止まっても直さない")
    func japaneseToggle() {
        let converter = FakeConverter()
        converter.corrections["youdesu"] = [
            ReadingCorrection(keys: "yoidesu", reading: "ヨイデス", score: -5, cost: 2),
            ReadingCorrection(keys: "youdesu", reading: "ヨウデス", score: -9, cost: 0),
        ]
        var settings = DefaultSettings.settings
        settings.correction.japanese = false
        settings.misreadings = false
        let harness = Harness(converter: converter, settings: settings)
        harness.type("youdesu")
        harness.settle()
        #expect(harness.marked.text == "ようです")
    }

    @Test("R-02: よくある読み違いは候補に正しい語を足し，止まれば「もしかして」と示して Tab で直す")
    func misreading() {
        let converter = FakeConverter(["ふいんき": [("ふいんき", nil)], "ふんいき": [("雰囲気", nil)]])
        let harness = Harness(converter: converter, settings: .listPresentation)
        harness.type("fuinnki")
        harness.settle()
        #expect(harness.note?.contains("雰囲気") == true)
        harness.press(.tab)
        #expect(harness.marked.text == "雰囲気")
        let supplemented = SupplementedConverter(FakeConverter(["ふいんき": [("ふいんき", nil)]]), settings: FakeSettings(), calendar: FakeCalendar())
        #expect(supplemented.candidates(for: "ふいんき").map(\.text) == ["ふいんき", "雰囲気"])
    }

    @Test("R-11: 「=」で終わる式は，計算した結果を先頭の候補にする")
    func calculation() {
        let converter = SupplementedConverter(FakeConverter(), settings: FakeSettings(), calendar: FakeCalendar())
        #expect(converter.candidates(for: "1＋2＊3＝").prefix(2).map(\.text) == ["7", "1+2*3=7"])
        var off = DefaultSettings.settings
        off.calculation = false
        #expect(SupplementedConverter(FakeConverter(), settings: FakeSettings(off), calendar: FakeCalendar()).candidates(for: "1＋2＝").isEmpty)
    }

    @Test("R-12: 送り仮名は既定で本則を先にし，許容を選べば許容を先にする")
    func okurigana() {
        let base = FakeConverter(["おこなう": [("行なう", nil), ("行う", nil)]])
        #expect(SupplementedConverter(base, settings: FakeSettings(), calendar: FakeCalendar()).candidates(for: "おこなう").first?.text == "行う")
        var allowed = DefaultSettings.settings
        allowed.okuriganaStyle = .allowed
        #expect(SupplementedConverter(base, settings: FakeSettings(allowed), calendar: FakeCalendar()).candidates(for: "おこなう").first?.text == "行なう")
    }
}
