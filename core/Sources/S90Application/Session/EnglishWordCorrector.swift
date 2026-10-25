import S90Domain

/// 読みの末尾に打った英単語を見つけて直す(R-02)．「pyてょn」→「python」，「pthon」→「python」．
///
/// 文の途中の英単語(「このばーじょんの」+「python」)も対象にする．
/// 直した英単語のあとに日本語を続けて打つと，英単語を読みの中に確定させる(「python」+「ha」→「pythonは」)．
/// どの部分を英単語とみなすかの規則は TypoCorrectionRule にある．この型は，その規則を使って補正の状態を進める
@MainActor
final class EnglishWordCorrector {
    /// 打ったキーの rawStart 番目から始まる keys(読みでは kanaStart 文字目から)を word に直している
    struct Correction: Equatable {
        var rawStart: Int
        var kanaStart: Int
        var keys: String
        var word: String
    }

    /// 英単語のあとにローマ字を打ったときの扱い
    enum FollowingInput: Equatable {
        /// まだかなになり切っていないので，補正を保って次のキーを待つ(「python」+「h」)
        case waiting
        /// 補正を求め直す．英単語を確定させたあとか，英字のまま残ったとき
        case reevaluate
    }

    private let lexicon: any EnglishLexicon
    private let settings: any SettingsReading

    private(set) var active: Correction?
    /// 利用者が Space で取り消した補正の位置．同じ位置では補正し直さない(Q-01)
    private var dismissedKanaStart: Int?

    init(lexicon: any EnglishLexicon, settings: any SettingsReading) {
        self.lexicon = lexicon
        self.settings = settings
    }

    /// 読みの末尾から英単語を探して，補正を求め直す
    func update(for composition: Composition) {
        let rule = TypoCorrectionRule(level: settings.current.typoCorrection)
        let tails = rule.tails(in: composition).filter { $0.kanaStart != dismissedKanaStart }
        // 1. 英単語そのものを，長い部分から探す
        if let tail = tails.first(where: { lexicon.isWord($0.keys) }),
            let word = rule.correction(for: tail.keys, isWord: true, suggestions: []) {
            active = Correction(rawStart: tail.rawStart, kanaStart: tail.kanaStart, keys: tail.keys, word: word)
            return
        }
        // 2. 綴りの誤りは，いちばん短い部分だけで探す．長い部分で探すと前の日本語まで英単語に飲み込む
        if let tail = tails.last,
            let word = rule.correction(for: tail.keys, isWord: false, suggestions: lexicon.suggestions(for: tail.keys)) {
            active = Correction(rawStart: tail.rawStart, kanaStart: tail.kanaStart, keys: tail.keys, word: word)
            return
        }
        active = nil
    }

    /// 英単語のあとにローマ字を打った直後に呼ぶ．あとのキーがかなになり切っていれば英単語を確定させる
    func handleFollowingRomaji(in composition: inout Composition) -> FollowingInput {
        guard let current = active else { return .reevaluate }
        let following = followingReading(in: composition)
        if following.kana.contains(where: { $0.isASCII && $0.isLetter }) {
            // 英字のまま残った．「pythons」のように別の英単語になるかもしれない
            return .reevaluate
        }
        if following.pending.isEmpty, !following.kana.isEmpty {
            commit(into: &composition)
            return .reevaluate
        }
        // 「s」のように英単語の続きかもしれないキーは，英単語として読めるならそちらを優先する
        let extended = current.keys + followingKeys(in: composition)
        if lexicon.isWord(extended) {
            active = Correction(rawStart: current.rawStart, kanaStart: current.kanaStart, keys: extended, word: extended)
        }
        return .waiting
    }

    /// 直した英単語を読みの中に確定させる．記号や数字を打つ前にも呼ぶ(「python」+「,」→「python、」)
    func commit(into composition: inout Composition) {
        guard let current = active else { return }
        composition.freeze(
            rawStart: current.rawStart,
            kanaStart: current.kanaStart,
            keys: current.keys,
            as: current.word,
            replaying: followingKeys(in: composition)
        )
        active = nil
        dismissedKanaStart = nil
    }

    /// 補正の直後の Space で，打ったままに戻す(Q-01)．戻したら true
    func dismiss() -> Bool {
        guard let current = active else { return false }
        dismissedKanaStart = current.kanaStart
        active = nil
        return true
    }

    func reset() {
        active = nil
        dismissedKanaStart = nil
    }

    /// 直した英単語のあとに打ったキーを，日本語として読んだもの
    func followingReading(in composition: Composition) -> Composition {
        var following = Composition()
        for key in followingKeys(in: composition) { following.insertRomaji(key) }
        return following
    }

    private func followingKeys(in composition: Composition) -> String {
        guard let current = active else { return "" }
        return String((composition.rawKeys ?? "").dropFirst(current.rawStart + current.keys.count))
    }
}
