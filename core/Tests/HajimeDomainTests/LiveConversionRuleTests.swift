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

    @Test("止まって変換して見せた語は，続けて打ってもかなに戻さない．止まったあとに打った語だけをかなのまま見せる")
    func keepsConvertedWords() {
        let rule = LiveConversionRule()
        let sentence = Candidate(text: "今日は雷", readingCount: 6, origin: .engine(id: 0), trailingWord: .init(readingCount: 2, textCount: 1))
        // 止まる前に見せていない(convertedLength が 0)なら，末尾の短い語はかなのまま
        #expect(rule.display(of: sentence, reading: "きょうはらい", settled: false) == "今日はらい")
        // 「きょうはらい」で止まって「今日は雷」を見せたあとは，ローマ字を打ちかけても「雷」をかなに戻さない
        #expect(rule.display(of: sentence, reading: "きょうはらい", settled: false, convertedLength: 6) == "今日は雷")
        // 「きょうは」で止まったあとに打った「らい」は，止まるまでかなのまま
        #expect(rule.display(of: sentence, reading: "きょうはらい", settled: false, convertedLength: 4) == "今日はらい")
        // 止まって見せた語に続けて打った語(雷 → ライブ)も，かなに戻さない
        let live = Candidate(text: "今日はライブ", readingCount: 7, origin: .engine(id: 0), trailingWord: .init(readingCount: 3, textCount: 3))
        #expect(rule.display(of: live, reading: "きょうはらいぶ", settled: false, convertedLength: 6) == "今日はライブ")
        // 短い読みでも，止まって変換して見せたものはかなに戻さない
        let thunder = Candidate(text: "雷", readingCount: 2, origin: .engine(id: 0), trailingWord: .init(readingCount: 2, textCount: 1))
        #expect(rule.display(of: thunder, reading: "らい", settled: false) == "らい")
        #expect(rule.display(of: thunder, reading: "らい", settled: false, convertedLength: 2) == "雷")
    }
}
