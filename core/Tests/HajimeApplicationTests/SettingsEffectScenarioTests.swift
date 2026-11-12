import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

/// 設定の項目を変えると入力の動きが変わること．ほかのシナリオのテストで値を変えて確かめていない項目をここで確かめる．
/// どの項目も，いずれかのテストで値を変えて確かめる(tools/check/check_settings_fields.py)
@MainActor
@Suite("設定の効き")
struct SettingsEffectScenarioTests {
    private func harness(_ converter: FakeConverter = FakeConverter(), lexicon: FakeLexicon = FakeLexicon(), _ change: (inout Settings) -> Void) -> Harness {
        var settings = DefaultSettings.settings
        change(&settings)
        return Harness(converter: converter, lexicon: lexicon, settings: settings)
    }

    // MARK: 打ち間違いの補正(R-02)

    /// 「arigatoou」と打つと，母音の重なりを 1 回にした「arigatou」でだけもっともらしい読みになる変換器
    private func repeatedKeyConverter() -> FakeConverter {
        let converter = FakeConverter()
        converter.corrections["arigatoou"] = [ReadingCorrection(keys: "arigatoou", reading: "アリガトオウ", score: -40, cost: 0)]
        converter.corrections["arigatou"] = [ReadingCorrection(keys: "arigatou", reading: "アリガトウ", score: -1, cost: 0)]
        return converter
    }

    @Test("R-02: 同じキーを続けて打った誤りを直す．設定で切れば直さない")
    func repeatedKeys() {
        let on = harness(repeatedKeyConverter()) { _ in }
        on.type("arigatoou")
        on.settle()
        #expect(on.marked.text == "ありがとう")

        let off = harness(repeatedKeyConverter()) { $0.correction.repeatedKeys = false }
        off.type("arigatoou")
        off.settle()
        #expect(off.marked.text == "ありがとおう")
    }

    /// 「you」を「yoi」に直す差が，標準では示すだけ，積極的なら直す大きさになる変換器(SettingsRuleTests の sensitivity と同じ点数)
    private func borderlineConverter() -> FakeConverter {
        let converter = FakeConverter()
        converter.corrections["youdesu"] = [
            ReadingCorrection(keys: "yoidesu", reading: "ヨイデス", score: 0.5, cost: 2.5),
            ReadingCorrection(keys: "youdesu", reading: "ヨウデス", score: -9, cost: 0),
        ]
        return converter
    }

    @Test("R-02: 修正の基準で，直すか「もしかして」と示すだけかが変わる", arguments: [
        (CorrectionSensitivity.aggressive, "よいです", false),
        (CorrectionSensitivity.standard, "ようです", true),
        (CorrectionSensitivity.cautious, "ようです", false),
    ])
    func correctionSensitivity(sensitivity: CorrectionSensitivity, marked: String, suggests: Bool) {
        let harness = harness(borderlineConverter()) { $0.correctionSensitivity = sensitivity }
        harness.type("youdesu")
        harness.settle()
        #expect(harness.marked.text == marked)
        #expect((harness.note?.contains("よいです") == true) == suggests)
    }

    @Test("R-02: 「もしかして」を表示しない設定なら，直すほど確かでない読みを示さない")
    func showsSuggestions() {
        let shown = harness(borderlineConverter()) { _ in }
        shown.type("youdesu")
        shown.settle()
        #expect(shown.note?.contains("よいです") == true)

        let hidden = harness(borderlineConverter()) { $0.showsSuggestions = false }
        hidden.type("youdesu")
        hidden.settle()
        #expect(hidden.marked.text == "ようです")
        #expect(hidden.note == nil)
    }

    @Test("R-02: 手の置き場所が横にずれたまま打った並びは，設定でオンのときだけ直す")
    func handShiftCorrection() {
        func converter() -> FakeConverter {
            let converter = FakeConverter()
            // 打ったままの読みは，かなにならない英字を残した「sとhsyぴ」
            converter.corrections["stohsypi"] = [ReadingCorrection(keys: "stohsypi", reading: KanaWidth.katakana(from: "sとhsyぴ"), score: -40, cost: 0)]
            converter.corrections["arigatou"] = [ReadingCorrection(keys: "arigatou", reading: "アリガトウ", score: -1, cost: 0)]
            return converter
        }
        let off = harness(converter()) { _ in }
        off.type("stohsypi")
        off.settle()
        #expect(off.marked.text != "ありがとう")

        let on = harness(converter()) { $0.handShiftCorrection = true }
        on.type("stohsypi")
        on.settle()
        #expect(on.marked.text == "ありがとう")
    }

    // MARK: 注釈

    @Test("誤用の注釈は，設定でオンのときだけ添える")
    func misuseNotes() {
        let converter = FakeConverter(["おめいばんかい": [("汚名挽回", nil)]])
        let off = harness(converter) { _ in }
        off.type("omeibannkai")
        off.press(.space)
        #expect(off.lattice?.columns.first?.usageNote == nil)

        let on = harness(converter) { $0.misuseNotes = true }
        on.type("omeibannkai")
        on.press(.space)
        #expect(on.lattice?.columns.first?.usageNote == UsageGuide.misuseNote(for: "汚名挽回"))
    }

    @Test("校正支援の注釈(重言など)は既定で添え，設定で切れる")
    func proofreading() {
        let converter = FakeConverter(["いちばんさいしょ": [("一番最初", nil)]])
        let on = harness(converter) { _ in }
        on.type("itibannsaisyo")
        on.press(.space)
        #expect(on.lattice?.columns.first?.usageNote == Proofreading.note(for: "一番最初"))

        let off = harness(converter) { $0.proofreading = false }
        off.type("itibannsaisyo")
        off.press(.space)
        #expect(off.lattice?.columns.first?.usageNote == nil)
    }

    // MARK: 文字

    @Test("R-04: ¥ キーで入れる文字は設定に従う．プログラミング用のアプリでだけ \\ にもできる", arguments: [
        (YenKeyPolicy.alwaysBackslash, AppProfile.standard, "\\"),
        (YenKeyPolicy.alwaysYen, AppProfile.standard, "¥"),
        (YenKeyPolicy.alwaysYen, AppProfile.programming, "¥"),
        (YenKeyPolicy.backslashInProgramming, AppProfile.standard, "¥"),
        (YenKeyPolicy.backslashInProgramming, AppProfile.programming, "\\"),
    ])
    func yenKey(policy: YenKeyPolicy, profile: AppProfile, expected: String) {
        let harness = harness { $0.yenKey = policy }
        harness.context = InputContext(profile: profile)
        harness.press(.yen)
        #expect(harness.committed == expected)
    }

    // MARK: 候補

    @Test("R-20: 発音どおりに綴った英単語は，設定でオンのときだけ一覧に出す")
    func phoneticSpelling() {
        let lexicon = FakeLexicon(words: ["photo"])
        func list(_ change: (inout Settings) -> Void) -> [String] {
            var settings = DefaultSettings.settings
            change(&settings)
            let converter = SupplementedConverter(FakeConverter(["ふぉと": [("ふぉと", nil)]]), settings: FakeSettings(settings), calendar: FakeCalendar(),
                                                  lexicon: lexicon)
            return converter.listCandidates(for: "ふぉと").map(\.text)
        }
        #expect(!list { _ in }.contains("photo"))
        #expect(list { $0.phoneticSpelling = true }.contains("photo"))
    }
}
