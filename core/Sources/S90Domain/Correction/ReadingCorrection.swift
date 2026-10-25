/// 打ち間違いを直した読みの候補．keys は直したあとのキーの並び，reading はそのかな．
/// score は言語モデルの対数確率から直した手間(cost)を引いたもので，大きいほどよい
public struct ReadingCorrection: Sendable, Equatable {
    public var keys: String
    public var reading: String
    public var score: Double
    public var cost: Double

    public init(keys: String, reading: String, score: Double, cost: Double) {
        self.keys = keys
        self.reading = reading
        self.score = score
        self.cost = cost
    }

    /// 打ったまま(直していない)か
    public var isUnchanged: Bool { cost == 0 }
}

/// 日本語の打ち間違い(「ようですね」→「よいですね」)を直すかどうかの判定．
///
/// 直した読みが，打ったままの読みより十分にもっともらしいときだけ直す(差が DefaultSettings.readingCorrectionMargin 以上)．
/// 打ったままの読みが候補に無いときは，候補の最後より下にあるとみなして比べる．
/// 打ったままの読みがこちらの読みと違うとき(「nn」の読み方の違いなど)は，比べる相手が違うので直さない
public struct ReadingCorrectionRule: Sendable {
    public var level: TypoCorrectionLevel

    public init(level: TypoCorrectionLevel) {
        self.level = level
    }

    /// 直すならその候補を返す．reading はこちらで組み立てた読み(ひらがな)
    public func correction(among candidates: [ReadingCorrection], reading: String) -> ReadingCorrection? {
        guard level == .standard, let best = candidates.first, let last = candidates.last, !best.isUnchanged else { return nil }
        let typed = candidates.first(where: \.isUnchanged)
        if let typed, typed.reading != KanaWidth.katakana(from: reading) { return nil }
        guard best.reading != KanaWidth.katakana(from: reading) else { return nil }
        let typedScore = typed?.score ?? last.score
        return best.score - typedScore >= DefaultSettings.readingCorrectionMargin ? best : nil
    }
}
