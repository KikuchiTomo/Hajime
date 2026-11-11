import HajimeDomain

/// 英単語の辞書に英語の語の辞書(R-24)の語を足したもの．OS のスペルチェッカーが知らない語(「openai」「chatgpt」)も英単語として扱い，
/// ローマ字として読めない並び(「chatgpt」→ ちゃtgpt)を英単語の補正(R-02)で英語の語にする．補正した語は辞書の書き方にする(ChatGPT)
@MainActor
public final class EnglishTermLexicon: EnglishLexicon {
    private let base: any EnglishLexicon
    private let terms: EnglishTerms

    public init(_ base: any EnglishLexicon, terms: EnglishTerms) {
        self.base = base
        self.terms = terms
    }

    public func isWord(_ text: String) -> Bool {
        base.isWord(text) || !(terms.dictionary?.terms(forKeys: text).isEmpty ?? true)
    }

    public func suggestions(for text: String) -> [String] {
        base.suggestions(for: text)
    }

    /// 小文字で打った語だけを辞書の書き方にする．大文字を含めて打った語は打ったとおりにする
    public func spelling(of word: String) -> String? {
        guard word.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) }) else { return base.spelling(of: word) }
        return terms.dictionary?.terms(forKeys: word).first ?? base.spelling(of: word)
    }
}
