import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

/// 文全体の候補の一覧に，文節を 1 か所だけ替えた文を入れる(設定の listSegmentAlternatives)
@Suite("一覧に文節を入れ替えた候補を出す")
@MainActor
struct ListAlternativesScenarioTests {
    /// 「手紙を｜加工」に分かれ，文全体の候補が「手紙を加工」「手紙お加工」になる変換器．「かこう」の文節の 2 番目は「河口」
    private func converter() -> FakeConverter {
        let converter = FakeConverter([
            "てがみをかこう": [("手紙を加工", nil), ("手紙お加工", nil)],
            "かこう": [("加工", nil), ("河口", nil), ("書こう", nil)],
            "てがみを": [("手紙を", nil)],
        ])
        let particle = Candidate.Word(text: "を", readingCount: 1, startsWithParticle: true, endsWithParticle: true)
        converter.words["てがみをかこう"] = [Candidate.Word(text: "手紙", readingCount: 3), particle, Candidate.Word(text: "加工", readingCount: 3)]
        converter.candidateWords["手紙を加工"] = converter.words["てがみをかこう"]
        return converter
    }

    @Test("文全体の 2 番目から，替えた文とエンジンの候補を交互に並べる．設定を切ると入れない", arguments: [true, false])
    func listAlternatives(enabled: Bool) {
        var settings = Settings.listPresentation
        settings.listSegmentAlternatives = enabled
        settings.contextualSegmentCandidates = false
        let harness = Harness(converter: converter(), settings: settings)
        harness.type("tegamiwokakou")
        warm(harness)
        harness.press(.space)
        let entries = harness.panel?.entries.map(\.text) ?? []
        if enabled {
            #expect(entries.prefix(3) == ["手紙を加工", "手紙を河口", "手紙お加工"])
        } else {
            #expect(entries.prefix(2) == ["手紙を加工", "手紙お加工"])
            #expect(!entries.contains("手紙を河口"))
        }
    }

    @Test("替えた文を確定すると，その文になる")
    func commitsAlternative() {
        let harness = Harness(converter: converter(), settings: .listPresentation)
        harness.type("tegamiwokakou")
        warm(harness)
        harness.press(.space)
        harness.press(.down)
        harness.press(.enter)
        #expect(harness.committed == "手紙を河口")
    }

    @Test("打鍵が止まらずに Space を押したときは，すぐには文節の候補を求めずに一覧を出し，打鍵の合間に求めて替えた文を足す．選んでいる候補は変えない")
    func spaceWithoutWarming() {
        let harness = Harness(converter: converter(), settings: .listPresentation)
        harness.type("tegamiwokakou")
        harness.runsFollowUps = false
        let before = harness.converter.requests.count
        harness.press(.space)
        let requested = harness.converter.requests.dropFirst(before).map(\.reading)
        #expect(!requested.contains("かこう") && !requested.contains("てがみを"))
        #expect(harness.panel?.entries.map(\.text).prefix(2) == ["手紙を加工", "手紙お加工"])
        harness.press(.down)
        harness.followUp()
        #expect(harness.panel?.entries.map(\.text).prefix(3) == ["手紙を加工", "手紙を河口", "手紙お加工"])
        harness.press(.enter)
        #expect(harness.committed == "手紙お加工")
    }

    @Test("確定したあとは，前の文で求めた文節の候補を使わない(変換器は確定のときにためた候補を捨てる)")
    func forgetsWarmedSegmentsAfterCommit() {
        let harness = Harness(converter: converter(), settings: .listPresentation)
        harness.type("tegamiwokakou")
        warm(harness)
        harness.press(.space)
        harness.press(.enter)
        harness.type("tegamiwokakou")
        harness.runsFollowUps = false
        let before = harness.converter.requests.count
        harness.press(.space)
        #expect(!harness.converter.requests.dropFirst(before).map(\.reading).contains("かこう"))
    }

    @Test("一覧を出したあと，打鍵の合間に前後の語を含めた変換を求め，入れ替えた文を前後の文脈で並べ替えて出し直す．設定を切ると並べ替えない",
          arguments: [true, false])
    func contextAfterShowing(contextual: Bool) {
        let converter = converter()
        // 前の語を含めた「をかこう」では「を書こう」が「を加工」の次に来る(「かこう」だけでは「加工・河口・書こう」の順)
        converter.table["をかこう"] = [("を加工", nil), ("を書こう", nil)]
        let particle = Candidate.Word(text: "を", readingCount: 1, startsWithParticle: true, endsWithParticle: true)
        converter.candidateWords["を加工"] = [particle, Candidate.Word(text: "加工", readingCount: 3)]
        converter.candidateWords["を書こう"] = [particle, Candidate.Word(text: "書こう", readingCount: 3)]
        var settings = Settings.listPresentation
        settings.contextualSegmentCandidates = contextual
        let harness = Harness(converter: converter, settings: settings)
        harness.type("tegamiwokakou")
        warm(harness)
        harness.runsFollowUps = false
        harness.press(.space)
        #expect(harness.panel?.entries.map(\.text).prefix(3) == ["手紙を加工", "手紙を河口", "手紙お加工"])
        harness.followUp()
        #expect(harness.panel?.entries.map(\.text).prefix(3) == ["手紙を加工", contextual ? "手紙を書こう" : "手紙を河口", "手紙お加工"])
    }

    /// アプリで打鍵が止まったときと同じく，前もって求める手順をすべて動かす
    private func warm(_ harness: Harness) {
        harness.session.latticeWarmingSteps.forEach { $0() }
    }
}
