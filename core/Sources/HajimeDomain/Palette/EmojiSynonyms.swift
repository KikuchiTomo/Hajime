/// かな漢字変換の候補に足す絵文字の，同じ意味の語の一覧(R-26)．同梱の表(data/palette/emoji-synonyms.tsv)を読む．
///
/// 絵文字の名前に出てこないが，その語でいちばん期待される絵文字(コーヒー → ☕ 温かい飲み物，ありがとう → 🙏 祈り)を，
/// 名前の照らし合わせ(EmojiRelevance)を通さずに出すため．語と読みの両方が文節と合うときだけ出す(空室 → 🈳 は出し，空(そら) → 🈳 は出さない)．
/// 行は「語<タブ>読み<タブ>絵文字(空白で区切り，先に出すものから)」．# で始まる行は注記．表は手で書く
public struct EmojiSynonyms: Sendable, Equatable {
    private struct Key: Hashable, Sendable {
        var word: String
        var reading: String
    }

    private var emoji: [Key: [String]]

    public init() {
        emoji = [:]
    }

    /// 表の中身を読む．形の合わない行は飛ばす．同じ語と読みの行が重なれば，前の行の後ろにつなぐ
    public init(text: String) {
        var emoji: [Key: [String]] = [:]
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3, !fields[0].isEmpty, !fields[1].isEmpty else { continue }
            let texts = fields[2].split(separator: " ").map(String.init)
            guard !texts.isEmpty else { continue }
            let key = Key(word: String(fields[0]), reading: String(fields[1]))
            for text in texts where !(emoji[key] ?? []).contains(text) { emoji[key, default: []].append(text) }
        }
        self.emoji = emoji
    }

    /// 文節の語(第 1 候補の表記と，第 1 候補がひらがなならそのひらがな)と読みに合う絵文字．先に出すものから
    public func emoji(reading: String, word: EmojiWord) -> [String] {
        var result: [String] = []
        for text in [word.text, word.hiraganaText].compactMap({ $0 }) {
            for item in emoji[Key(word: text, reading: reading)] ?? [] where !result.contains(item) { result.append(item) }
        }
        return result
    }

    /// 一覧にある絵文字(表の絵文字がパレットの表にあるかを確かめるため)
    public var allEmoji: Set<String> {
        Set(emoji.values.joined())
    }
}
