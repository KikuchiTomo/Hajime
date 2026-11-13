import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

/// 候補の 2 番目から後ろを文脈で並べ替える(検証木．ADR 0016)
@MainActor
@Suite("Zenzai による候補の並べ替え")
struct CandidateRerankingScenarioTests {
    /// 「あめ」1 文節．Zenzai の変換の候補は 雨・亜目．Zenzai を使わない変換の候補(文節の候補)は 雨・飴・天(偽物では Zenzai の変換の候補も続く)
    private func singleSegment() -> FakeConverter {
        FakeConverter(["あめ": [("雨", nil), ("亜目", nil)]], clauses: ["あめ": [("雨", 2), ("飴", 2), ("天", 2)]])
    }

    /// 「きょうはあめ」2 文節(今日は｜雨)
    private func twoSegments() -> FakeConverter {
        let converter = FakeConverter(
            ["きょうはあめ": [("今日は雨", nil)], "あめ": [("雨", nil)], "きょう": [("今日", nil)], "はあめ": [("は雨", nil)]],
            clauses: [
                "きょうはあめ": [("今日は", 4), ("京は", 4)],
                "きょうは": [("今日は", 4), ("京は", 4), ("経は", 4)],
                "あめ": [("雨", 2), ("飴", 2), ("天", 2)],
                "はあめ": [("は雨", 3)],
            ]
        )
        converter.clauseScoreStep["きょうはあめ"] = 1
        return converter
    }

    /// 一覧の設定．文節を入れ替えた文は混ぜない(エンジンの文全体の候補の並びだけを確かめる)
    private var listSettings: Settings {
        var settings = DefaultSettings.settings
        settings.candidatePresentation = .list
        settings.listSegmentAlternatives = false
        return settings
    }

    @Test("分岐図の文節の候補を点数の順に並べ，第 1 候補(幹)は変えない")
    func branchMapReorders() {
        let scorer = FakeCandidateScorer(["雨": -9, "飴": -5, "天": -1, "亜目": -3])
        let harness = Harness(converter: singleSegment(), scorer: scorer)
        harness.type("ame")
        harness.press(.space)
        #expect(harness.focusedAlternatives == ["雨", "天", "亜目", "飴"])
    }

    @Test("分岐図では，Space で採点を待たずに出し，続く処理で採点して並べ替える")
    func branchMapScoresAfterShowing() {
        let scorer = FakeCandidateScorer(["雨": -9, "飴": -5, "天": -1, "亜目": -3])
        let harness = Harness(converter: singleSegment(), scorer: scorer)
        harness.runsFollowUps = false
        harness.type("ame")
        harness.press(.space)
        #expect(scorer.requests.isEmpty)
        #expect(harness.focusedAlternatives == ["雨", "飴", "天", "亜目"])
        harness.followUp()
        #expect(scorer.requests.count == 1)
        #expect(harness.focusedAlternatives == ["雨", "天", "亜目", "飴"])
    }

    @Test("あとから並べ替えるとき，利用者が候補を動かしていれば，選んでいる候補とそれより前は動かさない")
    func lateScoringKeepsSelection() {
        let scorer = FakeCandidateScorer(["雨": -9, "飴": -5, "天": -1, "亜目": -3])
        let harness = Harness(converter: singleSegment(), scorer: scorer)
        harness.runsFollowUps = false
        harness.type("ame")
        harness.press(.space)
        harness.press(.down)
        let before = harness.lattice?.columns.first(where: \.isFocused)
        harness.followUp()
        let after = harness.lattice?.columns.first(where: \.isFocused)
        #expect(scorer.requests.count == 1)
        #expect(after?.text == before?.text)
        #expect(after?.alternatives.prefix(2) == before?.alternatives.prefix(2))
    }

