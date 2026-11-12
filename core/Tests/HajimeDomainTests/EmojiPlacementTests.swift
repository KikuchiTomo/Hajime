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

    @Test("設定の位置は 1 から数え，絵文字に変換しない設定では置き場所が無い")
    func settings() {
        var settings = DefaultSettings.settings
        settings.emojiCandidatePosition = 4
        settings.emojiCandidateCount = 3
        #expect(settings.emojiPlacement == EmojiPlacement(index: 3, count: 3))
        settings.emojiConversion = false
        #expect(settings.emojiPlacement == nil)
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
