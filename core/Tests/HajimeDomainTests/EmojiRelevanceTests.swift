import HajimeDomain
import Testing

/// 読みで引いた絵文字が文節の語と合うか(R-26)．行は data/palette/palette.tsv の同じ絵文字の行(読みとキーワードは一部)
@Suite("絵文字と文節の語の照らし合わせ")
struct EmojiRelevanceTests {
    private static func item(_ text: String, name: String, readings: [String], keywords: [String]) -> PaletteItem {
        PaletteItem(kind: .emoji, category: .nature, text: text, japaneseName: name, readings: readings, keywords: keywords)
    }

    private static let wing = item("🪽", name: "翼", readings: ["つばさ", "はね", "そら"], keywords: ["翼", "天使", "空", "羽"])
    private static let jar = item("🫙", name: "瓶", readings: ["びん", "あきびん", "そら"], keywords: ["瓶", "空", "空き瓶"])
    private static let redHair = item("👨‍🦰", name: "男性: 赤毛", readings: ["あかげ", "かみ"], keywords: ["男性: 赤毛", "赤毛", "髪"])
    private static let orca = item("🫍", name: "シャチ", readings: ["しゃち", "うみ"], keywords: ["海", "海洋"])
    private static let frog = item("🐸", name: "カエルの顔", readings: ["かえる", "かえるのかお"], keywords: ["カエルの顔", "動物", "顔"])
    private static let cat = item("🐈", name: "ネコ", readings: ["ねこ", "ぺっと"], keywords: ["動物", "猫"])
    private static let grinningCat = item("😺", name: "にっこり笑う猫", readings: ["ねこ", "えがお"], keywords: ["にっこり笑う猫", "猫", "笑顔"])
    private static let spider = item("🕷️", name: "クモ", readings: ["くも", "むし"], keywords: ["虫"])
    private static let beer = item("🍺", name: "ビールジョッキ", readings: ["びーる", "じょっき"], keywords: ["お酒", "居酒屋"])
    private static let car = item("🚗", name: "自動車", readings: ["くるま", "じどうしゃ"], keywords: ["自動車", "乗り物", "車"])
    private static let martialArts = item("🥋", name: "武道", readings: ["ぶどう", "からて"], keywords: ["武道", "柔道"])
    private static let sushi = item("🍣", name: "すし", readings: ["すし"], keywords: ["お寿司", "寿司"])
    private static let smile = item("😄", name: "笑顔", readings: ["えがお"], keywords: ["笑顔", "顔"])

    private static func matches(_ item: PaletteItem, _ reading: String, _ text: String, noun: Bool = true) -> Bool {
        EmojiRelevance.matches(item, reading: reading, word: EmojiWord(text: text, isNoun: noun))
    }

    @Test("連想の読み(翼の「空」・空き瓶の「空」)や同じ読みの別の語(赤毛の「髪」と「紙」)では出さない")
    func unrelated() {
        #expect(!Self.matches(Self.wing, "そら", "空"))
        #expect(!Self.matches(Self.jar, "そら", "空"))
        #expect(!Self.matches(Self.redHair, "かみ", "紙"))
        #expect(!Self.matches(Self.redHair, "かみ", "神"))
        #expect(!Self.matches(Self.orca, "うみ", "海"))
        #expect(!Self.matches(Self.spider, "くも", "雲"))
        #expect(!Self.matches(Self.martialArts, "ぶどう", "ブドウ"))
    }

    @Test("文節の語が名前の語と違えば出さない(帰る → 🐸 は出さず，カエル → 🐸 は出す)")
    func firstCandidate() {
        #expect(!Self.matches(Self.frog, "かえる", "帰る", noun: false))
        #expect(Self.matches(Self.frog, "かえる", "カエル"))
    }

    @Test("名前そのもの・名前の語の境・キーワードで名前の中にある語・かなの名前の読みは出す", arguments: [
        ("😄", "えがお", "笑顔"), ("🍣", "すし", "すし"), ("😺", "ねこ", "猫"), ("🚗", "くるま", "車"), ("🐈", "ねこ", "猫"), ("🍺", "びーる", "ビール"),
    ])
    func related(text: String, reading: String, word: String) throws {
        let item = try #require([Self.smile, Self.sushi, Self.grinningCat, Self.car, Self.cat, Self.beer].first { $0.text == text })
        #expect(Self.matches(item, reading, word))
    }

    @Test("かなの語は名前のかなの語とひらがなにして比べる(くま → 🐻 クマの顔)")
    func kanaWord() {
        let bear = Self.item("🐻", name: "クマの顔", readings: ["くま"], keywords: ["クマの顔", "熊"])
        #expect(Self.matches(bear, "くま", "くま"))
        #expect(Self.matches(bear, "くま", "熊"))
        #expect(EmojiRelevance.isHiragana("ぶどう") && !EmojiRelevance.isHiragana("ブドウ") && !EmojiRelevance.isHiragana("桃"))
    }

    @Test("第 1 候補がひらがなのままなら，名前がそのひらがなの絵文字にだけ合わせる(みかん → 🍊．くも → 🕷️ クモ は出さない)")
    func hiraganaFirstCandidate() {
        let orange = Self.item("🍊", name: "みかん", readings: ["みかん"], keywords: ["果物"])
        #expect(EmojiRelevance.matches(orange, reading: "みかん", word: EmojiWord(text: "蜜柑", isNoun: true, hiraganaText: "みかん")))
        #expect(!EmojiRelevance.matches(Self.spider, reading: "くも", word: EmojiWord(text: "雲", isNoun: true, hiraganaText: "くも")))
    }

    @Test("かなの名前の読みで合わせるのは，名詞で，その語が絵文字のキーワードにあるときだけ")
    func kanaNameNeedsKeyword() {
        #expect(!Self.matches(Self.cat, "ねこ", "猫", noun: false))
        #expect(!Self.matches(Self.cat, "ねこ", "寝子"))
    }

    @Test("同じ読みの漢字の名前の絵文字には，カタカナの語だけでは合わせない(ブドウ → 🥋 武道 は出さない)")
    func katakanaHomophone() {
        let martialArts = PaletteItem(kind: .emoji, category: .activities, text: "🥋", japaneseName: "武道", nameReading: "ぶどう",
                                      readings: ["ぶどう"], keywords: ["武道"])
        #expect(!Self.matches(martialArts, "ぶどう", "ブドウ"))
        #expect(EmojiRelevance.containsKanji("帰る") && !EmojiRelevance.containsKanji("ウマ") && !EmojiRelevance.containsKanji("とり"))
    }

    @Test("語の境は字の種類の変わり目と記号．漢字の続きの途中では合わせない")
    func boundaries() {
        let airport = Self.item("🛫", name: "空港の出発", readings: ["そら"], keywords: ["出発"])
        #expect(!Self.matches(airport, "そら", "空"))
        #expect(EmojiRelevance.matches(Self.redHair, reading: "あかげ", word: EmojiWord(text: "赤毛", isNoun: true)))
    }
}
