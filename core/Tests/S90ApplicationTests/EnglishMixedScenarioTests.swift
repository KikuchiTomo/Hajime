import S90Application
import S90Domain
import S90TestSupport
import Testing

/// 英語の混ざる入力(R-02)とプログラミング中の決まり(R-06)．
/// 英単語は英単語の補正の受け持ちで，日本語の打ち間違いの見直しで日本語に直さない．分岐図では英単語を 1 つの文節にする
@Suite("英語の混ざる入力")
@MainActor
struct EnglishMixedScenarioTests {
    private func words(_ texts: [String], particles: Set<String> = []) -> [Candidate.Word] {
        texts.map { Candidate.Word(text: $0, readingCount: $0.count, startsWithParticle: particles.contains($0)) }
    }

    @Test("R-02: 英単語のあとの日本語を見直しても，英単語を日本語に直さない(「pythonがすごい」が「ぴょんがすごい」にならない)")
    func reviewKeepsEnglishWord() {
        let converter = FakeConverter(["pythonがすごい": [("pythonがすごい", nil)]])
        // 打ったキー全体を見直すと「ぴょん」に直してしまう訂正
        converter.corrections["pythongasugoi"] = [
            ReadingCorrection(keys: "pyongasugoi", reading: "ピョンガスゴイ", score: -1, cost: 1),
            ReadingCorrection(keys: "pythongasugoi", reading: KanaWidth.katakana(from: "pythonがすごい"), score: -20, cost: 0),
        ]
        let harness = Harness(converter: converter, lexicon: FakeLexicon(words: ["python"]))
        harness.type("pythongasugoi")
        harness.settle()
        #expect(harness.marked.text == "pythonがすごい")
        #expect(!harness.marked.segments.contains { $0.style == .correction })
        harness.press(.enter)
        #expect(harness.committed == "pythonがすごい")
    }

    @Test("R-02: 英単語より後ろの日本語の打ち間違いは直し，Esc で打ったままに戻せる")
    func reviewsJapaneseAfterEnglish() {
        let converter = FakeConverter()
        converter.corrections["noyoudesu"] = [
            ReadingCorrection(keys: "noyoidesu", reading: "ノヨイデス", score: -1, cost: 1),
            ReadingCorrection(keys: "noyoudesu", reading: "ノヨウデス", score: -9, cost: 0),
        ]
        let harness = Harness(converter: converter, lexicon: FakeLexicon(words: ["python"]))
        harness.type("pythonnoyoudesu")
        harness.settle()
        #expect(harness.marked.text == "pythonのよいです")
        #expect(harness.marked.segments.contains { $0.style == .correction })
        harness.press(.escape)
        #expect(harness.marked.text == "pythonのようです")
    }

    @Test("R-02: Shift で打った英字(「IME」)のあとも，英字は見直しに含めない")
    func reviewSkipsShiftedLetters() {
        let converter = FakeConverter()
        converter.corrections["hayoudesu"] = [
            ReadingCorrection(keys: "hayoidesu", reading: "ハヨイデス", score: -1, cost: 1),
            ReadingCorrection(keys: "hayoudesu", reading: "ハヨウデス", score: -9, cost: 0),
        ]
        let harness = Harness(converter: converter)
        harness.type("konoIMEhayoudesu")
        harness.settle()
        #expect(harness.marked.text == "このIMEはよいです")
    }

    @Test("R-02: ローマ字として読めてしまう英単語も，助詞が続いて日本語より確からしければ英単語にする(「gitwotukau」→「gitを使う」)")
    func wordReadAsRomaji() {
        let converter = FakeConverter(["gitをつかう": [("gitを使う", nil)]])
        converter.scores = ["ぎとぉつかう": -52, "をつかう": -16]
        // 打ったキー全体を見直すと「必要」にしてしまう訂正
        converter.corrections["gitwotukau"] = [
            ReadingCorrection(keys: "hituyou", reading: "ヒツヨウ", score: -1, cost: 3),
            ReadingCorrection(keys: "gitwotukau", reading: "ギトォツカウ", score: -30, cost: 0),
        ]
        let harness = Harness(converter: converter, lexicon: FakeLexicon(words: ["git"]))
        harness.type("gitwotukau")
        harness.settle()
        #expect(harness.marked.text == "gitを使う")
        harness.press(.enter)
        #expect(harness.committed == "gitを使う")
    }

    @Test("R-02: 打鍵が止まる前に Enter を押しても，ローマ字として読めてしまう英単語を英単語にして確定する")
    func wordReadAsRomajiOnEnter() {
        let converter = FakeConverter(["gitをつかう": [("gitを使う", nil)]])
        converter.scores = ["ぎとぉつかう": -52, "をつかう": -16]
        let harness = Harness(converter: converter, lexicon: FakeLexicon(words: ["git"]))
        harness.type("gitwotukau")
        harness.press(.enter)
        #expect(harness.committed == "gitを使う")
    }

    @Test("R-02: 日本語として確からしい読みは英単語にしない(「kitto」の「kit」)", arguments: [
        ("kitto", "きっと", ["kit"], ["きっと": -8.0, "と": -9.0]),
        // 区切りに合う語(「kite」→ きて)は調べない
        ("kitewo", "きてを", ["kite"], ["きてを": -40.0, "を": -5.0]),
        // 助詞などが続かないものは調べない(打ち間違いのある日本語の一部を英単語と取り違えない)
        ("arigatoou", "ありがとおう", ["gat"], ["がとおう": -40.0, "おう": -5.0]),
    ])
    func keepsJapanese(keys: String, reading: String, english: [String], scores: [String: Double]) {
        let converter = FakeConverter([reading: [(reading, nil)]])
        converter.scores = scores
        let harness = Harness(converter: converter, lexicon: FakeLexicon(words: Set(english)))
        harness.type(keys)
        harness.settle()
        #expect(harness.marked.text == reading)
    }

