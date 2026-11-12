import HajimeDomain
import Testing

@Suite("字の並びが崩れた候補を除く")
struct BrokenSpellingsTests {
    /// 語の区切りの分かるエンジンの候補．words は語の文字の並び
    private static func engine(_ words: [String], readingCount: Int = 5) -> Candidate {
        Candidate(text: words.joined(), readingCount: readingCount, origin: .engine(id: 0),
                  words: words.map { Candidate.Word(text: $0, readingCount: 1) })
    }

    /// 読みの分かる語．reading の終わりの促音を印にする
    private static func word(_ text: String, reading: String) -> Candidate.Word {
        Candidate.Word(text: text, readingCount: reading.count, endsWithSokuon: reading.hasSuffix("っ"))
    }

    /// 読みの分かる語をつないだエンジンの候補
    private static func engine(_ words: [(text: String, reading: String)]) -> Candidate {
        Candidate(text: words.map(\.text).joined(), readingCount: words.reduce(0) { $0 + $1.reading.count }, origin: .engine(id: 0),
                  words: words.map { word($0.text, reading: $0.reading) })
    }

    /// 語の区切りの分からない，語をつないだ候補
    private static func combined(_ text: String, readingCount: Int = 5) -> Candidate {
        Candidate(text: text, readingCount: readingCount, origin: .combined)
    }

    @Test("ひらがなのすぐ後にカタカナの「ッ」が来る候補を除く対象にする", arguments: ["はッ制", "きッぷを", "けッか", "いッ所に"])
    func brokenAfterHiragana(text: String) {
        #expect(BrokenSpellings.isBroken(Self.combined(text)))
    }

    @Test("カタカナの語の「ッ」と，漢字のあとの「ッ」は除かない", arguments: ["ハッとする", "三ッ星", "フッ素", "ちょっと"])
    func keepsOtherSmallTsu(text: String) {
        #expect(!BrokenSpellings.isBroken(Self.combined(text)))
    }

    @Test("かなと促音で終わる語や，漢字のあとのカタカナの「ッ」のすぐ後に漢字の語が続く候補を除く対象にする", arguments: [
        ["じゅっ", "分"], ["ざっ", "氏", "を"], ["はっ", "再", "の"], ["ジュ", "っ", "分"],
        ["シュッ", "派", "つ"], ["ハッ", "中", "した"], ["アッ", "制"], ["良", "ッ", "書", "に"], ["良ッ", "本", "の"], ["い", "っ子"], ["や", "っ子"],
    ])
    func brokenWords(words: [String]) {
        #expect(BrokenSpellings.isBroken(Self.engine(words)))
    }

    @Test("カタカナの「ッ」でも，1 つの語・強めの接頭の語・数のあとの「ッ」は除かない", arguments: [
        ["フッ素"], ["トッ捕まる"], ["ズッ友"], ["ブッ", "飛ばす"], ["カッ", "飛ぶ"], ["フッ", "化"], ["真ッ", "赤"], ["三ッ", "星"], ["ハッ", "と"],
    ])
    func keepsKatakanaWords(words: [String]) {
        #expect(!BrokenSpellings.isBroken(Self.engine(words)))
    }

    @Test("1 つの語・動詞の活用の促音・強めの接頭の語・漢字の続かない促音は除かない", arguments: [
        ["うっ血"], ["三ッ星"], ["引っ越し", "を"], ["引っ", "越し"], ["言っ", "た"], ["ぶっ", "飛ぶ"], ["ひっ", "越し"], ["とっ", "捕まえる"],
        ["ちょっと", "待っ", "て"], ["ちび", "っ子"], ["売れ", "っ子"], ["江戸", "っ子"],
    ])
    func keepsWords(words: [String]) {
        #expect(!BrokenSpellings.isBroken(Self.engine(words)))
    }

