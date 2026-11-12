/// 2 つのモデルの第 1 候補が食い違ったときに，どちらを第 1 候補にするかを決める規則(ADR 0016 の案 2)．
///
/// - 今の第 1 候補(主のモデルの結果)を残すのが既定．もう一方のモデルの候補は，2 つのモデルの対数確率の重み付きの和で，
///   決めた差(margin)を超えて上回ったときだけ第 1 候補にする．同じモデルの中で比べ直しても第 1 候補は良くならないので，
///   別のモデルの点数を足して初めて選び直す意味がある
/// - もう一方のモデルの候補は，読みにそろえられたもの(辞書の語の読みで読み全体を作れるもの)だけを渡す
public enum FirstCandidateArbitration {
    /// 2 つの表記それぞれの，2 つのモデルの log P(表記, 出力の終わり | 読み, 文脈)
    public struct Scores: Sendable, Equatable {
        /// 今の第 1 候補を，主のモデルで測った点数
        public var currentByMain: Double
        /// もう一方のモデルの候補を，主のモデルで測った点数
        public var challengerByMain: Double
        /// 今の第 1 候補を，もう一方のモデルで測った点数
        public var currentByOther: Double
        /// もう一方のモデルの候補を，もう一方のモデルで測った点数
        public var challengerByOther: Double

        public init(currentByMain: Double, challengerByMain: Double, currentByOther: Double, challengerByOther: Double) {
            self.currentByMain = currentByMain
            self.challengerByMain = challengerByMain
            self.currentByOther = currentByOther
            self.challengerByOther = challengerByOther
        }
    }

    /// もう一方のモデルの候補を第 1 候補にするか
    /// - Parameters:
    ///   - weight: もう一方のモデルの点数にかける重み
    ///   - margin: もう一方のモデルの候補が上回らなければならない差
    public static func prefersChallenger(_ scores: Scores, weight: Double, margin: Double) -> Bool {
        let challenger = scores.challengerByMain + weight * scores.challengerByOther
        let current = scores.currentByMain + weight * scores.currentByOther
        guard challenger.isFinite, current.isFinite else { return false }
        return challenger - current > margin
    }
}
