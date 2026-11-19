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
    /// 英語の辞書にあるかを調べた結果．英語と日本語に分けるとき(MixedWordSplit)に，同じ並びを打鍵ごとに何度も調べない
    private var wordCache: [String: Bool] = [:]

    init(lexicon: any EnglishLexicon, converter: any KanaKanjiConverting, settings: any SettingsReading) {
        self.lexicon = lexicon
        self.converter = converter
        self.settings = settings
    }

    func language(of keys: String, context: WordLanguageContext, mode: WordLanguageJudge.Mode) -> WordLanguage {
        let judge = WordLanguageJudge(settings: settings.current.wordLanguage, mode: mode, japaneseReadingLength: settings.current.englishSkipLength)
        if let light = evidenceWithoutConversion(for: keys, mode: mode) { return judge.decide(light, context: context) }
        return judge.decide(evidence(for: keys), context: context)
    }

    /// 語を見分ける(language)ときに変換して調べる読み．変換を求めずに決まる語，前に調べた語，ローマ字として読めない語では nil．
    /// 打鍵が止まったときに見分ける語の変換を，前もって裏で求めておくのに使う(InputSession.prepareSettle)
    func readingToConvert(for keys: String, mode: WordLanguageJudge.Mode) -> String? {
        guard cache[keys] == nil, evidenceWithoutConversion(for: keys, mode: mode) == nil else { return nil }
        return Self.reading(of: keys)
    }

    /// 変換を求めなくても決まる語の手がかり．変換が要る語は nil．
    ///
    /// ローマ字入力で英語の辞書にない長い語(文をまるごと打った並びなど)は，読みのもっともらしさも不適切な語かも見ずに日本語と決まる
    /// (WordLanguageJudge.decide)．その語のために読みを 2 回変換すると，確定のたびに文の長さだけ待たせるので，求めずに決める．
    /// 変換の結果(不適切な語か)を見る語は，短い語，英字の語のあとによく続く語，読みが短い語，英語の辞書にある語
    private func evidenceWithoutConversion(for keys: String, mode: WordLanguageJudge.Mode) -> WordLanguageJudge.Evidence? {
        guard mode == .japaneseFirst, cache[keys] == nil, let reading = Self.reading(of: keys) else { return nil }
        let isWord = keys.allSatisfy({ $0.isASCII && $0.isLetter }) && isEnglishWord(keys)
        guard !isWord, keys.count > DefaultSettings.maximumJapaneseFirstShortWordLength, !TypoCorrectionRule.isWordAfterEnglish(reading),
              reading.count > settings.current.englishSkipLength else { return nil }
        return WordLanguageJudge.Evidence(keys: keys, isEnglishWord: false, reading: reading, plausibilityPerCharacter: nil, isOffensive: false)
    }

    /// 英語の辞書にある語か
    func isEnglishWord(_ keys: String) -> Bool {
        if let cached = wordCache[keys] { return cached }
        let value = lexicon.isWord(keys)
        if wordCache.count >= DefaultSettings.maximumEnglishWordCache { wordCache = [:] }
        wordCache[keys] = value
        return value
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
