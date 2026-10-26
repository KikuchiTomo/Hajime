import S90Application
import S90Domain
import S90TestSupport
import Testing

/// 英字入力のライブ変換と英字入力(自動)(R-05)，英語にも日本語にも読める語の見分け(R-02)
@Suite("英字入力(自動)と英字入力のライブ変換")
@MainActor
struct EnglishAutoScenarioTests {
    private func harness(_ style: InputStyle, liveConversion: Bool = false, converter: FakeConverter = FakeConverter(),
                         lexicon: Set<String> = ["hello", "world", "make", "shine", "sense"], change: (inout Settings) -> Void = { _ in }) -> Harness {
        var settings = DefaultSettings.settings
        settings.inputStyle = style
        settings.englishInputLiveConversion = liveConversion
        change(&settings)
        return Harness(converter: converter, lexicon: FakeLexicon(words: lexicon), settings: settings)
    }

    private var converter: FakeConverter {
        FakeConverter([
            "きょうはいいてんき": [("今日はいい天気", nil)],
            "まけ": [("負け", nil)],
            "しね": [("死ね", nil), ("市ね", nil)],
        ])
    }

    // MARK: - 英字入力のライブ変換

    @Test("R-05: 英字入力のライブ変換がオフなら，英字のまま見せて日本語は候補に添えるだけ")
    func manualWithoutLiveConversion() {
        let harness = harness(.english, converter: converter)
        harness.type("kyouhaiitenki")
        #expect(harness.marked.text == "kyouhaiitenki")
        #expect(harness.panel?.entries.map(\.text) == ["今日はいい天気"])
        harness.press(.space)
        #expect(harness.committed == "kyouhaiitenki")
        #expect(!harness.lastResult.handled)
    }

    @Test("R-05: 英字入力のライブ変換がオンなら，ローマ字として読める語を日本語にして見せ，Space で日本語を確定する(空白は入れない)")
    func manualWithLiveConversion() {
        let harness = harness(.english, liveConversion: true, converter: converter)
        harness.type("kyouhaiitenki")
        #expect(harness.marked.text == "今日はいい天気")
        #expect(harness.panel?.entries.map(\.text) == ["kyouhaiitenki"])
        harness.press(.space)
        #expect(harness.committed == "今日はいい天気")
        #expect(harness.lastResult.handled)
        // 読めない語は英字のまま
        harness.type("hello")
        #expect(harness.marked.text == "hello")
    }

    @Test("R-05: 日本語にして見せている語は Esc で英字に戻し，Enter で英字を確定する")
    func escapeBackToLetters() {
        let harness = harness(.english, liveConversion: true, converter: converter)
        harness.type("kyouhaiitenki")
        harness.press(.escape)
        #expect(harness.marked.text == "kyouhaiitenki")
        #expect(harness.committed.isEmpty)
        harness.press(.enter)
        #expect(harness.committed == "kyouhaiitenki")
        #expect(!harness.lastResult.handled)
    }

    // MARK: - 英字入力(自動)

    @Test("R-05: 英字入力(自動)は，日本語にできる語を日本語にし，英語の語は英語のまま")
    func automatic() {
        let harness = harness(.englishAuto, converter: converter)
        harness.type("hello")
        #expect(harness.marked.text == "hello")
        harness.press(.space)
        #expect(harness.committed == "hello")
        harness.type("kyouhaiitenki")
        #expect(harness.marked.text == "今日はいい天気")
        harness.press(.enter)
        #expect(harness.committed == "hello今日はいい天気")
    }

    @Test("R-05: 英字入力(自動)で日本語らしくない読みは英語のまま(英語の辞書にない語でも)")
    func automaticKeepsImplausible() {
        let converter = converter
        converter.table["かてぃお"] = [("かてぃお", nil)]
        converter.scores["かてぃお"] = -40
        let harness = harness(.englishAuto, converter: converter)
        harness.type("kathio")
        #expect(harness.marked.text == "kathio")
    }

    @Test("R-02: 英語にも日本語にも読める語(「make」)は，前が英語なら英語，前が日本語なら日本語", arguments: [
        ("Let's ", "make"),
        ("試合に", "負け"),
        (nil, "make"),
    ] as [(String?, String)])
    func ambiguousByContext(preceding: String?, expected: String) {
        let harness = harness(.englishAuto, converter: converter)
        harness.context = InputContext(precedingText: preceding)
        harness.type("make")
        #expect(harness.marked.text == expected)
    }

