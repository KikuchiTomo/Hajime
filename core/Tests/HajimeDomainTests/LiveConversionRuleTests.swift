import Testing
@testable import HajimeDomain

@Suite("ライブ変換で見せる文")
struct LiveConversionRuleTests {
    private func candidate(_ words: [(String, Int)]) -> Candidate {
        Candidate(text: words.map(\.0).joined(), readingCount: words.map(\.1).reduce(0, +), origin: .engine(id: 0),
                  words: words.map { Candidate.Word(text: $0.0, readingCount: $0.1) })
    }

    @Test("打っている途中の文の先頭は，前に止まったときの文に合わせる(打って ↔ 売って でちらつかない)")
    func keepsSettledPrefix() {
        let settled = candidate([("打って", 3), ("いる", 2)])
        let typing = candidate([("売って", 3), ("いる", 2), ("とき", 2)])
        let shown = LiveConversionRule().stabilized(typing, reading: "うっているとき", settled: (settled, "うっている"))
        #expect(shown.text == "打っているとき")
        #expect(shown.words.map(\.text) == ["打って", "いる", "とき"])
        #expect(shown.readingCount == 7)
    }

    @Test("止まったときの読みが先頭でない(Backspace で戻した)ときや，語の区切りが合わないときは，今の文のまま")
    func keepsCandidateOtherwise() {
        let rule = LiveConversionRule()
        let typing = candidate([("売って", 3), ("いる", 2)])
        #expect(rule.stabilized(typing, reading: "うっている", settled: (candidate([("打った", 3)]), "うった")).text == "売っている")
        #expect(rule.stabilized(typing, reading: "うっている", settled: (candidate([("打っ", 2)]), "うっ")).text == "売っている")
        #expect(rule.stabilized(typing, reading: "うっている", settled: nil).text == "売っている")
        let noWords = Candidate(text: "売っている", readingCount: 5, origin: .engine(id: 0))
        #expect(rule.stabilized(noWords, reading: "うっている", settled: (candidate([("打って", 3)]), "うって")).text == "売っている")
    }
}
