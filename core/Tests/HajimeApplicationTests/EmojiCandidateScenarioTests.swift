import Foundation
import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

/// 読みで引いた絵文字を変換したときの候補に足す(設定の「文節を絵文字に変換」「語を絵文字に変換」)．第 1 候補にはせず，
/// 分岐図の見えている枝と一覧の 1 ページ目に入る位置にまとめて置く(EmojiPlacement)．打っているあいだの表示と入力中の候補の窓には出さない
@MainActor
@Suite("絵文字の候補")
struct EmojiCandidateScenarioTests {
    /// 「ねこ」の変換．エンジンの辞書の絵文字(🐱)も混ぜておく
    private func converter() -> FakeConverter {
        FakeConverter(["ねこ": [("猫", nil), ("ねこ", nil), ("ネコ", nil), ("🐱", nil), ("根子", nil), ("音子", nil), ("値子", nil), ("子子", nil)]])
    }

    private let emoji = FakeEmoji(["ねこ": ["🐈", "😺", "😸"], "なく": ["😢", "😭", "🐦"], "は": ["🦷", "🌿"]], names: ["🐈": "ネコ"])

    /// 位置を 3 番目，数を 2 にした設定(既定の値に左右されずに位置を確かめるため)
    private func settings(_ change: (inout Settings) -> Void = { _ in }) -> Settings {
        var settings = DefaultSettings.settings
        settings.emojiCandidatePosition = 3
        settings.emojiCandidateCount = 2
        change(&settings)
        return settings
    }

    private func harness(_ settings: Settings, converter: FakeConverter? = nil) -> Harness {
        let emoji = emoji
        return Harness(converter: converter ?? self.converter(), settings: settings,
                       wrap: { SupplementedConverter($0, settings: $1, calendar: FakeCalendar(), emoji: emoji) })
    }

    private func supplemented(_ settings: Settings, converter: FakeConverter? = nil) -> SupplementedConverter {
        SupplementedConverter(converter ?? self.converter(), settings: FakeSettings(settings), calendar: FakeCalendar(), emoji: emoji)
    }

    @Test("読みで引いた絵文字を設定の位置にまとめ，数を設定で抑える．エンジンの辞書の絵文字は除く")
    func placesLookedUpEmoji() {
        let candidates = supplemented(settings()).listCandidates(for: "ねこ")
        #expect(candidates.map(\.text) == ["猫", "ねこ", "🐈", "😺", "ネコ", "根子", "音子", "値子", "子子"])
        #expect(candidates.filter { $0.origin == .emoji }.map(\.text) == ["🐈", "😺"])
        let moved = supplemented(settings { $0.emojiCandidatePosition = 5; $0.emojiCandidateCount = 3 }).listCandidates(for: "ねこ")
        #expect(moved.map(\.text).prefix(7) == ["猫", "ねこ", "ネコ", "根子", "🐈", "😺", "😸"])
    }

    @Test("設定を切ると絵文字を出さない．エンジンの辞書の絵文字も出さない")
    func settingOff() {
        let candidates = supplemented(settings { $0.emojiConversion = false; $0.emojiWordConversion = false }).listCandidates(for: "ねこ").map(\.text)
        #expect(!candidates.contains { EmojiPlacement.containsEmoji($0) })
    }

    @Test("打っているあいだに求める候補(ライブ変換の文字)には絵文字を出さない．エンジンの辞書の絵文字が学習で先頭に来ても出さない")
    func noEmojiWhileTyping() {
        let converter = FakeConverter(["ねこ": [("🐱", nil), ("猫", nil), ("ねこ", nil)]])
        #expect(supplemented(settings(), converter: converter).candidates(for: "ねこ").map(\.text) == ["猫", "ねこ"])
        converter.predictionTexts["ねこ"] = ["🐱", "猫カフェ"]
        #expect(supplemented(settings(), converter: converter).predictions(for: "ねこ").map(\.text) == ["猫カフェ"])
        let harness = harness(settings { $0.liveConversionSkipLength = 0 }, converter: converter)
        harness.type("neko")
        harness.settle()
        #expect(harness.marked.text == "猫")
    }

