/// 候補の語の並びから，文節(自立語とそのあとに続く助詞・助動詞)の区切りを決める(ADR 0007)．
///
/// エンジンの「最初の文節」は粗く，「非常な人だ」を 1 つの文節にすることがある．それでは「非情」を選べないので，
/// 語の並びから次の決まりで細かく分ける．
/// - 漢字・カタカナ・英字で始まる語と，ひらがなの名詞(「ところ」「こと」)から，新しい文節を始める
/// - 語の中で，先頭のひらがなのあとに漢字などが続けば，そこで分ける(「な人だ」→「な」「人だ」，「を立てる」→「を」「立てる」)
/// - 1 文字の助詞で始まり，2 文字以上のひらがなが続く語は，助詞のあとで分ける(「はいい」→「は」「いい」，「とすれば」→「と」「すれば」)
/// - ひらがなで始まるそのほかの語(助詞・助動詞・「する」など)は，前の文節に付ける
public enum ClauseSplitter {
    public struct Clause: Sendable, Equatable {
        public var text: String
        public var readingCount: Int

        public init(text: String, readingCount: Int) {
            self.text = text
            self.readingCount = readingCount
        }
    }

    /// 語の並びを文節に分ける．語が無ければ空
    public static func clauses(of words: [Candidate.Word]) -> [Clause] {
        var clauses: [Clause] = []
        func append(_ text: String, _ readingCount: Int, startsClause: Bool) {
            guard !text.isEmpty || readingCount > 0 else { return }
            if startsClause || clauses.isEmpty {
                clauses.append(Clause(text: text, readingCount: readingCount))
            } else {
                clauses[clauses.count - 1].text += text
                clauses[clauses.count - 1].readingCount += readingCount
            }
        }
        for word in words {
            let characters = Array(word.text)
            guard let first = characters.first else { continue }
            // 「お茶」「ご飯」の接頭辞は分けず，語全体を新しい文節にする
            let leading = characters.prefix(while: isHiragana).count
            let isPrefixed = leading == 1 && characters.count > 1 && !word.startsWithParticle && honorificPrefixes.contains(first)
            if !isHiragana(first) || word.startsWithNoun || isPrefixed {
                append(word.text, word.readingCount, startsClause: true)
                continue
            }
            // 先頭のひらがなは読みと 1 文字ずつ対応するので，読みの長さもそのまま分けられる
            if leading < characters.count {
                append(String(characters.prefix(leading)), leading, startsClause: false)
                append(String(characters.dropFirst(leading)), word.readingCount - leading, startsClause: true)
            } else if word.startsWithParticle, characters.count > 2, singleParticles.contains(first) {
                append(String(first), 1, startsClause: false)
                append(String(characters.dropFirst()), word.readingCount - 1, startsClause: true)
            } else {
                append(word.text, word.readingCount, startsClause: false)
            }
        }
        return clauses
    }

    /// 語の頭に付く接頭辞．「お茶」「ご飯」は 1 つの語として扱う
    private static let honorificPrefixes: Set<Character> = ["お", "ご"]

    /// 1 文字の助詞．語の先頭にあれば，そのあとで文節を分けてよい
    private static let singleParticles: Set<Character> = ["は", "が", "を", "に", "の", "へ", "と", "で", "も", "や"]

    private static func isHiragana(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (0x3041...0x309F).contains($0.value) || $0 == "ー" }
    }
}
