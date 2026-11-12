import Foundation
import Testing
@testable import HajimeDomain

@Suite("あいまいな照合")
struct FuzzyMatchTests {
    private func match(_ pattern: String, _ text: String) -> FuzzyMatch.Match? {
        FuzzyMatch.match(FuzzyMatch.normalized(pattern), in: FuzzyMatch.normalized(text))
    }

    @Test("当たり方を強い順に見分ける", arguments: [
        ("bow", "bow", FuzzyMatch.Kind.exact),
        ("thumbs", "thumbsup", .prefix),
        ("joy", "face with tears of joy", .wordPrefix),
        ("sup", "thumbsup", .substring),
        ("tsup", "thumbsup", .scattered),
        ("ネコ", "ねこ", .exact),
    ])
    func kinds(pattern: String, text: String, kind: FuzzyMatch.Kind) {
        #expect(match(pattern, text)?.kind == kind)
    }

    @Test("順に含まない語には当たらない")
    func noMatch() {
        #expect(match("upt", "thumbsup") == nil)
        #expect(match("longer", "long") == nil)
        #expect(match("", "bow") == nil)
    }

    @Test("続いた文字と語の頭の当たりを，散らばった当たりより高くする")
    func scores() throws {
        let consecutive = try #require(match("ok", "ok hand"))
        let scattered = try #require(match("ok", "folk"))
        #expect(consecutive.score > scattered.score)
        let boundary = try #require(match("hand", "ok hand"))
        let inside = try #require(match("and", "ok hand"))
        #expect(boundary.score > inside.score)
    }
}

@Suite("パレットの表と検索")
struct PaletteSearchTests {
    private static let sample = """
        # 注記
        emoji\tsmileys\t😂\t0.6\t嬉し泣き\tうれしなき\tface with tears of joy\tうれしなき|わらい\t嬉し泣き|joy|laugh\tjoy\t
        emoji\tpeople\t🙇\t0.6\tおじぎする人\tおじぎするひと\tperson bowing\tおじぎ|ごめんなさい\t謝罪|apology|bow\tbow\t🙇🏻|🙇🏼|🙇🏽|🙇🏾|🙇🏿
        emoji\tpeople\t👍\t0.6\tサムズアップ\tさむずあっぷ\tthumbs up\tいいね|さむずあっぷ\t+1|good|like\t+1|thumbsup\t👍🏻|👍🏼|👍🏽|👍🏾|👍🏿
        emoji\tnature\t🐱\t0.6\tネコの顔\tねこのかお\tcat face\tねこ|ねこのかお\t猫|cat\tcat\t
        emoji\tnature\t🐈\t0.7\tネコ\tねこ\tcat\tねこ\t猫|pet\tcat2\t
        emoji\tactivities\t🎳\t0.6\tボウリング\tぼうりんぐ\tbowling\tぼうりんぐ\tball|game\tbowling\t
        emoji\tobjects\t🫟\t16.0\t飛び散り\tとびちり\tsplatter\tとびちり\tsplatter\tsplatter\t
        symbol\tarrows\t→\t\t右向矢印\tみぎむきやじるし\trightwards arrow\tみぎ|やじるし\t右|arrow\t\t
        symbol\tenclosed\t①\t\t丸数字1\tまるいち\tcircled digit one\tまるいち|いち\tcircled digit one\t\t
        symbol\tunknown\t?\t\t\t\t\t\t\t\t
        壊れた行
        """

    private let catalog = PaletteCatalog(text: sample)

    private func texts(_ typed: String, kana: String = "", ranking: PaletteSearch.Ranking = .init()) -> [String] {
        PaletteSearch(catalog: catalog).search(PaletteSearch.Query(typed: typed, kana: kana), ranking: ranking).map(\.text)
    }

    @Test("表を読み，形の合わない行と知らないまとまりの行を飛ばす")
    func parse() throws {
        #expect(catalog.items.map(\.text) == ["😂", "🙇", "👍", "🐱", "🐈", "🎳", "🫟", "→", "①"])
        let bowing = try #require(catalog.item(for: "🙇🏽"))
        #expect(bowing.text == "🙇")
        #expect(bowing.nameReading == "おじぎするひと")
        #expect(bowing.text(skinTone: .medium) == "🙇🏽")
        #expect(bowing.text(skinTone: .none) == "🙇")
        #expect(catalog.items[0].text(skinTone: .dark) == "😂")
        #expect(catalog.categories == [.smileys, .people, .nature, .activities, .objects, .arrows, .enclosed])
    }

    @Test("変換に足す絵文字は読みと同じ読みの絵文字だけ．名前の読みで当たったものを先にし，記号と前方一致は出さない")
    func emojiForReading() {
        let search = PaletteSearch(catalog: catalog)
        #expect(search.emoji(reading: "ねこ", limit: 5).map(\.text) == ["🐈", "🐱"])
        #expect(search.emoji(reading: "ネコ", limit: 5).map(\.text) == ["🐈", "🐱"])
        #expect(search.emoji(reading: "ね", limit: 5).isEmpty)
        #expect(search.emoji(reading: "ねこのか", limit: 5).isEmpty)
        #expect(search.emoji(reading: "やじるし", limit: 5).isEmpty)
        #expect(search.emoji(reading: "ねこ", limit: 1).map(\.text) == ["🐈"])
        #expect(search.emoji(reading: "ねこ", limit: 0).isEmpty)
    }