    @Test("ユーザー辞書に登録した絵文字は先頭に残す")
    func keepsUserDictionaryEmoji() {
        let candidates = supplemented(settings { $0.userDictionary = [UserDictionaryEntry(reading: "ねこ", word: "🐱")] }).candidates(for: "ねこ")
        #expect(candidates.first?.text == "🐱")
        #expect(candidates.first?.origin == .userDictionary)
    }

    @Test("1 文字の読み(助詞や語の切れ端)には絵文字を出さない")
    func skipsSingleCharacterReading() {
        let converter = FakeConverter(["は": [("は", nil), ("歯", nil), ("葉", nil), ("派", nil)]])
        #expect(!supplemented(settings(), converter: converter).candidates(for: "は").contains { $0.origin == .emoji })
    }

    @Test("エンジンが候補を出さない読みでも，絵文字を第 1 候補にしない")
    func neverFirstWithoutOtherCandidates() {
        let candidates = supplemented(settings(), converter: FakeConverter()).listCandidates(for: "なく").map(\.text)
        #expect(candidates == ["なく", "😢", "😭"])
    }

    @Test("分岐図の見えている枝に絵文字を出し，前後の文脈で並べ替えても押し下げない", arguments: [true, false])
    func latticeShowsEmoji(contextual: Bool) {
        let harness = harness(settings { $0.contextualSegmentCandidates = contextual })
        harness.type("neko")
        harness.press(.space)
        // 上の枝(ねこ・ネコ)は下の枝に重ねない
        #expect(harness.focusedAlternatives == ["猫", "根子", "🐈", "😺", "音子"])
    }

    @Test("文節ごとの一覧と文全体の一覧でも，1 ページ目の同じ位置に出す", arguments: [CandidatePresentation.segmentList, .list])
    func listShowsEmoji(presentation: CandidatePresentation) {
        let harness = harness(settings { $0.candidatePresentation = presentation })
        harness.type("neko")
        harness.press(.space)
        if presentation == .list { harness.press(.down) }
        let entries = harness.panel?.entries.map(\.text) ?? []
        #expect(entries.firstIndex(of: "🐈") == 2)
        #expect(entries.firstIndex(of: "😺") == 3)
        #expect(!entries.contains("😸"))
    }

    @Test("入力中の候補の窓には出さず，Space で変換したあとの候補には 4 番目から出す")
    func suggestionWindowHasNoEmoji() {
        let harness = harness(settings { $0.liveConversion = false; $0.emojiCandidatePosition = DefaultSettings.emojiCandidatePosition })
        harness.type("neko")
        #expect(harness.panel?.entries.isEmpty == false)
        #expect(harness.panel?.entries.contains { EmojiPlacement.containsEmoji($0.text) } == false)
        harness.press(.space)
        #expect(harness.focusedAlternatives?.firstIndex(of: "🐈") == DefaultSettings.emojiCandidatePosition - 1)
    }

    @Test("最後の文節の入力中の候補の窓にも，語を絵文字にした候補を出さない")
    func suggestionWindowForLastClause() {
        let harness = harness(settings { $0.liveConversion = false }, converter: sentenceConverter())
        harness.type("shiroinekoga")
        #expect(harness.panel?.entries.contains { EmojiPlacement.containsEmoji($0.text) } == false)
    }

