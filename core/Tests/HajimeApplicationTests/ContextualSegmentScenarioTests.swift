import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

/// 文節の候補を前後の語とのつながりで並べる(設定の contextualSegmentCandidates)
@Suite("文節の候補を前後の文脈で並べる")
@MainActor
struct ContextualSegmentScenarioTests {
    /// 「手紙を｜加工」に分かれる変換器．「かこう」だけの候補は「加工・河口・書こう」の順(前に「を」があることを知らない)．
    /// 前の語を含めた「をかこう」では「を加工」「を書こう」の順になる
    private func converter() -> FakeConverter {
        let converter = FakeConverter([
            "てがみをかこう": [("手紙を加工", nil)],
            "かこう": [("加工", nil), ("河口", nil), ("書こう", nil)],
            "てがみを": [("手紙を", nil)],
            "をかこう": [("を加工", nil), ("を書こう", nil)],
        ])
        let particle = Candidate.Word(text: "を", readingCount: 1, startsWithParticle: true, endsWithParticle: true)
        converter.words["てがみをかこう"] = [Candidate.Word(text: "手紙", readingCount: 3), particle, Candidate.Word(text: "加工", readingCount: 3)]
        converter.candidateWords["手紙を加工"] = converter.words["てがみをかこう"]
        converter.candidateWords["を加工"] = [particle, Candidate.Word(text: "加工", readingCount: 3)]
        converter.candidateWords["を書こう"] = [particle, Candidate.Word(text: "書こう", readingCount: 3)]
        return converter
    }

    private func secondSegmentAlternatives(contextual: Bool, presentation: CandidatePresentation) -> [String]? {
        var settings = DefaultSettings.settings
        settings.initialFocus = .start
        settings.candidatePresentation = presentation
        settings.contextualSegmentCandidates = contextual
        let harness = Harness(converter: converter(), settings: settings)
        harness.type("tegamiwokakou")
        harness.press(.space)
        harness.press(.right)
        return harness.focusedAlternatives
    }

    @Test("前の語「を」を含めた変換で上に来た「書こう」を，文節の 2 番目に上げる", arguments: [CandidatePresentation.automatic, .segmentList])
    func contextRaisesCandidate(presentation: CandidatePresentation) {
        #expect(secondSegmentAlternatives(contextual: true, presentation: presentation)?.prefix(3) == ["加工", "書こう", "河口"])
    }

    @Test("設定を切ると，文節の読みだけで求めた順のまま", arguments: [CandidatePresentation.automatic, .segmentList])
    func settingOff(presentation: CandidatePresentation) {
        #expect(secondSegmentAlternatives(contextual: false, presentation: presentation)?.prefix(3) == ["加工", "河口", "書こう"])
    }

    @Test("文節の読みだけの候補に無い字も足す．辞書の「を書こう」のようにつながった語も助詞を切って使う")
    func neighborWindow() {
        let converter = converter()
        converter.table["をかこう"] = [("を囲う", nil), ("を書こう", nil)]
        converter.candidateWords["を囲う"] = [Candidate.Word(text: "を", readingCount: 1, startsWithParticle: true), Candidate.Word(text: "囲う", readingCount: 3)]
        // 辞書の「を書こう」のように助詞と次の語がつながった語も，助詞を切って使う
        converter.candidateWords["を書こう"] = [Candidate.Word(text: "を書こう", readingCount: 4, startsWithParticle: true)]
        var settings = DefaultSettings.settings
        settings.initialFocus = .start
        let harness = Harness(converter: converter, settings: settings)
        harness.type("tegamiwokakou")
        harness.press(.space)
        harness.press(.right)
        #expect(harness.focusedAlternatives?.prefix(4) == ["加工", "囲う", "書こう", "河口"])
    }

    @Test("読み全体の候補で文節の読みの範囲になった字を，前後の語を含めた変換より先に並べる")
    func sentenceCandidatesFirst() {
        let converter = converter()
        converter.table["てがみをかこう"] = [("手紙を加工", nil), ("手紙を河口", nil)]
        converter.candidateWords["手紙を河口"] = [Candidate.Word(text: "手紙", readingCount: 3), Candidate.Word(text: "を", readingCount: 1), Candidate.Word(text: "河口", readingCount: 3)]
        var settings = DefaultSettings.settings
        settings.initialFocus = .start
        let harness = Harness(converter: converter, settings: settings)
        harness.type("tegamiwokakou")
        harness.press(.space)
        harness.press(.right)
        #expect(harness.focusedAlternatives?.prefix(3) == ["加工", "河口", "書こう"])
    }

    @Test("読みの違う字(打ち間違いを直した候補)は並べ替えに使わない")
    func skipsInconsistentReading() {
        let converter = converter()
        converter.table["をかこう"] = [("を書く", nil), ("を書こう", nil)]
        converter.candidateWords["を書く"] = [Candidate.Word(text: "を", readingCount: 1), Candidate.Word(text: "書く", readingCount: 3)]
        var settings = DefaultSettings.settings
        settings.initialFocus = .start
        let harness = Harness(converter: converter, settings: settings)
        harness.type("tegamiwokakou")
        harness.press(.space)
        harness.press(.right)
        #expect(harness.focusedAlternatives?.prefix(3) == ["加工", "書こう", "河口"])
    }
}
