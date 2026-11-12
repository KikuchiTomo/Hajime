import Foundation
import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

/// 打っているあいだの，続く語句の予測の窓．変換の候補とは体験が違うので，候補の窓に混ぜず別の窓に出す
@Suite("予測の窓")
@MainActor
struct PredictionWindowScenarioTests {
    private static func settings(_ change: (inout Settings) -> Void = { _ in }) -> Settings {
        var settings = DefaultSettings.settings
        settings.predictionDisplay = .always
        change(&settings)
        return settings
    }

    private static func converter() -> FakeConverter {
        let converter = FakeConverter(["えぴ": [("エピ", nil), ("えぴ", nil)], "えぴそーど": [("エピソード", nil)]])
        converter.predictionTexts["えぴ"] = ["エピ", "エピソード", "エピローグ"]
        return converter
    }

    @Test("入力中の予測を出す設定では，変換の候補と同じ語句を除いた最初の予測を，打った部分と補う部分に分けて出す")
    func showsPrediction() {
        let harness = Harness(converter: Self.converter(), settings: Self.settings())
        harness.type("epi")
        #expect(harness.prediction == Prediction(typed: "エピ", completion: "ソード", key: "Tab"))
        // 変換の候補の窓は出さない設定(既定ではライブ変換がオンのとき出さない)
        #expect(harness.panel == nil)
    }

    @Test("Tab で予測を確定し，確定したら予測の窓を消す")
    func tabCommitsPrediction() {
        let harness = Harness(converter: Self.converter(), settings: Self.settings())
        harness.type("epi")
        harness.press(.tab)
        #expect(harness.committed == "エピソード")
        #expect(harness.prediction == nil)
        #expect(harness.marked.isEmpty)
    }

    @Test("ライブ変換で文が見えているときは，今打っている最後の文節の予測を出し，Tab で前の文節とつないで確定する")
    func predictsLastClause() {
        let converter = FakeConverter(["きょうはあめ": [("今日は雨", nil)], "あめ": [("雨", nil), ("飴", nil)]])
        converter.candidateWords["今日は雨"] = [
            Candidate.Word(text: "今日", readingCount: 3, startsWithNoun: true),
            Candidate.Word(text: "は", readingCount: 1, startsWithParticle: true),
            Candidate.Word(text: "雨", readingCount: 2, startsWithNoun: true),
        ]
        converter.predictionTexts["あめ"] = ["雨", "雨具"]
        let harness = Harness(converter: converter, settings: Self.settings())
        harness.type("kyouhaame")
        #expect(harness.prediction == Prediction(typed: "雨", completion: "具", key: "Tab"))
        harness.press(.tab)
        #expect(harness.committed == "今日は雨具")
    }

    @Test("Space で分岐図を出したら予測の窓を消し，分岐図にも予測を入れない")
    func hidesOnConversion() {
        let harness = Harness(converter: Self.converter(), settings: Self.settings())
        harness.type("epi")
        #expect(harness.prediction != nil)
        harness.press(.space)
        #expect(harness.prediction == nil)
        #expect(harness.lattice?.columns.first?.alternatives.contains("エピソード") == false)
    }

    @Test("Esc で打った文字を消したら予測の窓も消す")
    func hidesOnCancel() {
        let harness = Harness(converter: Self.converter(), settings: Self.settings())
        harness.type("epi")
        harness.press(.escape)
        harness.press(.escape)
        #expect(harness.marked.isEmpty)
        #expect(harness.prediction == nil)
    }

    @Test("入力中の予測を出さない設定，ライブ変換がオンで「ライブ変換がオフのときだけ」の設定では予測を出さず，Tab は予測を確定しない")
    func respectsSetting() {
        for display in [SuggestionDisplay.off, .whenLiveConversionOff] {
            let harness = Harness(converter: Self.converter(), settings: Self.settings { $0.predictionDisplay = display })
            harness.type("epi")
            #expect(harness.prediction == nil)
            harness.press(.tab)
            #expect(harness.committed.isEmpty)
        }
        let off = Harness(converter: Self.converter(), settings: Self.settings {
            $0.predictionDisplay = .whenLiveConversionOff
            $0.liveConversion = false
        })
        off.type("epi")
        #expect(off.prediction?.completion == "ソード")
    }