    @Test("文の途中の文節でも，文節の読みが絵文字の読みと同じなら出す．文全体の候補から文節の字を前に集めても押し下げない")
    func midSentenceSegment() {
        // 文全体の候補の「ねこ」の範囲の字(寝子・禰子・眠子)は文節の候補に無いので，前後の文脈で並べるときに前に足される
        let others = ["猫", "寝子", "禰子", "眠子"]
        let converter = FakeConverter([
            "しろいねこ": others.map { ("白い" + $0, nil) },
            "しろい": [("白い", nil)],
            "ねこ": [("猫", nil), ("根子", nil), ("音子", nil)],
        ])
        converter.words["しろいねこ"] = [Candidate.Word(text: "白い", readingCount: 3), Candidate.Word(text: "猫", readingCount: 2)]
        for text in others {
            converter.candidateWords["白い" + text] = [Candidate.Word(text: "白い", readingCount: 3), Candidate.Word(text: text, readingCount: 2)]
        }
        let harness = harness(settings { $0.initialFocus = .start }, converter: converter)
        harness.type("shiroineko")
        harness.press(.space)
        #expect(harness.marked.segments.map(\.text) == ["白い", "猫"])
        #expect(harness.focusedAlternatives?.contains("🐈") == false)
        harness.press(.right)
        #expect(harness.focusedAlternatives?.firstIndex(of: "🐈") == 2)
    }

    @Test("絵文字の候補の横に名前を添え，絵文字を選んでも語の意味のカードは開かない")
    func namesBesideEmoji() {
        let harness = harness(settings())
        harness.type("neko")
        harness.press(.space)
        let column = harness.lattice?.columns.first(where: \.isFocused)
        #expect(column?.alternatives == ["猫", "根子", "🐈", "😺", "音子"])
        // 名前を知らない絵文字(😺)には添えない
        #expect(column?.alternativeDetails == [nil, nil, "ネコ", nil, nil])
        harness.press(.down)
        harness.press(.down)
        let selected = harness.lattice?.columns.first(where: \.isFocused)
        #expect(selected?.text == "🐈")
        #expect(selected?.homophone == nil)
    }

    @Test("一覧と入力中の候補の窓でも，絵文字の候補の横に名前を添える", arguments: [CandidatePresentation.segmentList, .list])
    func namesInLists(presentation: CandidatePresentation) {
        let harness = harness(settings { $0.candidatePresentation = presentation })
        harness.type("neko")
        harness.press(.space)
        if presentation == .list { harness.press(.down) }
        let entries = harness.panel?.entries ?? []
        #expect(entries.first { $0.text == "🐈" }?.detail == "ネコ")
        #expect(entries.filter { $0.text != "🐈" }.allSatisfy { $0.detail == nil })
        #expect(harness.panel?.homophone == nil)
    }

    @Test("名前を表示しない設定では添えない")
    func namesOff() {
        let harness = harness(settings { $0.showsEmojiNames = false })
        harness.type("neko")
        harness.press(.space)
        #expect(harness.lattice?.columns.first(where: \.isFocused)?.alternativeDetails == [])
        let list = self.harness(settings { $0.showsEmojiNames = false; $0.candidatePresentation = .segmentList })
        list.type("neko")
        list.press(.space)
        #expect(list.panel?.entries.allSatisfy { $0.detail == nil } == true)
    }

    @Test("確定した絵文字は，その読みで選んだことを伝える")
    func commitRecordsReading() {
        let harness = harness(settings())
        harness.type("neko")
        harness.press(.space)
        harness.press(.down)
        harness.press(.down)
        harness.press(.enter)
        #expect(harness.committed == "🐈")
        #expect(emoji.committed.map(\.emoji) == ["🐈"])
        #expect(emoji.committed.map(\.reading) == ["ねこ"])
    }

    @Test("学習を使わずに変換しているあいだは，選んだ絵文字を伝えない")
    func suspendedLearning() {
        let converter = supplemented(settings())
        let candidate = converter.listCandidates(for: "ねこ").first { $0.origin == .emoji }!
        converter.suspendLearningUntilEnd()
        converter.didCommit(candidate)
        #expect(emoji.committed.isEmpty)
        converter.endComposition()
        let again = converter.listCandidates(for: "ねこ").first { $0.origin == .emoji }!
        converter.didCommit(again)
        #expect(emoji.committed.map(\.reading) == ["ねこ"])
    }

