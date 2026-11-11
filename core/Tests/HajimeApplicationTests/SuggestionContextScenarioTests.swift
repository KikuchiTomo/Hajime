import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

/// 入力中の候補の窓で，今打っている文節の候補を文全体の候補で並べ替える(設定の contextualSegmentCandidates)
@Suite("入力中の候補を文の流れで並べる")
@MainActor
struct SuggestionContextScenarioTests {
    /// 文全体では「手紙を書こう」になり，「かこう」だけの候補は「加工・河口・書こう」の順になる変換器
    private func converter() -> FakeConverter {
        let converter = FakeConverter([
            "てがみをかこう": [("手紙を書こう", nil), ("手紙を加工", nil)],
            "かこう": [("加工", nil), ("河口", nil), ("書こう", nil)],
        ])
        let letter = Candidate.Word(text: "手紙", readingCount: 3, startsWithNoun: true)
        let particle = Candidate.Word(text: "を", readingCount: 1, startsWithParticle: true, endsWithParticle: true)
        converter.candidateWords["手紙を書こう"] = [letter, particle, Candidate.Word(text: "書こう", readingCount: 3, startsWithPredicate: true)]
        converter.candidateWords["手紙を加工"] = [letter, particle, Candidate.Word(text: "加工", readingCount: 3, startsWithNoun: true)]
        return converter
    }

    @Test("今打っている文節の候補を，文全体の候補でその文節になった字の順にする．設定を切ると文節の読みだけの順", arguments: [true, false])
    func ranksByContext(enabled: Bool) {
        var settings = DefaultSettings.settings
        settings.suggestionDisplay = .always
        settings.contextualSegmentCandidates = enabled
        let harness = Harness(converter: converter(), settings: settings)
        harness.type("tegamiwokakou")
        #expect(harness.marked.text == "手紙を書こう")
        let entries = harness.panel?.entries.map(\.text) ?? []
        if enabled {
            #expect(entries.prefix(3) == ["書こう", "加工", "河口"])
        } else {
            #expect(entries.prefix(3) == ["加工", "河口", "書こう"])
        }
    }

    @Test("並べ替えた候補を選んで確定すると，その字で確定する")
    func commitsRanked() {
        var settings = DefaultSettings.settings
        settings.suggestionDisplay = .always
        let harness = Harness(converter: converter(), settings: settings)
        harness.type("tegamiwokakou")
        harness.press(.down)
        harness.press(.down)
        harness.press(.enter)
        #expect(harness.committed == "手紙を加工")
    }
}