    @Test("語の区切りが分からない候補は文字で見る．漢字のすぐ後の送りがなの促音は当たらない")
    func fragmentedText() {
        #expect(BrokenSpellings.isBroken(Self.combined("はっ再の")))
        #expect(BrokenSpellings.isBroken(Self.combined("ジュっ分")))
        #expect(BrokenSpellings.isBroken(Self.combined("シュッ派つ")))
        // 先頭の語を選び直した候補は，その語の中の切れ目も見る(いっ＋本 に の をつないだもの)
        var head = Self.engine(["いっ", "本"], readingCount: 4)
        head.text = "いっ本"
        var combined = Self.combined("いっ本の", readingCount: 5)
        combined.learnedParts = [head]
        #expect(BrokenSpellings.isBroken(combined))
        var word = Candidate(text: "三ッ星", readingCount: 4, origin: .engine(id: 1), words: [Candidate.Word(text: "三ッ星", readingCount: 4)])
        word.text = "三ッ星"
        var star = Self.combined("三ッ星の", readingCount: 5)
        star.learnedParts = [word]
        #expect(!BrokenSpellings.isBroken(star))
        #expect(!BrokenSpellings.isBroken(Self.combined("開けっ放し")))
        #expect(!BrokenSpellings.isBroken(Self.combined("引っ越しを")))
        #expect(!BrokenSpellings.isBroken(Self.combined("ぶっ飛ぶ")))
    }

    @Test("エンジン以外の候補(ユーザー辞書の語・記号)は見ない")
    func ignoresNonEngineCandidates() {
        #expect(!BrokenSpellings.isBroken(Candidate(text: "はっ再", readingCount: 4, origin: .userDictionary)))
        #expect(!BrokenSpellings.isBroken(Candidate(text: "はッ制", readingCount: 4, origin: .symbol)))
    }

    @Test("第 1 候補は変えず，2 番目から後ろの崩れた候補を除く．ほかの候補の順は変えない")
    func cleaned() {
        let candidates = [
            Self.engine(["はっ", "再"]), Self.engine(["発", "再"]), Self.engine(["じゅっ", "分"]), Self.combined("じゅッぷん"),
            Self.engine(["寿", "っ", "分"]), Self.engine(["じゅっ"], readingCount: 3), Self.engine(["ジュップン"]),
        ]
        #expect(BrokenSpellings.cleaned(candidates).map(\.text) == ["はっ再", "発再", "寿っ分", "じゅっ", "ジュップン"])
    }

    @Test("拍の途中の字種の切り替え・小さいかなの位置・1 文字のカタカナを除く対象にする", arguments: [
        "とゥ", "しェ", "ねェさん", "シゃ", "ザッしを", "アッさり", "さボッた", "自ャ", "打ァ", "非ゃっぽ", "良ッた",
        "出発スる", "コの", "雑誌ヲ", "コども", "呼ぶヨ", "ホんがある", "8歳ノ", "えンピつを",
    ])
    func scriptBreaks(text: String) {
        #expect(BrokenSpellings.isBroken(Self.combined(text)))
    }

    @Test("ふつうの字の並びは除かない", arguments: [
        "3カ月", "三ケ所", "5ヶ月", "湯ノ沢", "霞ケ関", "一ツ橋", "ハ長調", "イ短調", "サッと", "ハッとする", "トムって", "ファイルを開く",
        "フランス語", "ちょっと", "シャツを着る", "ティーカップ", "ラ・マンチャ", "パンを食べる", "コーヒーを飲む", "三ッ星", "ノ", "ぁー",
    ])
    func keepsOrdinaryText(text: String) {
        #expect(!BrokenSpellings.isBroken(Self.combined(text)))
    }

    @Test("語末で前のかなの母音を伸ばす小さいカタカナは，伸ばす書き方として除かない", arguments: [
        "だよォ", "大丈夫だよォ", "どうしてるかなァ", "ねェ", "じゃァ", "さァ", "だァ", "そうだねェ！", "すごいィ",
    ])
    func keepsElongation(text: String) {
        #expect(!BrokenSpellings.isBroken(Self.combined(text)))
    }

