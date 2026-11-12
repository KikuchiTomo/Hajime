import Foundation
import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

/// 読みで引いた絵文字を変換の候補に足す(設定の「絵文字に変換」)．第 1 候補にはせず，分岐図の見えている枝・一覧の 1 ページ目・
/// 入力中の候補の窓に入る位置にまとめて置く(EmojiPlacement)
@MainActor
@Suite("絵文字の候補")
struct EmojiCandidateScenarioTests {
    /// 「ねこ」の変換．エンジンの辞書の絵文字(🐱)も混ぜておく
    private func converter() -> FakeConverter {
        FakeConverter(["ねこ": [("猫", nil), ("ねこ", nil), ("ネコ", nil), ("🐱", nil), ("根子", nil), ("音子", nil), ("値子", nil), ("子子", nil)]])
    }

    private let emoji = FakeEmoji(["ねこ": ["🐈", "😺", "😸"], "なく": ["😢", "😭", "🐦"]], names: ["🐈": "ネコ"])

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
        let candidates = supplemented(settings()).candidates(for: "ねこ")
        #expect(candidates.map(\.text) == ["猫", "ねこ", "🐈", "😺", "ネコ", "根子", "音子", "値子", "子子"])
        #expect(candidates.filter { $0.origin == .emoji }.map(\.text) == ["🐈", "😺"])
        let moved = supplemented(settings { $0.emojiCandidatePosition = 5; $0.emojiCandidateCount = 3 }).candidates(for: "ねこ")
        #expect(moved.map(\.text).prefix(7) == ["猫", "ねこ", "ネコ", "根子", "🐈", "😺", "😸"])
    }

    @Test("設定を切ると絵文字を出さない．エンジンの辞書の絵文字も出さない")
    func settingOff() {
        let candidates = supplemented(settings { $0.emojiConversion = false }).candidates(for: "ねこ").map(\.text)
        #expect(!candidates.contains { EmojiPlacement.isEmoji($0) })
    }

    @Test("ユーザー辞書に登録した絵文字は先頭に残す")
    func keepsUserDictionaryEmoji() {
        let candidates = supplemented(settings { $0.userDictionary = [UserDictionaryEntry(reading: "ねこ", word: "🐱")] }).candidates(for: "ねこ")
        #expect(candidates.first?.text == "🐱")
        #expect(candidates.first?.origin == .userDictionary)
    }

    @Test("エンジンが候補を出さない読みでも，絵文字を第 1 候補にしない")
    func neverFirstWithoutOtherCandidates() {
        let candidates = supplemented(settings(), converter: FakeConverter()).candidates(for: "なく").map(\.text)
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

    @Test("入力中の候補の窓にも出す")
    func suggestionShowsEmoji() {
        let harness = harness(settings { $0.liveConversion = false })
        harness.type("neko")
        #expect(harness.panel?.entries.map(\.text).prefix(4) == ["猫", "ねこ", "🐈", "😺"])
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

    @Test("絵文字を選んでいるときは，語の意味のカードに絵文字の名前を出す")
    func meaningCardShowsName() {
        let harness = harness(settings())
        harness.type("neko")
        harness.press(.space)
        harness.press(.down)
        harness.press(.down)
        let column = harness.lattice?.columns.first(where: \.isFocused)
        #expect(column?.text == "🐈")
        #expect(column?.homophone == HomophoneNote(word: "🐈", meaning: "ネコ", others: []))
        // 語の意味を出さない設定では出さない
        let off = self.harness(settings { $0.homophoneNotes = false })
        off.type("neko")
        off.press(.space)
        off.press(.down)
        off.press(.down)
        #expect(off.lattice?.columns.first(where: \.isFocused)?.homophone == nil)
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
        let candidate = converter.candidates(for: "ねこ").first { $0.origin == .emoji }!
        converter.suspendLearningUntilEnd()
        converter.didCommit(candidate)
        #expect(emoji.committed.isEmpty)
        converter.endComposition()
        let again = converter.candidates(for: "ねこ").first { $0.origin == .emoji }!
        converter.didCommit(again)
        #expect(emoji.committed.map(\.reading) == ["ねこ"])
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

    @Test("読みと同じ読みの絵文字だけを，表の順に出す．記号は出さない")
    func exactReading() {
        #expect(lookup().emoji(for: "て", limit: 5) == ["👋", "🙌", "🫶"])
        #expect(lookup().emoji(for: "て", limit: 2) == ["👋", "🙌"])
        #expect(lookup().emoji(for: "てを", limit: 5).isEmpty)
    }

    @Test("OS が描けない新しい絵文字を除いた表なら，その絵文字は出さない(Windows のビルド番号で除いた表)")
    func limitedCatalog() {
        let catalog = FakePaletteCatalog(Self.table)
        catalog.index = catalog.index.map { PaletteIndex(catalog: $0.catalog.limited(to: .supportedOnWindows(build: 19045))) }
        #expect(lookup(catalog: catalog).emoji(for: "て", limit: 5) == ["👋", "🙌"])
    }

    @Test("表を読み終えるまでは出さない")
    func notLoaded() {
        let catalog = FakePaletteCatalog(Self.table)
        catalog.index = nil
        #expect(lookup(catalog: catalog).emoji(for: "て", limit: 5).isEmpty)
    }

    @Test("肌の色を変えられる絵文字は，パレットで選んだ肌の色で出す")
    func skinTone() {
        var usage = PaletteUsage()
        usage.defaultSkinTone = .medium
        #expect(lookup(usage: FakePaletteUsageStore(usage)).emoji(for: "ばいばい", limit: 5) == ["👋🏽", "🙌"])
        usage.setSkinTone(.dark, for: "👋")
        #expect(lookup(usage: FakePaletteUsageStore(usage)).emoji(for: "ばいばい", limit: 5) == ["👋🏿", "🙌"])
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
        #expect(lookup.emoji(for: "て", limit: 1) == ["🫶"])
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
