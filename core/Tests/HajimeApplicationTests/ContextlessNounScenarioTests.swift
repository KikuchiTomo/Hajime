import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

@Suite("左の文脈が無い 1 語の名詞")
@MainActor
struct ContextlessNounScenarioTests {
    /// Zenzai の候補は「いえ」が先，Zenzai を使わない変換(文節の読みだけの候補)は「家」が先の変換エンジン
    private static func converter() -> SupplementedConverter {
        let base = FakeConverter(["いえ": [("いえ", nil), ("家", nil), ("言え", nil)]], clauses: ["いえ": [("家", 2), ("いえ", 2)]])
        base.candidateWords["家"] = [Candidate.Word(text: "家", readingCount: 2, startsWithNoun: true, isCommonNoun: true)]
        return SupplementedConverter(base, settings: FakeSettings(), calendar: FakeCalendar())
    }

    @Test("左の文脈が無ければ，読みのかなのままの第 1 候補より，Zenzai を使わない変換の名詞を先にする")
    func nounFirstWithoutContext() {
        let converter = Self.converter()
        #expect(converter.candidates(for: "いえ").prefix(3).map(\.text) == ["家", "いえ", "言え"])
        converter.setLeftContext(" \n")
        #expect(converter.listCandidates(for: "いえ").first?.text == "家")
    }

    @Test("左の文脈があれば，Zenzai の第 1 候補のまま")
    func keepsZenzaiWithContext() {
        let converter = Self.converter()
        converter.setLeftContext("それは")
        #expect(converter.candidates(for: "いえ").prefix(3).map(\.text) == ["いえ", "家", "言え"])
    }
}
