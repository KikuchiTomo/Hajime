import HajimeDomain
import Testing

@Suite("促音の切れ端を漢字とつないだ候補を除く・下げる")
struct SokuonFragmentsTests {
    /// 語の区切りの分かるエンジンの候補．words は語の文字の並び
    private static func engine(_ words: [String], readingCount: Int = 5) -> Candidate {
        Candidate(text: words.joined(), readingCount: readingCount, origin: .engine(id: 0),
                  words: words.map { Candidate.Word(text: $0, readingCount: 1) })
    }

    /// 語の区切りの分からない，語をつないだ候補
    private static func combined(_ text: String, readingCount: Int = 5) -> Candidate {
        Candidate(text: text, readingCount: readingCount, origin: .combined)
    }

    @Test("ひらがなのすぐ後にカタカナの「ッ」が来る候補を除く対象にする", arguments: ["はッ制", "きッぷを", "けッか", "いッ所に"])
    func brokenAfterHiragana(text: String) {
        #expect(SokuonFragments.isBroken(Self.combined(text)))
    }

    @Test("カタカナの語の「ッ」と，漢字のあとの「ッ」は除かない", arguments: ["ハッとする", "三ッ星", "フッ素", "ちょっと"])
    func keepsOtherSmallTsu(text: String) {
        #expect(!SokuonFragments.isBroken(Self.combined(text)))
    }

    @Test("かなと促音で終わる語のすぐ後に漢字の語が続く候補を下げる対象にする", arguments: [
        ["じゅっ", "分"], ["ざっ", "氏", "を"], ["ハッ", "中", "した"], ["はっ", "再", "の"], ["ジュ", "っ", "分"], ["良", "ッ", "書", "に"],
    ])
    func fragmentedWords(words: [String]) {
        #expect(SokuonFragments.isFragmented(Self.engine(words)))
    }

    @Test("1 つの語・動詞の活用の促音・強めの接頭の語・漢字の続かない促音は下げない", arguments: [
        ["うっ血"], ["三ッ星"], ["引っ越し", "を"], ["引っ", "越し"], ["言っ", "た"], ["ぶっ", "飛ぶ"], ["ひっ", "越し"], ["とっ", "捕まえる"],
        ["ちょっと", "待っ", "て"],
    ])
    func keepsWords(words: [String]) {
        #expect(!SokuonFragments.isFragmented(Self.engine(words)))
    }

    @Test("語の区切りが分からない候補は文字で見る．漢字のすぐ後の送りがなの促音は当たらない")
    func fragmentedText() {
        #expect(SokuonFragments.isFragmented(Self.combined("はっ再の")))
        #expect(SokuonFragments.isFragmented(Self.combined("ジュっ分")))
        #expect(!SokuonFragments.isFragmented(Self.combined("開けっ放し")))
        #expect(!SokuonFragments.isFragmented(Self.combined("引っ越しを")))
        #expect(!SokuonFragments.isFragmented(Self.combined("ぶっ飛ぶ")))
    }

    @Test("エンジン以外の候補(ユーザー辞書の語・記号)は見ない")
    func ignoresNonEngineCandidates() {
        #expect(!SokuonFragments.isFragmented(Candidate(text: "はっ再", readingCount: 4, origin: .userDictionary)))
        #expect(!SokuonFragments.isBroken(Candidate(text: "はッ制", readingCount: 4, origin: .symbol)))
    }

    @Test("第 1 候補は変えず，除く候補を除き，下げる候補を同じ読みの数のほかの候補の下へ移す")
    func cleaned() {
        let candidates = [
            Self.engine(["10", "分"]), Self.engine(["十分"]), Self.engine(["じゅっ", "分"]), Self.combined("じゅッぷん"),
            Self.engine(["寿", "っ", "分"]), Self.engine(["じゅっ"], readingCount: 3), Self.engine(["ジュップン"]),
        ]
        let result = SokuonFragments.cleaned(candidates)
        #expect(result.map(\.text) == ["10分", "十分", "寿っ分", "じゅっ", "ジュップン", "じゅっ分"])
    }

    @Test("同じ読みの数のほかの候補が後ろに無ければ動かさない．第 1 候補が下げる候補でも動かさない")
    func keepsWhenNothingBelow() {
        let candidates = [Self.engine(["はっ", "再"]), Self.engine(["発", "再"]), Self.engine(["はっ", "最"]), Self.engine(["はっ"], readingCount: 2)]
        #expect(SokuonFragments.cleaned(candidates).map(\.text) == ["はっ再", "発再", "はっ最", "はっ"])
    }
}