    @Test("R-02: 前の手がかりで見分けない設定なら，英字入力(自動)では英語にする")
    func ambiguousWithoutContext() {
        let harness = harness(.englishAuto, converter: converter) { $0.wordLanguage.usesContext = false }
        harness.context = InputContext(precedingText: "試合に")
        harness.type("make")
        #expect(harness.marked.text == "make")
    }

    @Test("R-02: 不適切な語(「shine」→ しね)は，前が日本語でなければ日本語にしない")
    func offensiveStaysEnglish() {
        let harness = harness(.englishAuto, converter: converter)
        harness.type("shine")
        #expect(harness.marked.text == "shine")
    }

    @Test("R-02: 利用者が決めた「いつも英語」「いつも日本語」の語と，見分け方の決まりを先に使う")
    func userWords() {
        let japanese = harness(.englishAuto, converter: converter) { $0.wordLanguage.japaneseWords = ["make"] }
        japanese.type("make")
        #expect(japanese.marked.text == "負け")

        let english = harness(.englishAuto, converter: converter) { $0.wordLanguage.englishWords = ["kyouhaiitenki"] }
        english.type("kyouhaiitenki")
        #expect(english.marked.text == "kyouhaiitenki")

        let rule = harness(.englishAuto, converter: converter) {
            $0.wordLanguage.rules = [WordLanguageRule(word: "make", context: .afterJapanese, language: .english)]
        }
        rule.context = InputContext(precedingText: "試合に")
        rule.type("make")
        #expect(rule.marked.text == "make")
    }

    @Test("R-05: 英字入力(自動)でも Tab で分岐図を開き，Esc で英字に戻す")
    func automaticTab() {
        let converter = converter
        let harness = harness(.englishAuto, converter: converter)
        harness.type("kyouhaiitenki")
        harness.press(.tab)
        #expect(harness.lattice != nil)
        harness.press(.escape)
        #expect(harness.marked.text == "kyouhaiitenki")
    }

    @Test("R-05: 入力方式の切り替えはローマ字 → かな → 英字 → 英字(自動)の順")
    func cycle() {
        #expect(InputStyle.allCases == [.romaji, .kana, .english, .englishAuto])
        #expect(InputStyle.englishAuto.typesLetters)
        #expect(!InputStyle.romaji.typesLetters)
    }

    // MARK: - ローマ字入力の英単語

    @Test("R-02: ローマ字入力で，前が英語の「make」は英語にし，そうでなければ日本語のまま", arguments: [
        ("Let's ", "make"),
        (nil, "負け"),
        ("試合に", "負け"),
    ] as [(String?, String)])
    func romajiAmbiguous(preceding: String?, expected: String) {
        let harness = harness(.romaji, converter: converter)
        harness.context = InputContext(precedingText: preceding)
        harness.type("make")
        harness.settle()
        #expect(harness.marked.text == expected)
        harness.press(.enter)
        #expect(harness.committed == expected)
    }

    @Test("R-02: ローマ字入力でも，利用者が「いつも英語」にした語は英語にする")
    func romajiUserEnglish() {
        let harness = harness(.romaji, converter: converter) { $0.wordLanguage.englishWords = ["make"] }
        harness.type("make")
        harness.settle()
        #expect(harness.marked.text == "make")
    }

    @Test("設定の画面の「試す」は，入力と同じ見分け方で語ごとの結果を出し，前の語を次の語の手がかりにする")
    func preview() {
        let preview = WordLanguagePreview(converter: converter, lexicon: FakeLexicon(words: ["make", "sense"]), settings: FakeSettings())
        #expect(preview.preview("make sense").map(\.shown) == ["make", "sense"])
        #expect(preview.preview("make", precedingText: "試合に").map(\.shown) == ["負け"])
        let words = preview.preview("kyouhaiitenki make")
        #expect(words.map(\.language) == [.japanese, .japanese])
        #expect(words.map(\.shown) == ["今日はいい天気", "負け"])
    }

    @Test("R-02: 不適切な語を第 1 候補に出さない(設定)")
    func demotesOffensive() {
        let base = FakeConverter(["しね": [("死ね", nil), ("市ね", nil)], "ころす": [("殺す", nil)]])
        let converter = SupplementedConverter(base, settings: FakeSettings(), calendar: FakeCalendar())
        #expect(converter.candidates(for: "しね").first?.text == "市ね")
        #expect(converter.candidates(for: "ころす").first?.text == "ころす")
        var off = DefaultSettings.settings
        off.wordLanguage.avoidsOffensive = false
        #expect(SupplementedConverter(base, settings: FakeSettings(off), calendar: FakeCalendar()).candidates(for: "しね").first?.text == "死ね")
    }
}
