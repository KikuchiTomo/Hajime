import HajimeDomain
import Testing

@Suite("促音の切れ端を漢字とつないだ候補を除く")
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

    @Test("かなと促音で終わる語や，漢字のあとのカタカナの「ッ」のすぐ後に漢字の語が続く候補を除く対象にする", arguments: [
        ["じゅっ", "分"], ["ざっ", "氏", "を"], ["はっ", "再", "の"], ["ジュ", "っ", "分"],
        ["シュッ", "派", "つ"], ["ハッ", "中", "した"], ["アッ", "制"], ["良", "ッ", "書", "に"], ["良ッ", "本", "の"],
    ])
    func brokenWords(words: [String]) {
        #expect(SokuonFragments.isBroken(Self.engine(words)))
    }

    @Test("カタカナの「ッ」でも，1 つの語・強めの接頭の語・数のあとの「ッ」は除かない", arguments: [
        ["フッ素"], ["トッ捕まる"], ["ズッ友"], ["ブッ", "飛ばす"], ["カッ", "飛ぶ"], ["フッ", "化"], ["真ッ", "赤"], ["三ッ", "星"], ["ハッ", "と"],
    ])
    func keepsKatakanaWords(words: [String]) {
        #expect(!SokuonFragments.isBroken(Self.engine(words)))
    }

    @Test("1 つの語・動詞の活用の促音・強めの接頭の語・漢字の続かない促音は除かない", arguments: [
        ["うっ血"], ["三ッ星"], ["引っ越し", "を"], ["引っ", "越し"], ["言っ", "た"], ["ぶっ", "飛ぶ"], ["ひっ", "越し"], ["とっ", "捕まえる"],
        ["ちょっと", "待っ", "て"],
    ])
    func keepsWords(words: [String]) {
        #expect(!SokuonFragments.isBroken(Self.engine(words)))
    }

    @Test("語の区切りが分からない候補は文字で見る．漢字のすぐ後の送りがなの促音は当たらない")
    func fragmentedText() {
        #expect(SokuonFragments.isBroken(Self.combined("はっ再の")))
        #expect(SokuonFragments.isBroken(Self.combined("ジュっ分")))
        #expect(SokuonFragments.isBroken(Self.combined("シュッ派つ")))
        // 先頭の語を選び直した候補は，その語の中の切れ目も見る(いっ＋本 に の をつないだもの)
        var head = Self.engine(["いっ", "本"], readingCount: 4)
        head.text = "いっ本"
        var combined = Self.combined("いっ本の", readingCount: 5)
        combined.learnedParts = [head]
        #expect(SokuonFragments.isBroken(combined))
        var word = Candidate(text: "三ッ星", readingCount: 4, origin: .engine(id: 1), words: [Candidate.Word(text: "三ッ星", readingCount: 4)])
        word.text = "三ッ星"
        var star = Self.combined("三ッ星の", readingCount: 5)
        star.learnedParts = [word]
        #expect(!SokuonFragments.isBroken(star))
        #expect(!SokuonFragments.isBroken(Self.combined("開けっ放し")))
        #expect(!SokuonFragments.isBroken(Self.combined("引っ越しを")))
        #expect(!SokuonFragments.isBroken(Self.combined("ぶっ飛ぶ")))
    }

    @Test("エンジン以外の候補(ユーザー辞書の語・記号)は見ない")
    func ignoresNonEngineCandidates() {
        #expect(!SokuonFragments.isBroken(Candidate(text: "はっ再", readingCount: 4, origin: .userDictionary)))
        #expect(!SokuonFragments.isBroken(Candidate(text: "はッ制", readingCount: 4, origin: .symbol)))
    }

    @Test("第 1 候補は変えず，2 番目から後ろの崩れた候補を除く．ほかの候補の順は変えない")
    func cleaned() {
        let candidates = [
            Self.engine(["はっ", "再"]), Self.engine(["発", "再"]), Self.engine(["じゅっ", "分"]), Self.combined("じゅッぷん"),
            Self.engine(["寿", "っ", "分"]), Self.engine(["じゅっ"], readingCount: 3), Self.engine(["ジュップン"]),
        ]
        #expect(SokuonFragments.cleaned(candidates).map(\.text) == ["はっ再", "発再", "寿っ分", "じゅっ", "ジュップン"])
    }
}