    @Test("キーの案内を出さない設定では予測の窓にキーを添えないが，Tab では確定できる")
    func withoutKeyHints() {
        let harness = Harness(converter: Self.converter(), settings: Self.settings { $0.showsKeyHints = false })
        harness.type("epi")
        #expect(harness.prediction == Prediction(typed: "エピ", completion: "ソード", key: nil))
        harness.press(.tab)
        #expect(harness.committed == "エピソード")
    }

    @Test("予測を確定するキーはキー設定の表の「もしかして・予測を確定」で変えられ，割り当てが無ければ予測の窓を出さない")
    func customKey() {
        let custom = Self.settings {
            $0.keymap.entries.removeAll { $0.command == .acceptSuggestion }
            $0.keymap.entries.append(KeymapEntry(.composing, KeyStroke(.character("j"), control: true), .acceptSuggestion))
        }
        let harness = Harness(converter: Self.converter(), settings: custom)
        harness.type("epi")
        #expect(harness.prediction?.key == "⌃J")
        harness.press(.character("j"), .control)
        #expect(harness.committed == "エピソード")
        let none = Harness(converter: Self.converter(), settings: Self.settings { $0.keymap.entries.removeAll { $0.command == .acceptSuggestion } })
        none.type("epi")
        #expect(none.prediction == nil)
    }

    @Test("ローマ字を打ちかけているあいだは前の予測を出しておき，かなになったら求め直す")
    func keepsWhilePending() {
        let converter = Self.converter()
        converter.predictionTexts["えぴそ"] = ["エピソード"]
        converter.table["えぴそ"] = [("エピソ", nil)]
        let harness = Harness(converter: converter, settings: Self.settings())
        harness.type("epi")
        let shown = harness.prediction
        harness.press(.character("s"))
        #expect(harness.prediction == shown)
        harness.press(.character("o"))
        #expect(harness.prediction == Prediction(typed: "エピソ", completion: "ード", key: "Tab"))
    }
}

/// 予測の窓に出す予測の選び方(履歴にある語句を先にするか，打ち間違いを直した読みからも予測するか)
@Suite("予測の出どころ")
@MainActor
struct PredictionSourceScenarioTests {
    private static func settings(_ change: (inout Settings) -> Void = { _ in }) -> Settings {
        var settings = DefaultSettings.settings
        settings.predictionDisplay = .always
        change(&settings)
        return settings
    }

    @Test("確定した履歴にある予測を先に出す設定(既定)では，エンジンの並びより先に履歴の語句を出す．オフならエンジンの並びのまま")
    func prefersHistory() {
        let converter = FakeConverter(["えぴ": [("エピ", nil)]])
        converter.predictionTexts["えぴ"] = ["エピ", "エピソード", "エピローグ"]
        converter.learnedPredictions = ["エピローグ"]
        let harness = Harness(converter: converter, settings: Self.settings())
        harness.type("epi")
        #expect(harness.prediction?.completion == "ローグ")
        let off = Harness(converter: converter, settings: Self.settings { $0.predictionPrefersHistory = false })
        off.type("epi")
        #expect(off.prediction?.completion == "ソード")
    }

    /// 「arigatoi」を打って止まると「ありがとう」と「もしかして」で示す
    private static func typoConverter() -> FakeConverter {
        let converter = FakeConverter(["ありがとう": [("ありがとう", nil)]])
        converter.corrections["arigatoi"] = [
            ReadingCorrection(keys: "arigatou", reading: "アリガトウ", score: 0.5, cost: 2.5),
            ReadingCorrection(keys: "arigatoi", reading: "アリガトイ", score: -9, cost: 0),
        ]
        converter.predictionTexts["ありがとう"] = ["ありがとうございます"]
        return converter
    }

