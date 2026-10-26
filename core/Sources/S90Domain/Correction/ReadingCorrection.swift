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
/// 差がそれより小さくても DefaultSettings.readingSuggestionMargin 以上なら，直さずに示すだけにする(打ち間違いと決めつけない)．
/// 打ったままの読みが候補に無いときは，候補の最後より下にあるとみなして比べる．
/// 打ったままの読みがこちらの読みと違うとき(「nn」の読み方の違いなど)は，比べる相手が違うので直さない
public struct ReadingCorrectionRule: Sendable {
    /// 直すか，示すだけか
    public enum Decision: Sendable, Equatable {
        case apply(ReadingCorrection)
        case suggest(ReadingCorrection)

        public var correction: ReadingCorrection {
            switch self {
            case .apply(let correction), .suggest(let correction): correction
            }
        }
    }

    public var level: TypoCorrectionLevel

    public init(level: TypoCorrectionLevel) {
        self.level = level
    }

    /// 直すならその候補を返す．reading はこちらで組み立てた読み(ひらがな)
    public func correction(among candidates: [ReadingCorrection], reading: String) -> ReadingCorrection? {
        guard case .apply(let correction) = decision(among: candidates, reading: reading) else { return nil }
        return correction
    }

    /// 直すか，示すだけか，何もしないか．candidates は点数の高い順
    public func decision(among candidates: [ReadingCorrection], reading: String) -> Decision? {
        guard level == .standard, let best = candidates.first, let last = candidates.last, !best.isUnchanged else { return nil }
        let typed = candidates.first(where: \.isUnchanged)
        if let typed, typed.reading != KanaWidth.katakana(from: reading) { return nil }
        guard best.reading != KanaWidth.katakana(from: reading) else { return nil }
        let gain = best.score - (typed?.score ?? last.score)
        if gain >= DefaultSettings.readingCorrectionMargin { return .apply(best) }
        if gain >= DefaultSettings.readingSuggestionMargin { return .suggest(best) }
        return nil
    }

    /// 同じキーを続けて打った箇所を 1 回にしたキーの並び．母音の重なり(「oo」)と，3 回以上の重なりだけを試す．
    /// 子音の 2 回(「tt」→「っ」)と「nn」(→「ん」)は正しい打ち方なので試さない
    public static func repeatedKeyVariants(of keys: String) -> [String] {
        let characters = Array(keys)
        var variants: [String] = []
        for index in characters.indices.dropFirst() where characters[index] == characters[index - 1] {
            let character = characters[index]
            let tripled = index >= 2 && characters[index - 2] == character
            guard "aiueo".contains(character) || (tripled && character != "n") else { continue }
            // 3 回以上の重なりは，最後の 1 回だけを除く(同じ並びを何度も試さない)
            if index + 1 < characters.count, characters[index + 1] == character { continue }
            var edited = characters
            edited.remove(at: index)
            variants.append(String(edited))
            if variants.count == DefaultSettings.maximumRepeatedKeyVariants { break }
        }
        return variants
    }
}

extension ReadingCorrection {
    /// 直す手間を足したもの(キーの並びを変えてから求めた候補に使う)
    public func adding(cost extra: Double) -> ReadingCorrection {
        ReadingCorrection(keys: keys, reading: reading, score: score - extra, cost: cost + extra)
    }
}

extension ReadingCorrection: CustomStringConvertible, CustomDebugStringConvertible {
    // 打ったキーと読みは入力内容なので，ログには長さと点数だけを出す
    public var description: String { "ReadingCorrection(keysLength: \(keys.count), readingLength: \(reading.count), score: \(score))" }
    public var debugDescription: String { description }
}
