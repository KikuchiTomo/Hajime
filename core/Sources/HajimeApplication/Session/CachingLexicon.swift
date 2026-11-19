import HajimeDomain

/// 英単語の辞書を引いた結果を覚えて使い回す包み．
///
/// 綴りの候補(suggestions)を引くのは時間がかかる(macOS のスペルチェッカーで 1 回 10〜60ms)．英単語を打っているあいだは
/// 同じ綴りを打鍵ごとに何度も引くので，引いた結果を覚えておき，キーの処理の中で同じ綴りを引き直さない
@MainActor
final class CachingLexicon: EnglishLexicon {
    private let base: any EnglishLexicon
    private var words: [String: Bool] = [:]
    private var suggested: [String: [String]] = [:]

    init(_ base: any EnglishLexicon) {
        self.base = base
    }

    func isWord(_ text: String) -> Bool {
        if let known = words[text] { return known }
        let value = base.isWord(text)
        if words.count >= DefaultSettings.maximumEnglishWordCache { words = [:] }
        words[text] = value
        return value
    }

    func suggestions(for text: String) -> [String] {
        if let known = suggested[text] { return known }
        let value = base.suggestions(for: text)
        if suggested.count >= DefaultSettings.maximumEnglishWordCache { suggested = [:] }
        suggested[text] = value
        return value
    }

    func spelling(of word: String) -> String? {
        base.spelling(of: word)
    }

    /// 覚えた結果を捨てる．英単語の辞書(利用者が足した単語)は変わることがあるので，入力を終えるたびに捨てる
    func forget() {
        words = [:]
        suggested = [:]
    }
}
