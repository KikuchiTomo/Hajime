/// 使い方の記録．入力した文字列は持たず，回数だけを数える(docs/dev/research/list-free-input.md の「計測の仕組み」)．
///
/// 第 1 候補のまま確定できた割合や，打ち間違いの訂正を戻した割合から，
/// 分岐図の迷う文節の基準やライブ変換の見せ方を見直すために使う
public struct UsageCounts: Sendable, Equatable, Codable {
    /// 確定した回数
    public var commits = 0
    /// 変換の候補を開かずに(ライブ変換のまま)確定した回数
    public var commitsWithoutConversion = 0
    /// Space で変換の候補を開いた回数
    public var conversionsOpened = 0
    /// 候補を開いて，1 つも選び直さずに確定した回数
    public var conversionsKeptFirst = 0
    /// 選び直した文節の数
    public var segmentsChanged = 0
    /// 日本語の打ち間違いを直した回数と，Esc で戻された回数
    public var readingCorrections = 0
    public var readingCorrectionsUndone = 0
    /// 英単語を補正した回数と，Space で戻された回数
    public var englishCorrections = 0
    public var englishCorrectionsUndone = 0

    public init() {}

    /// 選び直さずに確定した割合(候補を開かずに確定したものを含む)
    public var firstCandidateRate: Double? {
        commits == 0 ? nil : Double(commitsWithoutConversion + conversionsKeptFirst) / Double(commits)
    }

    public mutating func record(_ event: UsageEvent) {
        switch event {
        case .committed(let changedSegments, let viaConversion):
            commits += 1
            if !viaConversion { commitsWithoutConversion += 1 }
            if viaConversion && changedSegments == 0 { conversionsKeptFirst += 1 }
            segmentsChanged += changedSegments
        case .conversionOpened: conversionsOpened += 1
        case .readingCorrected: readingCorrections += 1
        case .readingCorrectionUndone: readingCorrectionsUndone += 1
        case .englishCorrected: englishCorrections += 1
        case .englishCorrectionUndone: englishCorrectionsUndone += 1
        }
    }
}

/// 記録する出来事．文字列は含めない
public enum UsageEvent: Sendable, Equatable {
    /// 確定した．changedSegments は選び直した文節の数，viaConversion は候補を開いてから確定したか
    case committed(changedSegments: Int, viaConversion: Bool)
    case conversionOpened
    case readingCorrected
    case readingCorrectionUndone
    case englishCorrected
    case englishCorrectionUndone
}