    @Test("打ち間違いを直した読みからも予測する設定(既定)では，「もしかして」と示した読みから予測してキーを添えずに出し，Tab で読みを直すとキーを添え，もう一度 Tab で確定する")
    func predictsFromSuggestedReading() {
        let harness = Harness(converter: Self.typoConverter(), settings: Self.settings())
        harness.type("arigatoi")
        #expect(harness.prediction == nil)
        harness.settle()
        // 示した読みの予測は，打鍵の合間に求める
        harness.followUp()
        #expect(harness.note?.contains("ありがとう") == true)
        #expect(harness.prediction == Prediction(typed: "ありがとう", completion: "ございます", key: nil))
        harness.press(.tab)
        #expect(harness.marked.text == "ありがとう")
        #expect(harness.committed.isEmpty)
        #expect(harness.prediction == Prediction(typed: "ありがとう", completion: "ございます", key: "Tab"))
        harness.press(.tab)
        #expect(harness.committed == "ありがとうございます")
    }

    @Test("打ち間違いを直した読みから予測しない設定では，示しているあいだも直したあとも予測を出さない")
    func skipsCorrectedReading() {
        let harness = Harness(converter: Self.typoConverter(), settings: Self.settings { $0.predictionFromCorrection = false })
        harness.type("arigatoi")
        harness.settle()
        harness.followUp()
        #expect(harness.prediction == nil)
        harness.press(.tab)
        #expect(harness.marked.text == "ありがとう")
        #expect(harness.prediction == nil)
    }
}

/// 入力中の候補(変換の候補の窓)を出す件数
@Suite("入力中の候補の件数")
@MainActor
struct SuggestionSkipCountScenarioTests {
    @Test("候補が設定の件数以下なら入力中の候補の窓を出さず，↓ は変換を始める．既定の 0 なら候補があれば出す")
    func skipsFewCandidates() {
        let converter = FakeConverter(["あぴ": [("あぴ", nil), ("アピ", nil)]])
        var settings = DefaultSettings.settings
        settings.suggestionDisplay = .always
        let shown = Harness(converter: converter, settings: settings)
        shown.type("api")
        #expect(shown.panel?.entries.count == 2)
        settings.suggestionSkipCount = 2
        let skipped = Harness(converter: converter, settings: settings)
        skipped.type("api")
        #expect(skipped.panel == nil)
        skipped.press(.down)
        #expect(skipped.lattice != nil)
        settings.suggestionSkipCount = 1
        let more = Harness(converter: converter, settings: settings)
        more.type("api")
        #expect(more.panel?.entries.count == 2)
    }

    @Test("件数の設定は範囲(0 から出せる候補の数の 1 つ手前まで)に収める")
    func clampsSkipCount() {
        var settings = DefaultSettings.settings
        settings.suggestionSkipCount = 99
        settings.clampToValidRanges()
        #expect(settings.suggestionSkipCount == DefaultSettings.suggestionSkipCountRange.upperBound)
    }
}

/// 予測の窓の設定を，予測を候補の窓に混ぜていたころの設定のファイルから読む
@Suite("入力中の予測の設定")
struct PredictionSettingTests {
    @Test("入力中の予測の項目が無い設定のファイルは，入力中の候補と同じ設定で読む(それまでは同じ窓に出していたため)")
    func migratesFromSuggestionDisplay() throws {
        let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"suggestionDisplay": "always"}"#.utf8))
        #expect(old.predictionDisplay == .always)
        let new = try JSONDecoder().decode(Settings.self, from: Data(#"{"suggestionDisplay": "always", "predictionDisplay": "off"}"#.utf8))
        #expect(new.predictionDisplay == .off)
        #expect(try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(new)) == new)
        #expect(DefaultSettings.settings.predictionDisplay == .whenLiveConversionOff)
        #expect(DefaultSettings.settings.suggestionSkipCount == 0)
        #expect(DefaultSettings.settings.predictionPrefersHistory)
        #expect(DefaultSettings.settings.predictionFromCorrection)
    }
}
