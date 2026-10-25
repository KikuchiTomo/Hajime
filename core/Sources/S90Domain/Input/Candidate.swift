/// 変換候補の出どころ．確定したときに何をするか(学習するか，など)が変わる．
public enum CandidateOrigin: Sendable, Equatable {
    /// 変換エンジンの候補．id はエンジンのアダプタが自分の候補を引くための番号
    case engine(id: Int)
    /// タイプミスの補正(R-02)
    case correction
    /// 打ったままの文字列(補正を取り消すときの候補)
    case asTyped
    /// 文字の種類の変換(R-03)
    case variant(ScriptVariant)
}

/// 候補ひとつ．readingCount は，この候補が読みの先頭から何文字ぶんを置き換えるか．
public struct Candidate: Sendable, Equatable {
    public var text: String
    public var readingCount: Int
    public var origin: CandidateOrigin

    public init(text: String, readingCount: Int, origin: CandidateOrigin) {
        self.text = text
        self.readingCount = readingCount
        self.origin = origin
    }
}

extension Candidate: CustomStringConvertible, CustomDebugStringConvertible {
    // 候補の文字列は入力内容そのものなので，ログには長さだけを出す
    public var description: String { "Candidate(length: \(text.count), readingCount: \(readingCount), origin: \(origin))" }
    public var debugDescription: String { description }
}
