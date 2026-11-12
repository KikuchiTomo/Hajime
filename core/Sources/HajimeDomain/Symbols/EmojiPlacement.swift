/// 変換の候補の中の絵文字の置き場所(設定の「絵文字に変換」)．
///
/// 絵文字はふだんの語より選ぶことが少ないので，第 1 候補(ライブ変換で見える文字．Space ですぐ確定できる文字)にはしない．
/// その代わり，分岐図の見えている枝と一覧の 1 ページ目に入る位置にまとめて置き，探さなくても目に入るようにする．
/// 候補を並べ替える処理(前後の文脈・検証木・文節の先頭の語の選び直し)はどれも絵文字を押し下げうるので，
/// 並べ替えたあとに置き直す
public struct EmojiPlacement: Sendable, Equatable {
    /// 先頭から数えた位置(0 から)．第 1 候補にしないため，1 より前には置かない
    public var index: Int
    /// 候補に入れる絵文字の数の上限
    public var count: Int

    public init(index: Int, count: Int) {
        self.index = index
        self.count = count
    }

    /// items の中の絵文字を，並びを保ったまま index の位置にまとめる．ほかの項目が index に足りなければ，その末尾に置く
    public func placed<Item>(_ items: [Item], isEmoji: (Item) -> Bool) -> [Item] {
        let emoji = items.filter(isEmoji)
        guard !emoji.isEmpty else { return items }
        var others = items.filter { !isEmoji($0) }
        others.insert(contentsOf: emoji, at: min(max(index, 1), others.count))
        return others
    }

    /// 読みで引いた絵文字の候補(origin が .emoji)を index の位置にまとめる
    public func placed(_ candidates: [Candidate]) -> [Candidate] {
        placed(candidates) { $0.origin == .emoji }
    }

    /// 文字がすべて絵文字として描かれる字か(「🐈」「❤️」「👋🏻」「🇯🇵」「1️⃣」)．
    /// 印の無い「☺」「❤」「#」や，語と混ざった「🐈が」は絵文字ではない
    public static func isEmoji(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy(isEmojiCharacter)
    }

    /// 絵文字として描かれる字を含むか(「🐈が」)
    public static func containsEmoji(_ text: String) -> Bool {
        text.contains(where: isEmojiCharacter)
    }

    /// 絵文字の形で描く字(Emoji_Presentation)か，絵文字の形を選ぶ印(U+FE0F)かキーキャップの印(U+20E3)を付けた字
    private static func isEmojiCharacter(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard let first = scalars.first else { return false }
        return first.properties.isEmojiPresentation
            || (first.properties.isEmoji && scalars.contains { $0 == emojiStyle || $0 == keycap })
    }

    /// 語の並びが付属語(助詞・助動詞)だけでできていて，読みの readingCount 文字を覆うか．
    /// 文節の中の名詞を絵文字にする(「ねこが」→「🐈が」)のは，名詞の後ろが付属語だけのときに限る．
    /// 「ねこがかわいい」の「がかわいい」のように自立語を含むと，語を絵文字にした文が読みにくくなるので使わない
    public static func isFunctionWords(_ words: [Candidate.Word], readingCount: Int) -> Bool {
        !words.isEmpty && words.allSatisfy(\.isFunctionWord) && words.reduce(0, { $0 + $1.readingCount }) == readingCount
    }

    private static let emojiStyle: Unicode.Scalar = "\u{FE0F}"
    private static let keycap: Unicode.Scalar = "\u{20E3}"
}
