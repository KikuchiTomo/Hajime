import HajimeDomain

/// 同梱の英語の語の辞書と，利用者が設定で足した語をまとめて引く(R-24)．
/// 利用者が足した語を同梱の語より先にする．設定の「英語の語を候補に出す」がオフなら何も返さない
@MainActor
public final class EnglishTerms {
    private let bundled: (any EnglishTermProviding)?
    private let settings: any SettingsReading
    /// 同梱の辞書．初めて使うときに一度だけ読む(読めなければ nil のまま)
    private lazy var bundledDictionary: EnglishTermDictionary? = bundled?.englishTerms
    /// まとめた辞書と，そのもとにした利用者の語．利用者の語が変わったときだけ作り直す
    private var merged: (user: [String], dictionary: EnglishTermDictionary?)?

    public init(bundled: (any EnglishTermProviding)?, settings: any SettingsReading) {
        self.bundled = bundled
        self.settings = settings
    }

    /// 今使う辞書．設定でオフか，語が 1 つも無ければ nil
    public var dictionary: EnglishTermDictionary? {
        let current = settings.current
        guard current.englishTermCandidates else { return nil }
        if let merged, merged.user == current.englishTerms { return merged.dictionary }
        var dictionary = EnglishTermDictionary(terms: current.englishTerms)
        if let bundledDictionary { dictionary = dictionary.merging(bundledDictionary) }
        let result = dictionary.isEmpty ? nil : dictionary
        merged = (current.englishTerms, result)
        return result
    }
}
