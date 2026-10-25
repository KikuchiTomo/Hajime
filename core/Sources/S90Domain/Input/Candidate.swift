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
    /// 文全体の候補から切り出した文節．学習には使わない
    case sentencePart
    /// 複数の候補をつないだもの(文節格子の全体など)
    case combined
}

/// 候補ひとつ．readingCount は，この候補が読みの先頭から何文字ぶんを置き換えるか．
/// score はエンジンが付けた対数尤度で，大きいほどよい．エンジン以外の候補は 0
public struct Candidate: Sendable, Equatable {
    public var text: String
    public var readingCount: Int
    public var origin: CandidateOrigin
    public var score: Double

    public init(text: String, readingCount: Int, origin: CandidateOrigin, score: Double = 0) {
        self.text = text
        self.readingCount = readingCount
        self.origin = origin
        self.score = score
    }

    /// 変換エンジンが出した候補か．確定したときに学習に使うのはこれだけ
    public var isFromEngine: Bool {
        if case .engine = origin { true } else { false }
    }
}

extension Candidate: CustomStringConvertible, CustomDebugStringConvertible {
    // 候補の文字列は入力内容そのものなので，ログには長さだけを出す
    public var description: String { "Candidate(length: \(text.count), readingCount: \(readingCount), origin: \(origin))" }
    public var debugDescription: String { description }
}
