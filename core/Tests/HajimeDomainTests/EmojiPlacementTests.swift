import Testing
@testable import HajimeDomain

@Suite("変換の候補の絵文字の置き場所")
struct EmojiPlacementTests {
    private func candidates(_ texts: [String], emoji: Set<String>) -> [Candidate] {
        texts.map { Candidate(text: $0, readingCount: 2, origin: emoji.contains($0) ? .emoji : .engine(id: 0)) }
    }

    @Test("絵文字として描く文字だけを絵文字とみなす", arguments: [
        ("🐈", true), ("❤️", true), ("👋🏻", true), ("🇯🇵", true), ("1️⃣", true), ("❤️‍🔥", true), ("🍺🍻", true),
        // azooKey の絵文字の辞書は要らない U+FE0F を付けている
        ("😀\u{FE0F}", true),
        ("☺", false), ("❤", false), ("❤︎", false), ("#", false), ("1", false), ("🐈が", false), ("猫", false), ("", false), ("(^_^)", false),
    ])
    func isEmoji(text: String, expected: Bool) {
        #expect(EmojiPlacement.isEmoji(text) == expected)
    }

    @Test("絵文字を並びを保ったまま決まった位置にまとめる")
    func places() {
        let placement = EmojiPlacement(index: 3, count: 2)
        let placed = placement.placed(candidates(["猫", "ねこ", "🐈", "根子", "😺", "音子", "値子"], emoji: ["🐈", "😺"]))
        #expect(placed.map(\.text) == ["猫", "ねこ", "根子", "🐈", "😺", "音子", "値子"])
    }

    @Test("第 1 候補にはしない．ほかの候補が位置に足りなければ末尾に置く")
    func neverFirst() {
        let first = EmojiPlacement(index: 0, count: 2).placed(candidates(["🐈", "猫", "ねこ"], emoji: ["🐈"]))
        #expect(first.map(\.text) == ["猫", "🐈", "ねこ"])
        let short = EmojiPlacement(index: 5, count: 2).placed(candidates(["猫", "🐈", "ねこ"], emoji: ["🐈"]))
        #expect(short.map(\.text) == ["猫", "ねこ", "🐈"])
    }

    @Test("読みで引いた絵文字(.emoji)だけを動かす．ユーザー辞書などの絵文字は動かさない")
    func movesOnlyLookedUpEmoji() {
        var list = candidates(["😺", "猫", "ねこ", "🐈"], emoji: ["🐈"])
        list[0].origin = .userDictionary
        #expect(EmojiPlacement(index: 1, count: 1).placed(list).map(\.text) == ["😺", "🐈", "猫", "ねこ"])
    }

    @Test("設定の位置は 1 から数え，どちらの絵文字にも変換しない設定では置き場所が無い")
    func settings() {
        var settings = DefaultSettings.settings
        settings.emojiCandidatePosition = 4
        settings.emojiCandidateCount = 3
        #expect(settings.emojiPlacement == EmojiPlacement(index: 3, count: 3))
        // 文節全体と文節の中の語のどちらかを絵文字にする設定なら，置き場所は共通
        settings.emojiConversion = false
        #expect(settings.emojiPlacement == EmojiPlacement(index: 3, count: 3))
        settings.emojiWordConversion = false
        #expect(settings.emojiPlacement == nil)
    }

    @Test("付属語だけでできた語の並びを見分ける(文節の中の名詞を絵文字にするのは，後ろが付属語だけのとき)")
    func functionWords() {
        let particle = Candidate.Word(text: "が", readingCount: 1, startsWithParticle: true, endsWithParticle: true, isFunctionWord: true)
        let auxiliary = Candidate.Word(text: "です", readingCount: 2, isFunctionWord: true)
        // 「が可愛い」のように助詞で始まっても自立語を含む語は付属語ではない
        let particleAndAdjective = Candidate.Word(text: "が可愛い", readingCount: 5, startsWithParticle: true)
        #expect(EmojiPlacement.isFunctionWords([particle], readingCount: 1))
        #expect(EmojiPlacement.isFunctionWords([particle, auxiliary], readingCount: 3))
        #expect(!EmojiPlacement.isFunctionWords([particleAndAdjective], readingCount: 5))
        #expect(!EmojiPlacement.isFunctionWords([], readingCount: 0))
        // 語の並びが読み全体を覆わなければ付属語だけとはみなさない
        #expect(!EmojiPlacement.isFunctionWords([particle], readingCount: 2))
    }

    @Test("範囲の外の位置と数は範囲に収める(第 1 候補にはしない)")
    func clamps() {
        var settings = DefaultSettings.settings
        settings.emojiCandidatePosition = 1
        settings.emojiCandidateCount = 99
        settings.clampToValidRanges()
        #expect(settings.emojiCandidatePosition == DefaultSettings.emojiCandidatePositionRange.lowerBound)
        #expect(settings.emojiCandidatePosition >= 2)
        #expect(settings.emojiCandidateCount == DefaultSettings.emojiCandidateCountRange.upperBound)
    }

    @Test("既定の位置と数は，分岐図の見えている枝と一覧の 1 ページ目に収まる")
    func defaultsFitFirstPage() {
        let settings = DefaultSettings.settings
        let last = settings.emojiCandidatePosition + settings.emojiCandidateCount - 1
        #expect(settings.emojiCandidatePosition >= 2)
        #expect(last <= settings.branchCandidatesPerPage)
        #expect(last <= settings.listCandidatesPerPage)
        #expect(last <= DefaultSettings.suggestionCount)
    }
}
