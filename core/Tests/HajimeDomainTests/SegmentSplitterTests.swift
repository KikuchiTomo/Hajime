import HajimeDomain
import Testing

@Suite("文節を区切る位置")
struct SegmentSplitterTests {
    /// 読みごとの候補と語の並び．hajime-playground --split・--words で見た本物の変換器の結果を写したもの
    private struct Dictionary {
        var candidates: [String: [String]]
        var words: [String: [Candidate.Word]] = [:]

        func split(_ shown: String, _ reading: String) -> SegmentSplitter.Split {
            SegmentSplitter.split(
                shown: shown, reading: reading,
                candidates: { candidates[$0] ?? [$0] },
                words: { words[$0] ?? [Candidate.Word(text: $0, readingCount: $0.count)] })
        }
    }

    private static func particle(_ text: String) -> Candidate.Word {
        Candidate.Word(text: text, readingCount: text.count, startsWithParticle: true, endsWithParticle: true)
    }

    private static func predicate(_ text: String, readingCount: Int) -> Candidate.Word {
        Candidate.Word(text: text, readingCount: readingCount, startsWithPredicate: true)
    }

    @Test("左と右の候補をつなげて見えている字になる位置で切る(「問題｜が｜ある」)")
    func cutsWhereBothSidesConvert() {
        let dictionary = Dictionary(
            candidates: ["もんだい": ["問題"], "がある": ["がある"], "もんだいが": ["問題が"], "ある": ["ある", "或る"]],
            words: ["ある": [Self.predicate("ある", readingCount: 2)], "がある": [Self.particle("が"), Self.predicate("ある", readingCount: 2)],
                    "もんだいが": [Candidate.Word(text: "問題", readingCount: 4), Self.particle("が")]]
        )
        let split = dictionary.split("問題がある", "もんだいがある")
        #expect(split.pieces == ["問題", "が", "ある"])
        #expect(split.positions == [4, 5])
    }

    @Test("語の頭に来ない字(「ん」「っ」，小さいかな，長音)の前では切らない(「ウブ｜ンツ」「初｜んつ」)")
    func keepsNonInitialCharacters() {
        let dictionary = Dictionary(candidates: ["うぶ": ["ウブ", "初"], "んつ": ["ンツ", "んつ"]])
        #expect(dictionary.split("ウブンツ", "うぶんつ").pieces == ["ウブンツ"])
        #expect(dictionary.split("初んつ", "うぶんつ").pieces == ["初んつ"])
    }

    @Test("ひらがなどうしは，助詞の前後の語の切れ目だけで切る(「ある｜と」．「あ｜る」は切らない)")
    func hiraganaNeedsParticle() {
        let dictionary = Dictionary(
            candidates: ["あ": ["あ"], "るとおもう": ["ると思う"], "ある": ["ある"], "とおもう": ["と思う"], "あると": ["あると"], "おもう": ["思う"]],
            words: ["ある": [Self.predicate("ある", readingCount: 2)], "とおもう": [Self.particle("と"), Self.predicate("思う", readingCount: 3)],
                    "あると": [Self.predicate("ある", readingCount: 2), Self.particle("と")], "おもう": [Self.predicate("思う", readingCount: 3)]]
        )
        #expect(dictionary.split("あると思う", "あるとおもう").pieces == ["ある", "と", "思う"])
    }

    @Test("活用した形に付く助詞の前(「読ん｜で」)と，文の終わりの助詞のあと(「わ｜から」)では切らない")
    func conjugationStaysTogether() {
        let conjunctive = Candidate.Word(text: "で", readingCount: 1, startsWithParticle: true, endsWithParticle: true, startsWithConjunctiveParticle: true)
        let reading = Dictionary(
            candidates: ["よん": ["読ん"], "でください": ["でください"]],
            words: ["よん": [Self.predicate("読ん", readingCount: 2)], "でください": [conjunctive]]
        )
        #expect(reading.split("読んでください", "よんでください").positions.isEmpty)
        let final = Candidate.Word(text: "わ", readingCount: 1, startsWithParticle: true, endsWithParticle: true, endsWithSentenceFinalParticle: true)
        let understand = Dictionary(
            candidates: ["わ": ["わ"], "からない": ["からない"]],
            words: ["わ": [final], "からない": [Self.predicate("駆ら", readingCount: 2)]]
        )
        #expect(understand.split("わからない", "わからない").positions.isEmpty)
    }

    @Test("カタカナどうし(「ログ｜アウト」)，漢字 1 字と漢字(「天｜気」)，送り仮名(「飲｜む」)，頭の接頭語(「お｜茶」)では切らない")
    func keepsWords() {
        let dictionary = Dictionary(candidates: [
            "ろぐ": ["ログ"], "あうと": ["アウト"], "てん": ["天"], "き": ["気"], "の": ["飲"], "む": ["む"], "お": ["お"], "ちゃ": ["茶"],
        ])
        #expect(dictionary.split("ログアウト", "ろぐあうと").positions.isEmpty)
        #expect(dictionary.split("天気", "てんき").positions.isEmpty)
        #expect(dictionary.split("飲む", "のむ").positions.isEmpty)
        #expect(dictionary.split("お茶", "おちゃ").positions.isEmpty)
    }

    @Test("漢字 2 字以上どうしは切る(「運転｜免許」)")
    func splitsCompounds() {
        let dictionary = Dictionary(candidates: ["うんてん": ["運転"], "めんきょ": ["免許"]])
        #expect(dictionary.split("運転免許", "うんてんめんきょ").pieces == ["運転", "免許"])
    }

    @Test("区切れる位置は 9 個まで．あとは最後にまとめる")
    func atMostNine() {
        let shown = String(repeating: "亜亜ア", count: 11)
        let reading = String(repeating: "ああア", count: 11)
        // どの位置でも，読みのままの字が候補になる(漢字 2 字とカタカナのあいだで切れる)
        var candidates: [String: [String]] = [:]
        let characters = Array(reading), text = Array(shown)
        for start in 0..<characters.count {
            for end in (start + 1)...characters.count {
                candidates[String(characters[start..<end])] = [String(text[start..<end])]
            }
        }
        let split = Dictionary(candidates: candidates).split(shown, reading)
        #expect(split.positions.count == 9)
        #expect(split.pieces.count == 10)
        #expect(split.pieces.joined() == shown)
    }
}