    @Test("R-02: 英単語の終わりが次の日本語の綴りにかかっても(「react」+「wo」)，打っているあいだに英単語にする")
    func unreadableWordBeforeParticle() {
        let converter = FakeConverter(["reactを": [("reactを", nil)]])
        converter.scores = ["をつかう": -16, "を": -5]
        let harness = Harness(converter: converter, lexicon: FakeLexicon(words: ["react"]))
        harness.type("reactwo")
        #expect(harness.marked.text.hasPrefix("react"))
        harness.press(.enter)
        #expect(harness.committed == "reactを")
    }

    // MARK: - 分岐図

    @Test("分岐図では英単語を 1 つの文節にする", arguments: [
        ("pythongasugoi", "pythonがすごい", ["p", "y", "t", "h", "o", "n", "がすごい"], ["python"], ["pythonが", "すごい"]),
        ("konoIMEha", "このIMEは", ["この", "I", "M", "E", "は"], [], ["この", "IMEは"]),
        ("AAAmade", "AAAまで", ["A", "A", "A", "まで"], [], ["AAAまで"]),
    ])
    func latticeKeepsEnglishTogether(keys: String, reading: String, segmentation: [String], english: [String], expected: [String]) throws {
        let converter = FakeConverter([reading: [(reading, nil)]])
        converter.words[reading] = words(segmentation, particles: ["がすごい", "は", "まで"])
        // エンジンの最初の文節は英字 1 文字のことがある
        converter.clauseTable[reading] = [(String(reading.prefix(1)), 1)]
        let harness = Harness(converter: converter, lexicon: FakeLexicon(words: Set(english)))
        harness.type(keys)
        harness.press(.space)
        let columns = try #require(harness.lattice?.columns)
        #expect(columns.map(\.text) == expected)
        harness.press(.enter)
        #expect(harness.committed == reading)
    }

    // MARK: - プログラミング中(R-06)

    @Test("R-06: エディタでは，日本語の文の中にない英単語の綴りを直さない")
    func noCorrectionOutsideJapaneseInEditor() {
        let lexicon = FakeLexicon(words: ["python"], suggestions: ["pthon": ["python"]])
        let editor = Harness(lexicon: lexicon)
        editor.context = InputContext(profile: .programming)
        editor.type("pthon")
        #expect(!editor.marked.text.contains("python"))

        let sentence = Harness(lexicon: lexicon)
        sentence.context = InputContext(profile: .programming)
        sentence.type("konopthon")
        #expect(sentence.marked.text.contains("python"))

        let standard = Harness(lexicon: lexicon)
        standard.type("pthon")
        #expect(standard.marked.text.contains("python"))
    }

    @Test("R-06: 識別子の続き(大文字・数字・_)を打ったら，直した英単語を打ったとおりに戻す", arguments: ["N", "2", "_"])
    func identifierKeepsTyped(next: String) {
        let lexicon = FakeLexicon(words: ["python"], suggestions: ["pthon": ["python"]])
        let harness = Harness(lexicon: lexicon)
        harness.context = InputContext(profile: .programming)
        harness.type("konopthon")
        #expect(harness.marked.text.contains("python"))
        harness.type(next)
        #expect(harness.marked.text.hasSuffix("pthon" + next))
    }

    @Test("R-06: 識別子の続き(「user_」「a.」のあと)の英字は直さない")
    func noCorrectionAfterIdentifier() {
        let lexicon = FakeLexicon(words: ["python"], suggestions: ["pthon": ["python"]])
        let harness = Harness(lexicon: lexicon)
        harness.context = InputContext(precedingText: "my_")
        harness.type("pthon")
        #expect(!harness.marked.text.contains("python"))
    }

    @Test("R-06: エディタでは打鍵が止まるまで読みのまま見せ，英数字を打っているあいだは止まっても変換しない")
    func restrainedLiveConversion() {
        let converter = FakeConverter(["きょうは": [("今日は", nil)], "きょうはID": [("今日はID", nil)]])
        let harness = Harness(converter: converter)
        harness.context = InputContext(profile: .programming)
        harness.type("kyouha")
        #expect(harness.marked.text == "きょうは")
        harness.settle()
        #expect(harness.marked.text == "今日は")
        harness.type("ID")
        harness.settle()
        #expect(harness.marked.text == "きょうはID")
        harness.press(.enter)
        #expect(harness.committed == "きょうはID")
    }

    @Test("R-06: 設定で控えめにしなければ，エディタでもふつうのライブ変換にする")
    func restraintCanBeTurnedOff() {
        var settings = DefaultSettings.settings
        settings.restrainsLiveConversionInCode = false
        let converter = FakeConverter(["きょうはID": [("今日はID", nil)]])
        let harness = Harness(converter: converter, settings: settings)
        harness.context = InputContext(profile: .terminal)
        harness.type("kyouhaID")
        harness.settle()
        #expect(harness.marked.text == "今日はID")
    }
}
