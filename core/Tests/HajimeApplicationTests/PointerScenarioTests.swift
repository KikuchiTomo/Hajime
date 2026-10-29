import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

@Suite("候補の窓をマウスで押す")
@MainActor
struct PointerScenarioTests {
    /// 「きょうは」「いい」の 2 文節になる変換器
    private func twoSegments() -> FakeConverter {
        let converter = FakeConverter([
            "きょうはいい": [("今日はいい", nil)], "きょうは": [("今日は", nil), ("京は", nil)], "いい": [("良い", nil), ("いい", nil)],
            "きょう": [("今日", nil)], "は": [("は", nil)],
        ])
        converter.words["きょうはいい"] = [
            Candidate.Word(text: "今日", readingCount: 3), Candidate.Word(text: "は", readingCount: 1, startsWithParticle: true, endsWithParticle: true),
            Candidate.Word(text: "いい", readingCount: 2),
        ]
        return converter
    }

    @Test("分岐図の幹を押すとその文節を選び，枝を押すと番号キーで選んだのと同じに動く(残りが無ければ確定)")
    func lattice() {
        let harness = Harness(converter: twoSegments())
        harness.type("kyouhaii")
        harness.press(.space)
        let columns = harness.lattice?.columns.count ?? 0
        #expect(columns >= 1)
        if columns > 1 {
            harness.click(.segment(1))
            #expect(harness.lattice?.columns.firstIndex(where: \.isFocused) == 1)
            harness.click(.segment(0))
            #expect(harness.lattice?.columns.firstIndex(where: \.isFocused) == 0)
        }
        // 範囲の外は何もしない
        harness.click(.segment(99))
        #expect(harness.committed.isEmpty)
        // 枝を押していけば，迷う文節が無くなったところで確定する
        for _ in 0..<columns where harness.committed.isEmpty {
            harness.click(.alternative(0))
        }
        #expect(!harness.committed.isEmpty)
    }

    @Test("分岐図の上の枝(字種)を押すと，その字種を選ぶ")
    func latticeVariant() {
        let harness = Harness(converter: FakeConverter(["きょう": [("今日", nil), ("京", nil)]]))
        harness.type("kyou")
        harness.press(.space)
        let variants = harness.lattice?.columns.first?.variants ?? []
        #expect(!variants.isEmpty)
        harness.click(.variant(0))
        #expect(harness.committed == variants.first)
    }

    @Test("候補の一覧の行を押すと，その候補で確定する(番号を押して Enter と同じ)")
    func list() {
        var settings = DefaultSettings.settings
        settings.candidatePresentation = .list
        let harness = Harness(converter: FakeConverter(["きょう": [("今日", nil), ("京", nil), ("強", nil)]]), settings: settings)
        harness.type("kyou")
        harness.press(.space)
        #expect(harness.panel != nil)
        harness.click(.entry(1))
        #expect(harness.committed == "京")
    }

    @Test("候補の一覧の字種の行を押すと，その字種で確定する．今の状態に無い対象は何もしない")
    func listVariant() {
        var settings = DefaultSettings.settings
        settings.candidatePresentation = .list
        let harness = Harness(converter: FakeConverter(["きょう": [("今日", nil)]]), settings: settings)
        harness.type("kyou")
        harness.click(.entry(0))
        #expect(harness.committed.isEmpty)
        harness.press(.space)
        let index = ScriptVariant.allCases.firstIndex(of: .katakana) ?? 0
        harness.click(.listVariant(index))
        #expect(harness.committed == "キョウ")
    }
}