    @Test("文節は前後の文節の幹の文字を文脈にして採点する")
    func usesNeighborSegmentsAsContext() {
        let scorer = FakeCandidateScorer(["飴": -1, "天": -2, "京は": -3, "経は": -1])
        let harness = Harness(converter: twoSegments(), scorer: scorer)
        harness.type("kyouhaame")
        harness.press(.space)
        #expect(harness.lattice?.columns.map(\.text) == ["今日は", "雨"])
        // 候補を見せる文節(注目している文節)から採点する．もう一方は注目を移したときに採点する
        harness.press(.right)
        harness.press(.left)
        let rain = scorer.requests.first { $0.reading == "あめ" }
        #expect(rain?.before == "今日は")
        #expect(rain?.after == "")
        let today = scorer.requests.first { $0.reading == "きょうは" }
        #expect(today?.before == "")
        #expect(today?.after == "雨")
    }

    @Test("設定でオフなら採点せず，元の順のまま")
    func settingOff() {
        var settings = DefaultSettings.settings
        settings.candidateReranking = false
        let scorer = FakeCandidateScorer(["飴": -5, "天": -1])
        let harness = Harness(converter: singleSegment(), settings: settings, scorer: scorer)
        harness.type("ame")
        harness.press(.space)
        #expect(scorer.requests.isEmpty)
        #expect(harness.focusedAlternatives == ["雨", "飴", "天", "亜目"])
    }

    @Test("一覧でも 2 番目から後ろを並べ替え，Zenzai を使わない変換の候補も混ぜる")
    func listReorders() {
        let scorer = FakeCandidateScorer(["亜目": -4, "飴": -1, "天": -2])
        let harness = Harness(converter: singleSegment(), settings: listSettings, scorer: scorer)
        harness.type("ame")
        harness.press(.space)
        #expect(harness.panel?.entries.prefix(4).map(\.text) == ["雨", "飴", "天", "亜目"])
    }

    @Test("一覧では，打鍵が止まったあいだに Space で求めるのと同じ問いで採点しておく")
    func warmsTheSameQuestions() {
        let scorer = FakeCandidateScorer(["飴": -1])
        let harness = Harness(converter: singleSegment(), settings: listSettings, scorer: scorer)
        harness.type("ame")
        harness.settle()
        harness.session.latticeWarmingSteps.forEach { $0() }
        let warmed = scorer.requests.map { [$0.reading, $0.before, $0.after] + $0.texts }
        #expect(!warmed.isEmpty)
        let count = scorer.requests.count
        harness.press(.space)
        let atSpace = scorer.requests.dropFirst(count).map { [$0.reading, $0.before, $0.after] + $0.texts }
        #expect(atSpace.allSatisfy { warmed.contains($0) })
    }

    @Test("採点が遅い環境では Space で採点を待たず，打鍵の合間に求めた点数があるときだけ並べ替える")
    func slowScorerUsesPrecomputedScores() {
        let scorer = FakeCandidateScorer(["亜目": -4, "飴": -1, "天": -2])
        scorer.prefersPrecomputedScores = true
        let cold = Harness(converter: singleSegment(), settings: listSettings, scorer: scorer)
        cold.type("ame")
        cold.press(.space)
        #expect(scorer.requests.isEmpty)
        #expect(cold.panel?.entries.prefix(2).map(\.text) == ["雨", "亜目"])

        let warmed = Harness(converter: singleSegment(), settings: listSettings, scorer: scorer)
        warmed.type("ame")
        warmed.settle()
        warmed.session.latticeWarmingSteps.forEach { $0() }
        warmed.press(.space)
        #expect(warmed.panel?.entries.prefix(4).map(\.text) == ["雨", "飴", "天", "亜目"])
    }

    @Test("分岐図では，採点が遅い環境なら Space で採点を待たず，元の順のまま出す")
    func slowScorerInBranchMap() {
        let scorer = FakeCandidateScorer(["雨": -9, "飴": -5, "天": -1, "亜目": -3])
        scorer.prefersPrecomputedScores = true
        let harness = Harness(converter: singleSegment(), scorer: scorer)
        harness.type("ame")
        harness.press(.space)
        #expect(scorer.requests.isEmpty)
        #expect(harness.focusedAlternatives == ["雨", "飴", "天", "亜目"])
    }
}
