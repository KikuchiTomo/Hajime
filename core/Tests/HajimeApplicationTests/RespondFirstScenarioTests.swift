import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

/// キーにはすぐ反応して画面を出し，時間のかかる候補はあとから求めて足す(InputSession.followUps)
@Suite("まず反応し，候補はあとから足す")
@MainActor
struct RespondFirstScenarioTests {
    /// 「今日は｜雨」の 2 つの文節になる変換器
    private func converter() -> FakeConverter {
        let converter = FakeConverter(["きょうはあめ": [("今日は雨", nil)], "きょうは": [("今日は", nil), ("京は", nil)], "あめ": [("雨", nil), ("飴", nil)]])
        converter.words["きょうはあめ"] = [
            Candidate.Word(text: "今日", readingCount: 3), Candidate.Word(text: "は", readingCount: 1, startsWithParticle: true, endsWithParticle: true),
            Candidate.Word(text: "雨", readingCount: 2),
        ]
        return converter
    }

    @Test("Space ではすぐ分岐図を出し，選んでいる文節の候補だけを先に求める．ほかの文節の候補と下見はあとから足す")
    func latticeFillsLater() {
        var settings = DefaultSettings.settings
        settings.initialFocus = .start
        let harness = Harness(converter: converter(), settings: settings)
        harness.runsFollowUps = false
        harness.type("kyouhaame")
        harness.press(.space)
        #expect(harness.lattice?.columns.map(\.text) == ["今日は", "雨"])
        #expect(harness.lattice?.columns.first?.alternatives.contains("京は") == true)
        #expect(harness.lattice?.columns.last?.alternatives.isEmpty == true)
        #expect(harness.lattice?.columns.first?.longer == nil)
        harness.followUp()
        #expect(harness.lattice?.columns.map(\.text) == ["今日は", "雨"])
        #expect(harness.lattice?.columns.first?.longer != nil)
        // 足し終えたあと，次の文節の候補はもうある
        harness.press(.right)
        #expect(harness.lattice?.columns.last?.alternatives.contains("飴") == true)
    }

    @Test("候補を求める前の文節に移っても，その文節の候補はすぐ出す．確定すれば同じ文になる")
    func pendingSegmentFillsWhenFocused() {
        var settings = DefaultSettings.settings
        settings.initialFocus = .start
        let harness = Harness(converter: converter(), settings: settings)
        harness.runsFollowUps = false
        harness.type("kyouhaame")
        harness.press(.space)
        harness.press(.right)
        #expect(harness.lattice?.columns.last?.alternatives.contains("飴") == true)
        harness.press(.enter)
        #expect(harness.committed == "今日は雨")
    }

    @Test("入力中の候補の窓は，読みの変換を先に出し，続く語の予測はあとから足す")
    func suggestionPredictionsLater() {
        let converter = FakeConverter(["きょう": [("今日", nil), ("京", nil)]])
        converter.predictionTexts["きょう"] = ["今日は", "教室"]
        var settings = DefaultSettings.settings
        settings.suggestionDisplay = .always
        let harness = Harness(converter: converter, settings: settings)
        harness.runsFollowUps = false
        harness.type("kyou")
        #expect(harness.panel?.entries.map(\.text) == ["今日", "京"])
        harness.followUp()
        #expect(harness.panel?.entries.map(\.text) == ["今日", "京", "今日は", "教室"])
    }

    @Test("入力中の候補の窓は，ローマ字を打ちかけているあいだも消さずに出しておく")
    func suggestionPanelStaysWhilePending() {
        let converter = FakeConverter(["きょう": [("今日", nil)]])
        var settings = DefaultSettings.settings
        settings.suggestionDisplay = .always
        let harness = Harness(converter: converter, settings: settings)
        harness.type("kyou")
        #expect(harness.panel?.entries.first?.text == "今日")
        harness.press(.character("k"))
        #expect(harness.panel?.entries.first?.text == "今日")
    }
}