    @Test("同じ意味の語の一覧の絵文字は，名前と合わなくても出し，名前で合ったものより先にする．何度も選んだものはさらに先")
    func emojiSynonyms() {
        let synonyms = EmojiSynonyms(text: "ネコ\tねこ\t🐱\n猫\tねこ\t🐱 🎳 ❓")
        let search = PaletteSearch(catalog: catalog, synonyms: synonyms)
        let word = EmojiWord(text: "猫", isNoun: true)
        #expect(search.emoji(reading: "ねこ", word: EmojiWord(text: "寝子", isNoun: true), limit: 5).isEmpty)
        #expect(search.emoji(reading: "ねこ", word: word, limit: 5).map(\.text) == ["🐱", "🎳", "🐈"])
        #expect(search.emoji(reading: "ねこ", word: word, ranking: .init(learned: ["🐈"]), limit: 1).map(\.text) == ["🐈"])
        #expect(search.emoji(reading: "いぬ", word: word, limit: 5).isEmpty)
    }

    @Test("変換に足す絵文字は，その読みで何度も選んだものとよく使うものを先にする")
    func emojiForReadingRanking() {
        let search = PaletteSearch(catalog: catalog)
        #expect(search.emoji(reading: "ねこ", ranking: .init(learned: ["🐱"]), limit: 5).map(\.text) == ["🐱", "🐈"])
        #expect(search.emoji(reading: "ねこ", ranking: .init(usage: ["🐱": 3]), limit: 5).map(\.text) == ["🐱", "🐈"])
    }

    @Test("ショートコード・英語の名前・読みのどれでも探せる", arguments: [
        (":bow:", "", "🙇"),
        (":+1", "", "👍"),
        ("joy", "", "😂"),
        ("ojigi", "おじぎ", "🙇"),
        ("tumbsup", "", "👍"),
        ("", "やじるし", "→"),
        ("", "まるいち", "①"),
    ])
    func finds(typed: String, kana: String, expected: String) {
        #expect(texts(typed, kana: kana).first == expected)
    }

    @Test("「:」で始めたらショートコードだけを探す")
    func shortcodeOnly() {
        #expect(texts(":cat") == ["🐱", "🐈"])
        // 名前の「face」には当てない
        #expect(texts(":face").isEmpty)
        #expect(texts(":").isEmpty)
    }

    @Test("飛び飛びの当たりは，英数字を 3 文字以上打ったときだけ出す")
    func scatteredNeedsThreeLetters() {
        #expect(texts("tsup") == ["👍"])
        #expect(texts("tp").isEmpty)
    }

    @Test("名前で当たった項目を，ほかの読みで当たった項目より先にする")
    func nameFirst() {
        // 🐈 は名前が「ネコ」，🐱 は読みの 1 つが「ねこ」
        #expect(texts("", kana: "ねこ") == ["🐈", "🐱"])
    }

    @Test("同じ段の中では，よく使う項目とピン留めした項目を先にする．強い段より先にはしない")
    func usageOrdersWithinTier() {
        #expect(texts("", kana: "ねこ", ranking: .init(usage: ["🐱": 3])) == ["🐱", "🐈"])
        #expect(texts("", kana: "ねこ", ranking: .init(pinned: ["🐱"])) == ["🐱", "🐈"])
        // 🎳 は「bow」の頭からの当たり，🙇 はショートコードと同じ．どれだけ使っても段は越えない
        #expect(texts("bow", ranking: .init(usage: ["🎳": 10_000])) == ["🙇", "🎳"])
    }

    @Test("同じ語で前に何度も選んだ項目は，同じ当たりとして先頭に出す")
    func learnedChoices() {
        #expect(texts("bo").first == "🙇")
        #expect(texts("bo", ranking: .init(learned: ["🎳"])).first == "🎳")
    }

    @Test("点が同じなら，今見ているパレットの種類を先にする")
    func preferredKind() {
        let catalog = PaletteCatalog(text: """
            emoji\tsymbols\t❤️\t0.6\t赤いハート\tあかいはーと\tred heart\tはーと\t\theart\t
            symbol\tshapes\t♡\t\t白いハート\tしろいはーと\twhite heart\tはーと\t\t\t
            """)
        let search = PaletteSearch(catalog: catalog)
        #expect(search.search(PaletteSearch.Query(typed: "", kana: "はーと")).map(\.text) == ["❤️", "♡"])
        #expect(search.search(PaletteSearch.Query(typed: "", kana: "はーと"), ranking: .init(preferredKind: .symbol)).map(\.text) == ["♡", "❤️"])
    }

