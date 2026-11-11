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
        harness.press(.space)
        harness.press(.down)
        harness.press(.enter)
        #expect(harness.committed == "手紙を河口")
    }
}