    // MARK: 文節の中の語を絵文字にする(「ねこが」→「🐈が」)

    private static let noun = { (text: String, count: Int) in Candidate.Word(text: text, readingCount: count, startsWithNoun: true) }
    private static let particle = { (text: String) in
        Candidate.Word(text: text, readingCount: text.count, startsWithParticle: true, endsWithParticle: true, isFunctionWord: true)
    }

    /// 「白い｜猫が」に分かれる変換器．「ねこが」は辞書の 1 語(名詞と助詞をつないだ語)，「ねこがかわいい」は後ろに自立語がある
    private func sentenceConverter() -> FakeConverter {
        let converter = FakeConverter([
            "しろいねこが": [("白い猫が", nil)],
            "しろい": [("白い", nil)],
            "ねこが": [("猫が", nil), ("根子が", nil), ("音子が", nil), ("値子が", nil)],
            "ねこ": [("猫", nil), ("🐱", nil), ("根子", nil)],
            "ねこがかわいい": [("猫が可愛い", nil), ("猫がかわいい", nil)],
        ])
        converter.words["しろいねこが"] = [Candidate.Word(text: "白い", readingCount: 3, startsWithPredicate: true), Self.noun("猫", 2), Self.particle("が")]
        converter.candidateWords["白い猫が"] = converter.words["しろいねこが"]
        // 辞書には名詞と助詞をつないだ語(猫が)もあるので，語の並びの切れ目ではなく読みを切って確かめる
        converter.words["ねこが"] = [Candidate.Word(text: "猫が", readingCount: 3, endsWithParticle: true, startsWithNoun: true)]
        converter.words["ねこ"] = [Self.noun("猫", 2)]
        converter.words["が"] = [Self.particle("が")]
        converter.words["ねこがかわいい"] = [Self.noun("猫", 2), Candidate.Word(text: "が可愛い", readingCount: 5, startsWithParticle: true)]
        converter.words["がかわいい"] = [Candidate.Word(text: "が可愛い", readingCount: 5, startsWithParticle: true)]
        return converter
    }

    @Test("文節が絵文字にできる語と助詞でできていれば，語を絵文字にして助詞を付けた候補を出す．名前は元の絵文字のもの")
    func wordEmoji() {
        let harness = harness(settings { $0.initialFocus = .start }, converter: sentenceConverter())
        harness.type("shiroinekoga")
        harness.press(.space)
        harness.press(.right)
        let column = harness.lattice?.columns.first(where: \.isFocused)
        #expect(column?.alternatives.firstIndex(of: "🐈が") == 2)
        #expect(column?.alternatives.firstIndex(of: "😺が") == 3)
        #expect(column?.alternativeDetails.first { $0 != nil } == "ネコ")
        // 辞書の絵文字の語(🐱)を先頭の語にした候補は出さない
        #expect(column?.alternatives.contains("🐱が") == false)
        harness.press(.down)
        harness.press(.down)
        harness.press(.enter)
        #expect(harness.committed == "白い🐈が")
        #expect(emoji.committed.map(\.emoji) == ["🐈"])
        #expect(emoji.committed.map(\.reading) == ["ねこ"])
    }

    @Test("文節の後ろに自立語があるときは，語を絵文字にした候補を出さない")
    func wordEmojiNeedsOnlyFunctionWords() {
        let candidates = supplemented(settings(), converter: sentenceConverter()).listCandidates(for: "ねこがかわいい").map(\.text)
        #expect(!candidates.contains { EmojiPlacement.containsEmoji($0) })
    }

