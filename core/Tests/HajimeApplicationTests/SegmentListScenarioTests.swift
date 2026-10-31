import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

@Suite("文節ごとの一覧")
@MainActor
struct SegmentListScenarioTests {
    private func settings() -> Settings {
        var settings = DefaultSettings.settings
        settings.candidatePresentation = .segmentList
        settings.initialFocus = .start
        return settings
    }

    /// 「もんだいがある」を 1 つの文節にし，語の並びを「問題｜が｜ある」にした変換器
    private func problemConverter() -> FakeConverter {
        let converter = FakeConverter(["もんだいがある": [("問題がある", nil), ("問題が或る", nil)], "もんだい": [("問題", nil), ("門題", nil)],
                                       "がある": [("がある", nil), ("が或る", nil)], "もんだいが": [("問題が", nil)], "ある": [("ある", nil), ("或る", nil)]])
        converter.words["もんだいがある"] = [
            Candidate.Word(text: "問題", readingCount: 4), Candidate.Word(text: "が", readingCount: 1, startsWithParticle: true, endsWithParticle: true),
            Candidate.Word(text: "ある", readingCount: 2),
        ]
        let particle = Candidate.Word(text: "が", readingCount: 1, startsWithParticle: true, endsWithParticle: true)
        let exist = Candidate.Word(text: "ある", readingCount: 2, startsWithPredicate: true)
        converter.words["がある"] = [particle, exist]
        converter.words["ある"] = [exist]
        converter.words["もんだいが"] = [Candidate.Word(text: "問題", readingCount: 4), particle]
        converter.words["もんだい"] = [Candidate.Word(text: "問題", readingCount: 4)]
        return converter
    }

    @Test("Space で分岐図と同じ文節に分け，注目している文節の候補を一覧に出す．←→ で文節を移る")
    func segmentsAndMovesFocus() {
        let converter = FakeConverter(["きょうは": [("京は", nil)], "きょう": [("今日", nil), ("京", nil)], "は": [("は", nil), ("葉", nil)]])
        let harness = Harness(converter: converter, settings: settings())
        harness.type("kyou")
        harness.press(.space, .option)
        harness.type("ha")
        harness.press(.space)
        #expect(harness.lattice == nil)
        #expect(harness.marked.segments.map(\.text) == ["今日", "は"])
        #expect(harness.marked.segments.first?.style == .focused)
        #expect(harness.panel?.entries.prefix(2).map(\.text) == ["今日", "京"])
        harness.press(.right)
        #expect(harness.marked.segments.last?.style == .focused)
        #expect(harness.panel?.entries.prefix(2).map(\.text) == ["は", "葉"])
        harness.press(.down)
        harness.press(.enter)
        #expect(harness.committed == "今日葉")
    }

    @Test("文節の長さを変えるキーと，語の切れ目で区切るキーも分岐図と同じに使える")
    func resizesAndSplits() {
        let harness = Harness(converter: problemConverter(), settings: settings())
        harness.type("mondaigaaru")
        harness.press(.space)
        #expect(harness.marked.segments.map(\.text) == ["問題がある"])
        harness.press(.down, .shift)
        #expect(harness.panel?.entries.map(\.text) == ["問題｜がある", "問題が｜ある"])
        harness.press(.character("1"))
        #expect(harness.marked.segments.map(\.text) == ["問題", "がある"])
        #expect(harness.panel?.entries.prefix(2).map(\.text) == ["問題", "門題"])
        harness.press(.right, .shift)
        #expect(harness.marked.segments.map(\.text) == ["問題が", "ある"])
    }

    @Test("番号キーとマウスで注目している文節の候補を選ぶ．選び終えたら確定する")
    func selectsByNumberAndPointer() {
        let converter = FakeConverter(["きょうは": [("京は", nil)], "きょう": [("今日", nil), ("京", nil)], "は": [("は", nil), ("葉", nil)]])
        let harness = Harness(converter: converter, settings: settings())
        harness.type("kyou")
        harness.press(.space, .option)
        harness.type("ha")
        harness.press(.space)
        harness.press(.character("2"))
        #expect(harness.marked.segments.first?.text == "京")
        harness.press(.right)
        // 選び終えたら(迷う文節が残っていなければ)分岐図と同じに確定する
        harness.click(.entry(1))
        #expect(harness.committed == "京葉")
    }

    @Test("候補の先頭から ↑ で種類の行に入り，←→ で字種を移る")
    func variantRow() {
        let harness = Harness(converter: FakeConverter(["きょう": [("今日", nil)]]), settings: settings())
        harness.type("kyou")
        harness.press(.space)
        harness.press(.up)
        #expect(harness.panel?.focus == .variants)
        #expect(harness.panel?.selectedVariant == ScriptVariant.allCases.firstIndex(of: .hiragana))
        harness.press(.right)
        #expect(harness.panel?.selectedVariant == ScriptVariant.allCases.firstIndex(of: .katakana))
        harness.press(.enter)
        #expect(harness.committed == "キョウ")
    }
}