    @Test("記号に，読みから引く記号の辞書の読みを足す")
    func addingReadings() {
        let extended = catalog.addingReadings([(reading: "ならば", symbols: ["→"]), (reading: "えがお", symbols: ["😂"])])
        let search = PaletteSearch(catalog: extended)
        #expect(search.search(PaletteSearch.Query(typed: "", kana: "ならば")).map(\.text) == ["→"])
        // 絵文字には足さない
        #expect(search.search(PaletteSearch.Query(typed: "", kana: "えがお")).isEmpty)
    }

    @Test("OS が描けるバージョンまでの絵文字に絞る．記号は残す")
    func limitedByVersion() throws {
        let limited = catalog.limited(to: try #require(EmojiVersion("15.1")))
        #expect(!limited.items.contains { $0.text == "🫟" })
        #expect(limited.items.contains { $0.text == "→" })
        #expect(catalog.versionSamples.map(\.version.description) == ["0.6", "0.7", "16.0"])
    }
}

@Suite("同梱のパレットの表")
struct BundledPaletteTests {
    /// リポジトリの data/palette/palette.tsv
    private static let catalog: PaletteCatalog = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("data/palette/palette.tsv")
        return PaletteCatalog(text: (try? String(contentsOf: url, encoding: .utf8)) ?? "")
    }()

    @Test("絵文字・記号・顔文字のすべてのまとまりを読む")
    func everyCategory() {
        #expect(Self.catalog.items.count > 3000)
        #expect(Self.catalog.categories == PaletteCategory.allCases)
        // 顔文字は 4 文字を超えるものも読む．どれにも名前と読みがある
        let kaomoji = Self.catalog.items.filter { $0.kind == .kaomoji }
        #expect(kaomoji.count > 400)
        #expect(kaomoji.contains { $0.text.count > DefaultSettings.maximumPaletteTextLength })
        #expect(kaomoji.allSatisfy { !$0.japaneseName.isEmpty && !$0.readings.isEmpty })
    }

    @Test("R-26: 名前を定めたところを読む．絵文字は CLDR，記号は CLDR か Hajime IME，顔文字は無し")
    func nameSources() throws {
        let items = Self.catalog.items
        #expect(items.filter { $0.kind == .emoji }.allSatisfy { $0.nameSource == .cldr })
        #expect(items.filter { $0.kind == .kaomoji }.allSatisfy { $0.nameSource == nil })
        #expect(try #require(Self.catalog.item(for: "，")).nameSource == .cldr)
        #expect(try #require(Self.catalog.item(for: "①")).nameSource == .hajime)
        // 名前のある記号には，どれにも出どころがある
        #expect(items.filter { $0.kind == .symbol && !$0.japaneseName.isEmpty }.allSatisfy { $0.nameSource != nil })
    }

    @Test("マスの形を渡すと，その形の種類だけを探す")
    func searchByShape() {
        let search = PaletteSearch(catalog: Self.catalog)
        let query = PaletteSearch.Query(typed: "", kana: "おじぎ")
        let wide = search.search(query, shape: .wide)
        #expect(!wide.isEmpty)
        #expect(wide.allSatisfy { $0.kind == .kaomoji })
        let square = search.search(query, shape: .square)
        #expect(square.first?.text == "🙇")
        #expect(!square.contains { $0.kind == .kaomoji })
    }

    @Test("顔文字の読みで，目当ての顔文字が先頭に来る", arguments: [
        ("しょぼーん", "(´・ω・｀)"),
        ("ぺこり", "m(_ _)m"),
        ("しくしく", "(T_T)"),
    ])
    func findsKaomoji(kana: String, expected: String) {
        let results = PaletteSearch(catalog: Self.catalog).search(PaletteSearch.Query(typed: "", kana: kana), shape: .wide)
        #expect(results.first?.text == expected)
    }

    @Test("よく探す語で，目当ての文字が先頭に来る", arguments: [
        (":bow:", "", "🙇"),
        (":joy:", "", "😂"),
        (":+1:", "", "👍"),
        ("ojigi", "おじぎ", "🙇"),
        ("neko", "ねこ", "🐈"),
        (":cat:", "", "🐱"),
        ("thumbsup", "", "👍"),
        ("", "こめじるし", "※"),
        ("", "ゆうびん", "〒"),
        ("", "まるいち", "①"),
        ("", "あるふぁ", "α"),
        ("", "せっし", "℃"),
    ])
    func finds(typed: String, kana: String, expected: String) {
        let results = PaletteSearch(catalog: Self.catalog).search(PaletteSearch.Query(typed: typed, kana: kana))
        #expect(results.first?.text == expected)
    }

    @Test("表のすべての絵文字を描けるか確かめる見本を，バージョンごとに 1 つ選ぶ")
    func versionSamples() {
        let samples = Self.catalog.versionSamples
        #expect(samples.count >= 15)
        #expect(samples.map(\.version) == samples.map(\.version).sorted())
    }
}
