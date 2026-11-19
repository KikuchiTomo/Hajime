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
        for display in [PredictionDisplay.off, .whenLiveConversionOff] {
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

/// 予測に表示しない語句(キーで足し，設定の画面で消す)
@Suite("予測に表示しない語句")
@MainActor
struct HiddenPredictionScenarioTests {
    private static func settings(_ change: (inout Settings) -> Void = { _ in }) -> Settings {
        var settings = DefaultSettings.settings
        settings.predictionDisplay = .always
        change(&settings)
        return settings
    }

    private static func converter() -> FakeConverter {
        let converter = FakeConverter(["えぴ": [("エピ", nil)]])
        converter.predictionTexts["えぴ"] = ["エピ", "エピソード", "エピローグ"]
        return converter
    }

    @Test("入力中の ⌃⌫ で予測の窓の語句を設定の「予測に表示しない語句」に入れ，次の予測に替えて案内を出す")
    func hidesShownPrediction() {
        let harness = Harness(converter: Self.converter(), settings: Self.settings())
        harness.type("epi")
        #expect(harness.prediction?.completion == "ソード")
        harness.press(.backspace, .control)
        #expect(harness.settings.current.hiddenPredictions == ["エピソード"])
        #expect(harness.prediction?.completion == "ローグ")
        #expect(harness.note?.contains("エピソード") == true)
        // 読みは消さない
        #expect(harness.marked.text == "えぴ")
    }

    @Test("「予測に表示しない語句」にある語句は予測に出さず，一覧から消すとまた出す")
    func respectsList() {
        let hidden = Harness(converter: Self.converter(), settings: Self.settings { $0.hiddenPredictions = ["エピソード"] })
        hidden.type("epi")
        #expect(hidden.prediction?.completion == "ローグ")
        let restored = Harness(converter: Self.converter(), settings: Self.settings())
        restored.type("epi")
        #expect(restored.prediction?.completion == "ソード")
    }

    @Test("予測の窓を出していないときは何もしない．キーはキー設定の表で変えられる")
    func keyAndNoPrediction() {
        let none = Harness(converter: FakeConverter(["えぴ": [("エピ", nil)]]), settings: Self.settings())
        none.type("epi")
        none.press(.backspace, .control)
        #expect(none.settings.current.hiddenPredictions.isEmpty)
        #expect(none.marked.text == "えぴ")
        let custom = Harness(converter: Self.converter(), settings: Self.settings {
            $0.keymap.entries.removeAll { $0.command == .hidePrediction }
            $0.keymap.entries.append(KeymapEntry(.composing, KeyStroke(.character("x"), control: true), .hidePrediction))
        })
        custom.type("epi")
        custom.press(.character("x"), .control)
        #expect(custom.settings.current.hiddenPredictions == ["エピソード"])
    }
}

/// 予測を確定した直後に，補う前の読みに戻す(キー設定の表の「予測の確定を取り消し」)
@Suite("予測の確定の取り消し")
@MainActor
struct PredictionUndoScenarioTests {
    private static func settings(_ change: (inout Settings) -> Void = { _ in }) -> Settings {
        var settings = DefaultSettings.settings
        settings.predictionDisplay = .always
        change(&settings)
        return settings
    }

    private static func converter() -> FakeConverter {
        let converter = FakeConverter(["えぴ": [("エピ", nil)]])
        converter.predictionTexts["えぴ"] = ["エピ", "エピソード", "エピローグ"]
        return converter
    }

    /// 「epi」を打って Tab で予測(エピソード)を確定し，入力先の入力位置の前に確定した文字があるようにする
    private static func accepted(_ settings: Settings = settings(), converter: FakeConverter = converter()) -> Harness {
        let harness = Harness(converter: converter, settings: settings)
        harness.context.precedingText = "今日の"
        harness.type("epi")
        harness.press(.tab)
        harness.context.precedingText = "今日の" + harness.committed
        return harness
    }

    @Test("予測を確定した直後の Backspace で，確定した語句を消して補う前の読みに戻し，学習も取り消す．同じ読みのあいだは取り消した予測を出さない")
    func undoesRightAfter() {
        let converter = Self.converter()
        converter.predictionsAreLearnable = true
        let harness = Self.accepted(converter: converter)
        #expect(harness.committed == "エピソード")
        harness.press(.backspace)
        #expect(harness.lastResult.handled)
        #expect(harness.committed.isEmpty)
        #expect(harness.marked.text == "えぴ")
        #expect(converter.forgotten.map(\.text) == ["エピソード"])
        #expect(converter.leftContext == "今日の")
        harness.followUp()
        #expect(harness.prediction?.completion == "ローグ")
        // 読みは打ち続けられる
        harness.press(.backspace)
        #expect(harness.marked.text == "え")
    }

    @Test("直後でなければ取り消さず，Backspace はアプリに渡す(別のキーを押したあと・入力位置の前が確定した語句でないとき・置き換えられない入力先)")
    func passesThroughOtherwise() {
        let later = Self.accepted()
        later.press(.left)
        later.press(.backspace)
        #expect(!later.lastResult.handled)
        let moved = Self.accepted()
        moved.context.precedingText = "今日のエピソードを"
        moved.press(.backspace)
        #expect(!moved.lastResult.handled)
        #expect(moved.marked.text.isEmpty)
        let old = Self.accepted()
        old.context.canReplacePrecedingText = false
        old.press(.backspace)
        #expect(!old.lastResult.handled)
        // 予測でなく Enter で確定したあとは取り消さない
        let typed = Harness(converter: Self.converter(), settings: Self.settings())
        typed.type("epi")
        typed.press(.enter)
        typed.context.precedingText = typed.committed
        typed.press(.backspace)
        #expect(!typed.lastResult.handled)
    }

    @Test("取り消すキーはキー設定の表で変えられ，割り当てを消すと取り消さない")
    func customKey() {
        let custom = Self.accepted(Self.settings {
            $0.keymap.entries.removeAll { $0.command == .undoPrediction }
            $0.keymap.entries.append(KeymapEntry(.idle, KeyStroke(.character("z"), control: true), .undoPrediction))
        })
        custom.press(.character("z"), .control)
        #expect(custom.committed.isEmpty)
        #expect(custom.marked.text == "えぴ")
        let none = Self.accepted(Self.settings { $0.keymap.entries.removeAll { $0.command == .undoPrediction } })
        none.press(.backspace)
        #expect(!none.lastResult.handled)
        #expect(none.committed == "エピソード")
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

/// 打鍵が設定の時間止まってから予測を出す設定(入力中の予測「入力中のタイミングで制御」)．待つのは入力メソッドのタイマーで，
/// 止まったときに revealPrediction を呼ぶ
@Suite("予測を出すタイミング")
@MainActor
struct PredictionTimingScenarioTests {
    private static func settings(_ change: (inout Settings) -> Void = { _ in }) -> Settings {
        var settings = DefaultSettings.settings
        settings.predictionDisplay = .afterPause
        change(&settings)
        return settings
    }

    private static func converter() -> FakeConverter {
        let converter = FakeConverter(["えぴ": [("エピ", nil), ("えぴ", nil)], "えぴそ": [("エピソ", nil)]])
        converter.predictionTexts["えぴ"] = ["エピ", "エピソード", "エピローグ"]
        converter.predictionTexts["えぴそ"] = ["エピソード"]
        return converter
    }

    private static func reveal(_ harness: Harness) -> [ClientAction] {
        harness.session.revealPrediction(context: harness.context)
    }

    private static func shown(_ actions: [ClientAction]) -> Prediction?? {
        actions.compactMap { action -> Prediction?? in
            if case .showPrediction(let prediction) = action { .some(prediction) } else { nil }
        }.last
    }

    @Test("打っているあいだは予測を出さず(求めもせず)，打鍵が止まったら出す．ライブ変換がオンでもオフでも同じ", arguments: [true, false])
    func showsAfterPause(live: Bool) {
        let converter = Self.converter()
        let harness = Harness(converter: converter, settings: Self.settings { $0.liveConversion = live })
        harness.type("epi")
        #expect(harness.prediction == nil)
        #expect(harness.session.awaitsPrediction)
        #expect(Self.shown(Self.reveal(harness)) == .some(Prediction(typed: "エピ", completion: "ソード", key: "Tab")))
        // 出したあとは待たない(同じ打鍵の止まりで 2 回出さない)
        #expect(!harness.session.awaitsPrediction)
        #expect(Self.reveal(harness).isEmpty)
    }

    @Test("次のキーで予測を消し，また止まるのを待つ")
    func hidesOnNextKey() {
        let harness = Harness(converter: Self.converter(), settings: Self.settings())
        harness.type("epi")
        _ = Self.reveal(harness)
        harness.press(.character("s"))
        #expect(harness.lastResult.actions.contains(.showPrediction(nil)))
        #expect(harness.prediction == nil)
        harness.press(.character("o"))
        #expect(harness.prediction == nil)
        #expect(harness.session.awaitsPrediction)
        #expect(Self.shown(Self.reveal(harness)) == .some(Prediction(typed: "エピソ", completion: "ード", key: "Tab")))
    }

    @Test("出した予測は Tab で選べる")
    func acceptsRevealed() {
        let harness = Harness(converter: Self.converter(), settings: Self.settings())
        harness.type("epi")
        _ = Self.reveal(harness)
        harness.press(.tab)
        #expect(harness.committed == "エピソード")
    }

    @Test("確定した・変換を始めた・読みが短い・ほかの設定のときは待たず，遅れて届いた知らせでは何も出さない")
    func ignoresStaleTimer() {
        let committed = Harness(converter: Self.converter(), settings: Self.settings())
        committed.type("epi")
        committed.press(.enter)
        #expect(!committed.session.awaitsPrediction)
        #expect(Self.reveal(committed).isEmpty)

        let converting = Harness(converter: Self.converter(), settings: Self.settings())
        converting.type("epi")
        converting.press(.space)
        #expect(!converting.session.awaitsPrediction)
        #expect(Self.reveal(converting).isEmpty)

        let left = Harness(converter: Self.converter(), settings: Self.settings())
        left.type("epi")
        _ = left.session.deactivate()
        #expect(Self.reveal(left).isEmpty)

        let short = Harness(converter: Self.converter(), settings: Self.settings())
        short.type("e")
        #expect(!short.session.awaitsPrediction)

        for display in [PredictionDisplay.off, .whenLiveConversionOff, .always] {
            let other = Harness(converter: Self.converter(), settings: Self.settings { $0.predictionDisplay = display })
            other.type("epi")
            #expect(!other.session.awaitsPrediction)
            #expect(Self.reveal(other).isEmpty)
        }
    }

    @Test("予測を「予測に表示しない語句」に入れたら，次の予測は待たずに出す")
    func hidingShowsNext() {
        let harness = Harness(converter: Self.converter(), settings: Self.settings())
        harness.type("epi")
        _ = Self.reveal(harness)
        harness.press(.backspace, .control)
        #expect(harness.settings.current.hiddenPredictions == ["エピソード"])
        #expect(harness.lastResult.actions.contains(.showPrediction(Prediction(typed: "エピ", completion: "ローグ", key: "Tab"))))
    }

    @Test("待ち時間は 0.1 秒から 2 秒までに収め，既定は入力を継続する設定がオン")
    func clampsDelay() throws {
        #expect(DefaultSettings.predictionDelayRange == 0.1...2.0)
        var settings = DefaultSettings.settings
        settings.predictionDelay = 9
        settings.clampToValidRanges()
        #expect(settings.predictionDelay == 2.0)
        settings.predictionDelay = 0
        settings.clampToValidRanges()
        #expect(settings.predictionDelay == 0.1)
        settings.predictionDelay = .nan
        settings.clampToValidRanges()
        #expect(settings.predictionDelay == DefaultSettings.predictionDelay)
        #expect(DefaultSettings.settings.predictionKeepsComposing)
        let read = try JSONDecoder().decode(Settings.self, from: Data(#"{"predictionDisplay": "afterPause", "predictionDelay": 1.2, "predictionKeepsComposing": false}"#.utf8))
        #expect(read.predictionDisplay == .afterPause)
        #expect(read.predictionDelay == 1.2)
        #expect(!read.predictionKeepsComposing)
        #expect(try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(read)) == read)
    }
}

/// 予測を選んだあとも入力を続ける設定(既定でオン)．Tab で予測の語句を確定せず，読みを予測の読みに補う
@Suite("予測を選んだあとの入力の継続")
@MainActor
struct PredictionCompletionScenarioTests {
    private static func settings(_ change: (inout Settings) -> Void = { _ in }) -> Settings {
        var settings = DefaultSettings.settings
        settings.predictionDisplay = .always
        change(&settings)
        return settings
    }

    private static func converter() -> FakeConverter {
        let converter = FakeConverter([
            "えぴ": [("エピ", nil), ("えぴ", nil)],
            "えぴそーど": [("エピソード", nil), ("挿話", nil)],
            "えぴそーどを": [("エピソードを", nil)],
        ])
        converter.predictionTexts["えぴ"] = ["エピ", "エピソード", "エピローグ"]
        converter.predictionReadings = ["エピソード": "えぴそーど", "エピローグ": "えぴろーぐ"]
        converter.predictionsAreLearnable = true
        return converter
    }

    @Test("Tab で予測を選ぶと確定せず，予測の語句を未確定のまま見せ，Enter でその語句を確定して学ぶ", arguments: [true, false])
    func keepsComposing(live: Bool) {
        let converter = Self.converter()
        let harness = Harness(converter: converter, settings: Self.settings { $0.liveConversion = live })
        harness.type("epi")
        harness.press(.tab)
        #expect(harness.committed.isEmpty)
        #expect(harness.marked.text == "エピソード")
        #expect(harness.session.isComposing)
        #expect(converter.committed.isEmpty)
        harness.press(.enter)
        #expect(harness.committed == "エピソード")
        #expect(converter.committed.map(\.text) == ["エピソード"])
        #expect(harness.marked.isEmpty)
    }

    @Test("選んだあと，Space で補った読みを変換でき，候補を選び直せる")
    func convertsAfterCompletion() {
        let harness = Harness(converter: Self.converter(), settings: Self.settings { $0.candidatePresentation = .list })
        harness.type("epi")
        harness.press(.tab)
        harness.press(.space)
        #expect(harness.panel?.entries.map(\.text).contains("挿話") == true)
        harness.press(.space)
        harness.press(.enter)
        #expect(harness.committed == "挿話")
    }

    @Test("選んだあと，続けて打つと補った読みに足す")
    func typesAfterCompletion() {
        let harness = Harness(converter: Self.converter(), settings: Self.settings())
        harness.type("epi")
        harness.press(.tab)
        harness.type("wo")
        harness.settle()
        #expect(harness.committed.isEmpty)
        #expect(harness.marked.text == "エピソードを")
        harness.press(.enter)
        #expect(harness.committed == "エピソードを")
    }

    @Test("選んだ直後の Backspace で補う前の読みに戻し，同じ読みのあいだは戻した予測を出さない．直後でなければ 1 文字消す")
    func undoesCompletion() {
        let harness = Harness(converter: Self.converter(), settings: Self.settings { $0.liveConversion = false })
        harness.type("epi")
        harness.press(.tab)
        harness.press(.backspace)
        #expect(harness.marked.text == "えぴ")
        #expect(harness.committed.isEmpty)
        #expect(harness.prediction?.completion == "ローグ")

        let later = Harness(converter: Self.converter(), settings: Self.settings { $0.liveConversion = false })
        later.type("epi")
        later.press(.tab)
        later.press(.left, .shift)
        later.press(.backspace)
        #expect(later.marked.text != "えぴ")
    }

    @Test("ライブ変換で文が見えているときは，最後の文節の予測の読みを補い，前の文節とつないだ語句で見せる")
    func completesLastClause() {
        let converter = FakeConverter(["きょうはあめ": [("今日は雨", nil)], "あめ": [("雨", nil), ("飴", nil)], "きょうはあまぐ": [("今日は雨具", nil)]])
        converter.candidateWords["今日は雨"] = [
            Candidate.Word(text: "今日", readingCount: 3, startsWithNoun: true),
            Candidate.Word(text: "は", readingCount: 1, startsWithParticle: true),
            Candidate.Word(text: "雨", readingCount: 2, startsWithNoun: true),
        ]
        converter.predictionTexts["あめ"] = ["雨", "雨雲"]
        converter.predictionReadings = ["雨雲": "あめぐも"]
        let harness = Harness(converter: converter, settings: Self.settings())
        harness.type("kyouhaame")
        harness.press(.tab)
        #expect(harness.committed.isEmpty)
        #expect(harness.marked.text == "今日は雨雲")
        harness.press(.enter)
        #expect(harness.committed == "今日は雨雲")
    }

    @Test("設定をオフにすると，今までどおり Tab で予測の語句を確定する．予測の読みが分からないとき・打った読みの続きでないときも確定する")
    func commitsWhenOff() {
        let off = Harness(converter: Self.converter(), settings: Self.settings { $0.predictionKeepsComposing = false })
        off.type("epi")
        off.press(.tab)
        #expect(off.committed == "エピソード")
        #expect(off.marked.isEmpty)

        let unknown = Self.converter()
        unknown.predictionReadings = [:]
        let withoutReading = Harness(converter: unknown, settings: Self.settings())
        withoutReading.type("epi")
        withoutReading.press(.tab)
        #expect(withoutReading.committed == "エピソード")

        let other = Self.converter()
        other.predictionReadings = ["エピソード": "そうわ"]
        let unrelated = Harness(converter: other, settings: Self.settings())
        unrelated.type("epi")
        unrelated.press(.tab)
        #expect(unrelated.committed == "エピソード")
    }

    @Test("オフにして確定した予測は，今までどおり直後の Backspace で取り消せる")
    func undoStillWorksWhenOff() {
        let converter = Self.converter()
        let harness = Harness(converter: converter, settings: Self.settings { $0.predictionKeepsComposing = false })
        harness.type("epi")
        harness.press(.tab)
        harness.context.precedingText = harness.committed
        harness.press(.backspace)
        #expect(harness.committed.isEmpty)
        #expect(harness.marked.text == "えぴ")
        #expect(converter.forgotten.map(\.text) == ["エピソード"])
    }

    @Test("選んだ予測も「予測に表示しない語句」に入れられ，入れた語句は次から出さない")
    func hidingStillWorks() {
        let harness = Harness(converter: Self.converter(), settings: Self.settings())
        harness.type("epi")
        harness.press(.backspace, .control)
        #expect(harness.settings.current.hiddenPredictions == ["エピソード"])
        harness.press(.tab)
        #expect(harness.marked.text == "エピローグ")
    }
}

/// 入力中の候補の窓と予測の窓を，確定・入力先の切り替え・Esc・英数への切り替えのあとに残さない．
/// あとから求めて出し直す処理(followUps)やタイマー(settle・review・訂正・予測)が遅れて届いても，古い内容で窓を出し直さない
@Suite("入力中の窓を残さない")
@MainActor
struct SuggestionWindowClosingScenarioTests {
    private static func settings(_ change: (inout Settings) -> Void = { _ in }) -> Settings {
        var settings = DefaultSettings.settings
        settings.suggestionDisplay = .always
        settings.predictionDisplay = .always
        change(&settings)
        return settings
    }

    private static func converter() -> FakeConverter {
        let converter = FakeConverter(["えぴ": [("エピ", nil), ("えぴ", nil), ("絵ピ", nil)]])
        converter.predictionTexts["えぴ"] = ["エピ", "エピソード"]
        return converter
    }

    /// 窓を出す操作(候補・分岐図・案内・予測)
    private static func shows(_ actions: [ClientAction]) -> Bool {
        actions.contains { action in
            switch action {
            case .showCandidates, .showLattice, .showNote: true
            case .showPrediction(let prediction): prediction != nil
            default: false
            }
        }
    }

    /// 入力を終える操作．どれも候補の窓と予測の窓を消す
    enum Ending: String, CaseIterable, Sendable {
        case 入力先を離れる, OSのメニューで英数にする, 手書きの窓で選んだ文字を入れる, Enter, Esc, 英数キー, アプリのショートカット

        @MainActor
        func end(_ harness: Harness) -> [ClientAction] {
            switch self {
            case .入力先を離れる: harness.session.deactivate()
            case .OSのメニューで英数にする: harness.session.setMode(.direct)
            case .手書きの窓で選んだ文字を入れる: harness.session.insert("字")
            case .Enter: harness.session.handle(KeyEvent(.enter), context: harness.context).actions
            case .Esc: harness.session.handle(KeyEvent(.escape), context: harness.context).actions
            case .英数キー: harness.session.handle(KeyEvent(.eisu), context: harness.context).actions
            case .アプリのショートカット: harness.session.handle(KeyEvent(.character("s"), modifiers: .command), context: harness.context).actions
            }
        }
    }

    @Test("入力を終えると候補の窓と予測の窓を消し，遅れて届いた処理では出し直さない", arguments: Ending.allCases)
    func closesAndStaysClosed(ending: Ending) {
        let harness = Harness(converter: Self.converter(), settings: Self.settings())
        harness.runsFollowUps = false
        harness.type("epi")
        #expect(harness.panel != nil, "\(ending.rawValue)")
        // キーのあとの処理(予測を求めて出し直す)を，動かす前に入力を終える
        let pending = harness.session.followUps(context: harness.context)
        #expect(!pending.isEmpty)
        let actions = ending.end(harness)
        #expect(actions.contains(.hideCandidates), "\(ending.rawValue)")
        #expect(!Self.shows(actions), "\(ending.rawValue)")
        #expect(!harness.session.isComposing)
        // 遅れて届いた処理
        for step in pending { #expect(!Self.shows(step()), "\(ending.rawValue)") }
        #expect(!Self.shows(harness.session.settle(context: harness.context)))
        #expect(!Self.shows(harness.session.review(context: harness.context)))
        #expect(!Self.shows(harness.session.revealPrediction(context: harness.context)))
        #expect(!Self.shows(harness.session.applyLateCorrections([:], context: harness.context)))
        #expect(harness.session.followUps(context: harness.context).isEmpty)
    }

    @Test("予測を出していたら，入力を終えるときに予測の窓も消す", arguments: Ending.allCases)
    func closesPrediction(ending: Ending) {
        let harness = Harness(converter: Self.converter(), settings: Self.settings())
        harness.type("epi")
        #expect(harness.prediction != nil)
        #expect(ending.end(harness).contains(.showPrediction(nil)), "\(ending.rawValue)")
    }

    @Test("同じ読みを打ち直しても，前の入力のあとの処理では窓を出し直さない(次のキーで前の処理を捨てなくても)")
    func staleFollowUpAfterRetyping() {
        let harness = Harness(converter: Self.converter(), settings: Self.settings())
        harness.runsFollowUps = false
        harness.type("epi")
        let pending = harness.session.followUps(context: harness.context)
        _ = harness.session.deactivate()
        for step in pending { #expect(step().isEmpty) }
    }
}
