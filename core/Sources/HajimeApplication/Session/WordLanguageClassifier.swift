import HajimeDomain

/// 英字で打った 1 語を英語にするか日本語にするかを見分ける(R-05 の英字入力(自動)，R-02 のローマ字入力の英単語)．
/// 英語の辞書・ローマ字として読めるか・読みを変換したときのもっともらしさ・不適切な語かを調べ，WordLanguageJudge で決める
@MainActor
final class WordLanguageClassifier {
    private let lexicon: any EnglishLexicon
    private let converter: any KanaKanjiConverting
    private let settings: any SettingsReading
    /// 調べた結果．同じ語を打鍵ごとに何度も調べない．多くなったら捨てる
    private var cache: [String: WordLanguageJudge.Evidence] = [:]

    init(lexicon: any EnglishLexicon, converter: any KanaKanjiConverting, settings: any SettingsReading) {
        self.lexicon = lexicon
        self.converter = converter
        self.settings = settings
    }

    func language(of keys: String, context: WordLanguageContext, mode: WordLanguageJudge.Mode) -> WordLanguage {
        WordLanguageJudge(settings: settings.current.wordLanguage, mode: mode).decide(evidence(for: keys), context: context)
    }

    /// ローマ字として読めれば，その読み
    static func reading(of keys: String) -> String? {
        // 大文字を含む語は英語として打ったもの(「Documents」)
        guard !keys.isEmpty, keys.allSatisfy({ ($0.isASCII && $0.isLetter && $0.isLowercase) || $0 == "-" }) else { return nil }
        var composition = Composition()
        for key in keys { composition.insertRomaji(key) }
        guard !composition.containsInvalidRomaji, composition.pending.isEmpty || composition.pending == "n" else { return nil }
        return composition.conversionReading
    }

    func evidence(for keys: String) -> WordLanguageJudge.Evidence {
        if let cached = cache[keys] { return cached }
        let reading = Self.reading(of: keys)
        let plausibility = reading.map { converter.plausibility(of: $0) / Double(max($0.count, 1)) }
        let offensive = reading.map { reading in
            OffensiveWords.isOffensive(reading: reading)
                || converter.candidates(for: reading).first.map { OffensiveWords.isOffensive(text: $0.text) } == true
        } ?? false
        let letters = keys.allSatisfy { $0.isASCII && $0.isLetter }
        let evidence = WordLanguageJudge.Evidence(keys: keys, isEnglishWord: letters && lexicon.isWord(keys), reading: reading,
                                                  plausibilityPerCharacter: plausibility, isOffensive: offensive)
        if cache.count >= DefaultSettings.maximumWordLanguageCache { cache = [:] }
        cache[keys] = evidence
        return evidence
    }
}