    @Test("絵文字は文節の第 1 候補の語と名詞かを添えて引く(帰る → 🐸 を出さないため．照らし合わせは EmojiRelevance)")
    func passesFirstCandidate() {
        let emoji = FakeEmoji(["かえる": ["🐸"], "ねこ": ["🐈"]])
        let converter = FakeConverter(["かえる": [("帰る", nil), ("変える", nil)], "ねこ": [("猫", nil), ("ねこ", nil)]])
        converter.words["かえる"] = [Candidate.Word(text: "帰る", readingCount: 3, startsWithPredicate: true)]
        converter.words["ねこ"] = [Candidate.Word(text: "猫", readingCount: 2, startsWithNoun: true)]
        let supplemented = SupplementedConverter(converter, settings: FakeSettings(settings()), calendar: FakeCalendar(), emoji: emoji)
        _ = supplemented.listCandidates(for: "かえる")
        _ = supplemented.listCandidates(for: "ねこ")
        #expect(emoji.words["かえる"] == EmojiWord(text: "帰る", isNoun: false))
        #expect(emoji.words["ねこ"] == EmojiWord(text: "猫", isNoun: true))
    }

    @Test("文の中で文節の第 1 候補が変わったら，その語と名前が合わなくなった絵文字を除く(かえる だけなら 🐸，家に帰る の文節では出さない)")
    func keepsOnlyRelevantEmoji() {
        let row = ["emoji", "nature", "🐸", "0.6", "カエルの顔", "かえるのかお", "frog", "かえる|かえるのかお", "カエルの顔|動物|顔", "", ""]
        let lookup = PaletteEmojiLookup(catalog: FakePaletteCatalog(row.joined(separator: "\t")), usage: FakePaletteUsageStore(),
                                        settings: FakeSettings(settings()), now: Date.init)
        let converter = FakeConverter(["かえる": [("カエル", nil), ("帰る", nil), ("変える", nil)]])
        let supplemented = SupplementedConverter(converter, settings: FakeSettings(settings()), calendar: FakeCalendar(), emoji: lookup)
        let alone = supplemented.listCandidates(for: "かえる")
        #expect(alone.contains { $0.text == "🐸" })
        #expect(supplemented.keepingRelevantEmoji(alone, reading: "かえる").contains { $0.text == "🐸" })
        // 文の中の文節(家に｜帰る)では「帰る」を先頭にした候補になる
        let inSentence = [Candidate(text: "帰る", readingCount: 3, origin: .sentencePart)] + alone.filter { $0.text != "帰る" }
        #expect(!supplemented.keepingRelevantEmoji(inSentence, reading: "かえる").contains { $0.text == "🐸" })
    }

    @Test("文節全体と文節の中の語の絵文字は別々の設定で，片方だけでも動く", arguments: [(true, false), (false, true), (true, true)])
    func independentSettings(whole: Bool, word: Bool) {
        let converter = supplemented(settings { $0.emojiConversion = whole; $0.emojiWordConversion = word }, converter: sentenceConverter())
        #expect(converter.listCandidates(for: "ねこ").contains { $0.text == "🐈" } == whole)
        #expect(converter.listCandidates(for: "ねこが").contains { $0.text == "🐈が" } == word)
    }
}

/// パレットの表から変換の絵文字を引く(PaletteEmojiLookup)
@MainActor
@Suite("パレットの表から引く絵文字")
struct PaletteEmojiLookupTests {
    private static func line(_ text: String, version: String, name: String, nameReading: String, readings: String, tones: String = "") -> String {
        ["emoji", "people", text, version, name, nameReading, "", readings, "", "", tones].joined(separator: "\t")
    }

    private static let table = [
        line("👋", version: "0.6", name: "手を振る", nameReading: "てをふる", readings: "ばいばい|て", tones: "👋🏻|👋🏼|👋🏽|👋🏾|👋🏿"),
        line("🙌", version: "0.6", name: "万歳", nameReading: "ばんざい", readings: "ばいばい|て"),
        line("🫶", version: "14.0", name: "ハートの手", nameReading: "はーとのて", readings: "て"),
        ["symbol", "arrows", "→", "", "右向矢印", "みぎむきやじるし", "", "て", "", "", ""].joined(separator: "\t"),
    ].joined(separator: "\n")

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func lookup(usage: FakePaletteUsageStore = FakePaletteUsageStore(), settings: Settings = DefaultSettings.settings,
                        catalog: FakePaletteCatalog = FakePaletteCatalog(table)) -> PaletteEmojiLookup {
        PaletteEmojiLookup(catalog: catalog, usage: usage, settings: FakeSettings(settings), now: { self.start })
    }