    @Test("読みが促音で終わる数のすぐ後に，助数詞でない漢字の語が続く候補を除く対象にする", arguments: [
        [("8", "はっ"), ("精子", "せいし")], [("8", "はっ"), ("生", "せい")], [("1", "いっ"), ("緒", "しょ"), ("に", "に")],
        [("10", "じゅっ"), ("先", "せん")], [("６", "ろっ"), ("子", "こ")], [("6", "ろっ"), ("日", "ぴ"), ("機", "き")],
    ])
    func brokenNumbers(words: [(String, String)]) {
        #expect(BrokenSpellings.isBroken(Self.engine(words.map { (text: $0.0, reading: $0.1) })))
    }

    @Test("助数詞・読みが促音で終わらない数・漢字でない語は除かない", arguments: [
        [("8", "はっ"), ("本", "ほん")], [("1", "いっ"), ("分", "ぷん")], [("6", "ろっ"), ("匹", "ぴき")], [("10", "じゅっ"), ("回", "かい")],
        [("8", "はっ"), ("千", "せん")], [("1", "いっ"), ("体", "たい")], [("1", "いっ"), ("頁", "ぺーじ")], [("8", "はっ"), ("世", "せい")],
        [("第", "だい"), ("2", "に"), ("子", "し")], [("中", "ちゅう"), ("2", "に")], [("8", "はち"), ("精子", "せいし")],
        [("8", "はっ"), ("せいし", "せいし")], [("一", "いっ"), ("緒", "しょ")],
    ])
    func keepsNumbers(words: [(String, String)]) {
        #expect(!BrokenSpellings.isBroken(Self.engine(words.map { (text: $0.0, reading: $0.1) })))
    }

    @Test("漢字と促音で終わる語のすぐ後に，漢字で始まる語が続く候補を除く対象にする", arguments: [
        [("良っ", "いっ"), ("分", "ぷん")], [("好っ", "いっ"), ("分", "ぷん")], [("行っ", "いっ"), ("分", "ぷん")], [("言っ", "いっ"), ("時", "とき")],
    ])
    func brokenSokuonStems(words: [(String, String)]) {
        #expect(BrokenSpellings.isBroken(Self.engine(words.map { (text: $0.0, reading: $0.1) })))
    }

    @Test("1 つの語・促音のあとのかな・強めの接頭の語・数は，促音で終わる活用の形のあとの漢字に当たらない", arguments: [
        [("引っ越し", "ひっこし")], [("突っ込む", "つっこむ")], [("取っ手", "とって")], [("真っ赤", "まっか")], [("言っ", "いっ"), ("た", "た"), ("時", "とき")],
        [("引っ越", "ひっこ"), ("し", "し")], [("真っ", "まっ"), ("白", "しろ")], [("引っ", "ひっ"), ("越し", "こし")], [("突っ", "つっ"), ("張る", "ぱる")],
        [("取っ", "とっ"), ("組み", "くみ")], [("三っ", "みっ"), ("日", "か")],
    ])
    func keepsSokuonStems(words: [(String, String)]) {
        #expect(!BrokenSpellings.isBroken(Self.engine(words.map { (text: $0.0, reading: $0.1) })))
    }

    @Test("語をつないだ候補も，元の語の並びで数のあとの語を見る")
    func numbersInCombinedCandidates() {
        let number = Self.engine([(text: "8", reading: "はっ")])
        // 文節を替えた文(8｜精子た)．どの文節も語の並びが分かる
        var substituted = Self.combined("8精子た", readingCount: 6)
        substituted.learnedParts = [number, Self.engine([(text: "精子", reading: "せいし"), (text: "た", reading: "た")])]
        #expect(BrokenSpellings.isBroken(substituted))
        // 先頭の語を選び直した候補(8 に 精子 をつないだもの)．残りの語の読みは分からないので，字だけで助数詞かを見る
        var headWord = Self.combined("8精子", readingCount: 5)
        headWord.learnedParts = [number]
        #expect(BrokenSpellings.isBroken(headWord))
        var counter = Self.combined("8本の", readingCount: 4)
        counter.learnedParts = [number]
        #expect(!BrokenSpellings.isBroken(counter))
        // 語の並びが分からない候補は見ない
        #expect(!BrokenSpellings.isBroken(Self.combined("8精子")))
    }
}
