import HajimeDomain

/// 英字入力(自動)で打った文を，語ごとに英語と日本語のどちらにするかを試す(設定の画面の「試す」)．
/// 入力のときと同じ見分け方(WordLanguageClassifier)を使い，前の語の結果を次の語の手がかりにする
@MainActor
public final class WordLanguagePreview {
    /// 1 語の結果
    public struct Word: Sendable, Equatable {
        /// 打った英字
        public var typed: String
        public var language: WordLanguage
        /// 入る文字(日本語にするなら変換の第 1 候補)
        public var shown: String

        public init(typed: String, language: WordLanguage, shown: String) {
            self.typed = typed
            self.language = language
            self.shown = shown
        }
    }

    private let converter: any KanaKanjiConverting
    private let classifier: WordLanguageClassifier

    public init(converter: any KanaKanjiConverting, lexicon: any EnglishLexicon, settings: any SettingsReading) {
        self.converter = converter
        self.classifier = WordLanguageClassifier(lexicon: lexicon, converter: converter, settings: settings)
    }

    /// 空白で区切った語ごとの結果．precedingText は文の前にある文字列(「試合に」など)
    public func preview(_ text: String, precedingText: String? = nil) -> [Word] {
        var context = WordLanguageContext.of(precedingText: precedingText)
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\u{3000}" }).map(String.init)
            .prefix(DefaultSettings.maximumWordLanguagePreviewWords)
        return words.map { typed in
            let reading = typed.count >= DefaultSettings.minimumEnglishInputSuggestionLength ? WordLanguageClassifier.reading(of: typed) : nil
            let language = reading == nil ? .english : classifier.language(of: typed, context: context, mode: .englishFirst)
            context = language == .english ? .afterEnglish : .afterJapanese
            let shown = language == .japanese
                ? reading.flatMap { reading in converter.candidates(for: reading).first { $0.readingCount == reading.count }?.text } ?? reading ?? typed
                : typed
            return Word(typed: typed, language: language, shown: shown)
        }
    }
}

extension WordLanguagePreview.Word: CustomStringConvertible, CustomDebugStringConvertible {
    // 打った語は入力内容と同じに扱うので，ログには長さだけを出す
    public var description: String { "Word(typedLength: \(typed.count), language: \(language))" }
    public var debugDescription: String { description }
}