    /// 文節の第 1 候補の「手」
    private static let hand = EmojiWord(text: "手", isNoun: true)

    @Test("読みと同じ読みで，名前の語が文節の語と合う絵文字だけを，表の順に出す．記号は出さない")
    func exactReading() {
        // 🙌(万歳)は読みに「て」があるが，名前に「手」が無いので出さない
        #expect(lookup().emoji(for: "て", word: Self.hand, limit: 5) == ["👋", "🫶"])
        #expect(lookup().emoji(for: "て", word: Self.hand, limit: 1) == ["👋"])
        #expect(lookup().emoji(for: "てを", word: Self.hand, limit: 5).isEmpty)
    }

    @Test("OS が描けない新しい絵文字を除いた表なら，その絵文字は出さない(Windows のビルド番号で除いた表)")
    func limitedCatalog() {
        let catalog = FakePaletteCatalog(Self.table)
        catalog.index = catalog.index.map { PaletteIndex(catalog: $0.catalog.limited(to: .supportedOnWindows(build: 19045))) }
        #expect(lookup(catalog: catalog).emoji(for: "て", word: Self.hand, limit: 5) == ["👋"])
    }

    @Test("表を読み終えるまでは出さない")
    func notLoaded() {
        let catalog = FakePaletteCatalog(Self.table)
        catalog.index = nil
        #expect(lookup(catalog: catalog).emoji(for: "て", word: Self.hand, limit: 5).isEmpty)
    }

    @Test("肌の色を変えられる絵文字は，パレットで選んだ肌の色で出す")
    func skinTone() {
        var usage = PaletteUsage()
        usage.defaultSkinTone = .medium
        #expect(lookup(usage: FakePaletteUsageStore(usage)).emoji(for: "て", word: Self.hand, limit: 5) == ["👋🏽", "🫶"])
        usage.setSkinTone(.dark, for: "👋")
        #expect(lookup(usage: FakePaletteUsageStore(usage)).emoji(for: "て", word: Self.hand, limit: 5) == ["👋🏿", "🫶"])
    }

    @Test("名前は肌の色を変えた形からも引く")
    func name() {
        #expect(lookup().name(of: "👋🏽") == "手を振る")
        #expect(lookup().name(of: "→") == nil)
        #expect(lookup().name(of: "猫") == nil)
    }

    @Test("その読みで選んだ絵文字を次から先に出す．肌の色を変えた形も変えていない形で数える")
    func learnsChoice() {
        let usage = FakePaletteUsageStore()
        let lookup = lookup(usage: usage)
        lookup.didCommit("🫶", reading: "て")
        #expect(lookup.emoji(for: "て", word: Self.hand, limit: 1) == ["🫶"])
        lookup.didCommit("👋🏽", reading: "ばいばい")
        lookup.didCommit("👋🏽", reading: "ばいばい")
        #expect(usage.usage.learnedChoices(for: PaletteSearch.Query(typed: "", kana: "ばいばい")) == ["👋"])
    }

    @Test("学ばない設定とパレットの履歴を残さない設定では，選んだことを覚えない", arguments: [LearningMode.readOnly, .disabled])
    func noLearning(mode: LearningMode) {
        var settings = DefaultSettings.settings
        settings.learning = mode
        let usage = FakePaletteUsageStore()
        lookup(usage: usage, settings: settings).didCommit("🫶", reading: "て")
        #expect(usage.saveCount == 0)
        settings.learning = .enabled
        settings.paletteRecordsHistory = false
        lookup(usage: usage, settings: settings).didCommit("🫶", reading: "て")
        #expect(usage.saveCount == 0)
    }
}
