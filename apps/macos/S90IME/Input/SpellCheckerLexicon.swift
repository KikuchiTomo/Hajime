import AppKit
import S90Application

/// macOS のスペルチェッカーを英単語の辞書として使う(R-02)．調べるのは端末の中だけで，外部には送らない．
@MainActor
final class SpellCheckerLexicon: EnglishLexicon {
    private static let language = "en"
    private let checker = NSSpellChecker.shared

    func isWord(_ text: String) -> Bool {
        let range = checker.checkSpelling(of: text, startingAt: 0, language: Self.language, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        return range.location == NSNotFound
    }

    func suggestions(for text: String) -> [String] {
        checker.guesses(forWordRange: NSRange(location: 0, length: (text as NSString).length), in: text, language: Self.language, inSpellDocumentWithTag: 0) ?? []
    }
}
