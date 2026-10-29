/// 決まりの一覧のファイルの 1 行．左は打つもの(打った英字・入力・読み)，右は出すもの．1 列だけの一覧は右が空
public struct RuleListRow: Sendable, Equatable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// 設定の画面でファイルに書き出し・読み込みできる決まりの一覧．
/// どの一覧も「左<タブ>右」の行で読み書きし(RuleListFile)，読み込んだ行はそれぞれの一覧の決まりで確かめて足す
public enum RuleList: String, Sendable, Equatable, CaseIterable {
    /// 補正の置き換え(打った英字 → 語)
    case correctionRules
    /// 補正で直さない語句
    case exceptions
    /// いつも英語にする語
    case englishWords
    /// いつも日本語にする語
    case japaneseWords
    /// ローマ字の綴りの追加
    case romaji
    /// 続けて打った記号
    case symbolSequences
    /// 読みから引く記号
    case symbolReadings

    /// 書き出すファイルの既定の名前
    public var exportFileName: String {
        switch self {
        case .correctionRules: "replacements.tsv"
        case .exceptions: "exceptions.txt"
        case .englishWords: "english-words.txt"
        case .japaneseWords: "japanese-words.txt"
        case .romaji: "romaji.tsv"
        case .symbolSequences: "symbol-sequences.tsv"
        case .symbolReadings: "symbol-readings.tsv"
        }
    }

    /// 書き出す行．記号は既定の決まりに利用者の決まりを重ね，有効なものだけ
    public func rows(in settings: Settings) -> [RuleListRow] {
        switch self {
        case .correctionRules: settings.correction.rules.map { RuleListRow(key: $0.typed, value: $0.word) }
        case .exceptions: settings.correction.exceptions.map { RuleListRow(key: $0, value: "") }
        case .englishWords: settings.wordLanguage.englishWords.map { RuleListRow(key: $0, value: "") }
        case .japaneseWords: settings.wordLanguage.japaneseWords.map { RuleListRow(key: $0, value: "") }
        case .romaji: settings.customRomaji.map { RuleListRow(key: $0.keys, value: $0.kana) }
        case .symbolSequences, .symbolReadings:
            SymbolRuleEditing.items(symbolKind, rules: settings.symbolRules).filter(\.isEnabled).map { RuleListRow(key: $0.input, value: $0.output) }
        }
    }

    /// 読み込んだ行を一覧に足す．同じ左の決まりは上書きし，形の誤った行と上限を超えた行は足さない．足した(上書きを含む)数を返す
    public func merge(_ rows: [RuleListRow], into settings: inout Settings) -> Int {
        switch self {
        case .correctionRules:
            RuleListEditing.merge(rows.map { RuleListEditing.correctionRule(typed: $0.key, word: $0.value) }, key: \.typed, isValid: \.isValid,
                                  limit: DefaultSettings.maximumCorrectionRules, into: &settings.correction.rules)
        case .exceptions:
            RuleListEditing.merge(rows.map(\.key), key: { $0 }, isValid: RuleListEditing.isValidException,
                                  limit: DefaultSettings.maximumCorrectionRules, into: &settings.correction.exceptions)
        case .englishWords:
            RuleListEditing.merge(rows.map { Self.languageWord($0.key) }, key: { $0 }, isValid: WordLanguageSettings.isValidWord,
                                  limit: DefaultSettings.maximumWordLanguageEntries, into: &settings.wordLanguage.englishWords)
        case .japaneseWords:
            RuleListEditing.merge(rows.map { Self.languageWord($0.key) }, key: { $0 }, isValid: WordLanguageSettings.isValidWord,
                                  limit: DefaultSettings.maximumWordLanguageEntries, into: &settings.wordLanguage.japaneseWords)
        case .romaji:
            RuleListEditing.merge(rows.map { RuleListEditing.romajiRule(keys: $0.key, kana: $0.value) }, key: \.keys, isValid: \.isValid,
                                  limit: DefaultSettings.maximumRomajiRules, into: &settings.customRomaji)
        case .symbolSequences, .symbolReadings:
            rows.reduce(0) { count, row in
                SymbolRuleEditing.save(SymbolRule(kind: symbolKind, input: row.key, output: row.value), in: &settings.symbolRules) ? count + 1 : count
            }
        }
    }

    /// 英語と日本語の語は小文字で照らし合わせる
    public static func languageWord(_ text: String) -> String {
        text.trimmed.lowercased()
    }

    private var symbolKind: SymbolRule.Kind { self == .symbolSequences ? .sequence : .reading }
}
