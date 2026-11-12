import HajimeDomain
import Testing

/// かな漢字変換の候補に足す絵文字の，同じ意味の語の一覧(R-26)
@Suite("絵文字の同じ意味の語の一覧")
struct EmojiSynonymsTests {
    private static let list = EmojiSynonyms(text: """
    # 注記
    コーヒー\tこーひー\t☕
    ありがとう\tありがとう\t🙏
    空室\tくうしつ\t🈳
    泣く\tなく\t😭 😢
    泣く\tなく\t😢 🥲
    形の合わない行
    \tなく\t😭
    """)

    @Test("語と読みの両方が合う行の絵文字を，書いた順に返す．同じ語と読みの行はつなぐ")
    func lookup() {
        #expect(Self.list.emoji(reading: "こーひー", word: EmojiWord(text: "コーヒー", isNoun: true)) == ["☕"])
        #expect(Self.list.emoji(reading: "なく", word: EmojiWord(text: "泣く", isNoun: false)) == ["😭", "😢", "🥲"])
        #expect(Self.list.emoji(reading: "なく", word: EmojiWord(text: "無く", isNoun: false)).isEmpty)
        #expect(Self.list.emoji(reading: "そら", word: EmojiWord(text: "空", isNoun: true)).isEmpty)
        #expect(Self.list.emoji(reading: "くう", word: EmojiWord(text: "空室", isNoun: true)).isEmpty)
        #expect(Self.list.allEmoji == ["☕", "🙏", "🈳", "😭", "😢", "🥲"])
    }

    @Test("第 1 候補がひらがななら，そのひらがなでも引く(ありがとう → 🙏)")
    func hiraganaFirstCandidate() {
        let word = EmojiWord(text: "有難う", isNoun: false, hiraganaText: "ありがとう")
        #expect(Self.list.emoji(reading: "ありがとう", word: word) == ["🙏"])
    }
}
