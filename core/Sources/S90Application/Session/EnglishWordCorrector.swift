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

    /// 補正を求めるときの入力先の文脈(R-06)
    struct Context {
        /// 日本語の文の中にある英単語だけを直すか(プログラミング用のアプリ)
        var correctsOnlyInJapanese = false
        /// 組み立てを始める前の，入力位置の直前の文字
        var precedingCharacter: Character?
    }

    private let lexicon: any EnglishLexicon
    private let settings: any SettingsReading
    private let converter: any KanaKanjiConverting

    private(set) var active: Correction?
    /// 利用者が Space で取り消した補正の位置．同じ位置では補正し直さない(Q-01)
    private var dismissedKanaStart: Int?

    init(lexicon: any EnglishLexicon, settings: any SettingsReading, converter: any KanaKanjiConverting) {
        self.lexicon = lexicon
        self.settings = settings
        self.converter = converter
    }

    /// 読みの末尾から英単語を探して，補正を求め直す．
    /// - Parameter context: 入力先の文脈．プログラミング用のアプリでは日本語の文の中の英単語だけを直す(R-06)
    func update(for composition: Composition, context: Context = Context()) {
        let rule = TypoCorrectionRule(level: settings.current.typoCorrection)
        let customization = settings.current.correction
        guard customization.english else {
            active = nil
            return
        }
        let kana = Array(composition.kana)
        // 直さない語を含む部分と，識別子の一部(「user_」「a.」「userN」のあと)は除く
        let tails = rule.tails(in: composition)
            .filter { $0.kanaStart != dismissedKanaStart && !customization.isException(keys: $0.keys, reading: "") }
            .filter { tail in
                let before = tail.kanaStart > 0 ? kana[tail.kanaStart - 1] : context.precedingCharacter
                return !(before.map(TypoCorrectionRule.continuesIdentifier) ?? false)
                    && (!context.correctsOnlyInJapanese || rule.isInJapaneseSentence(before: kana.prefix(tail.kanaStart), precedingCharacter: context.precedingCharacter))
            }
        // 0. 利用者が足した置き換えの決まり(「teh」→「the」)を，長い部分から探す
        if let tail = tails.first(where: { customization.rule(for: $0.keys) != nil }), let custom = customization.rule(for: tail.keys) {
            active = Correction(rawStart: tail.rawStart, kanaStart: tail.kanaStart, keys: tail.keys, word: custom.word)
            return
        }
        // 1. 英単語そのものを，長い部分から探す
        if let tail = tails.first(where: { lexicon.isWord($0.keys) }),
            let word = rule.correction(for: tail.keys, isWord: true, suggestions: []) {
            active = Correction(rawStart: tail.rawStart, kanaStart: tail.kanaStart, keys: tail.keys, word: word)
            return
        }
        // 2. 英単語の終わりが次の日本語の綴りにかかったもの(「react」+「wo」)
        if let found = wordReadAsRomaji(in: composition, onlyUnreadable: true) {
            active = found
            return
        }
        // 3. 綴りの誤りは，いちばん短い部分だけで探す．長い部分で探すと前の日本語まで英単語に飲み込む
        if let tail = tails.last,
            let word = rule.correction(for: tail.keys, isWord: false, suggestions: lexicon.suggestions(for: tail.keys)) {
            active = Correction(rawStart: tail.rawStart, kanaStart: tail.kanaStart, keys: tail.keys, word: word)
            return
        }
        active = nil
    }

    /// ローマ字として読めてしまう英単語を読みの中から探し，見つけたら英単語として確定させる(「gitwotukau」→「gitを使う」)．
    /// 変換を使うので，打鍵ごとには呼ばず，打鍵が止まったときと変換・確定の前に呼ぶ．確定させたら true
    func freezeWordReadAsRomaji(in composition: inout Composition) -> Bool {
        guard active == nil, let found = wordReadAsRomaji(in: composition, onlyUnreadable: false) else { return false }
        active = found
        commit(into: &composition)
        return true
    }

    /// 英単語の終わりがローマ字の綴りの途中にかかり，かなとしては読めてしまう英単語を探す．
    /// 「react」+「wo」の「two」，「git」+「wo」のように，英単語のあとに日本語を続けたときだけ見つかる(TypoCorrectionRule.readsAsEnglish)
    /// - Parameter onlyUnreadable: ローマ字として読めない並び(「react」の「c」)を含む部分だけを調べる．
    ///   打鍵ごとに調べるときに使い，英単語の辞書を引く回数を抑える
    private func wordReadAsRomaji(in composition: Composition, onlyUnreadable: Bool) -> Correction? {
        let rule = TypoCorrectionRule(level: settings.current.typoCorrection)
        let customization = settings.current.correction
        guard customization.english, rule.level != .off,
            composition.pending.isEmpty || composition.pending == "n", let raw = composition.rawKeys else { return nil }
        let aligned = Set(composition.boundaries.map(\.rawCount))
        let keys = Array(raw)
        let kana = Array(composition.conversionReading)
        var best: (gain: Double, correction: Correction)?
        for tail in composition.tails() where tail.kanaStart != dismissedKanaStart && tail.keys.allSatisfy({ $0.isASCII && $0.isLowercase && $0.isLetter }) {
            if onlyUnreadable, !tail.containsInvalidRomaji { continue }
            // 英単語のすぐ後ろ(「python」+「no」)は日本語の助詞が来るところなので，続けて英単語を探さない
            if tail.kanaStart > 0, Composition.isAlphanumeric(kana[tail.kanaStart - 1]) { continue }
            var japanese: Double?
            let longest = min(tail.keys.count - 1, DefaultSettings.maximumWordReadAsRomajiLength)
            guard longest >= DefaultSettings.minimumWordReadAsRomajiLength else { continue }
            for length in stride(from: longest, through: DefaultSettings.minimumWordReadAsRomajiLength, by: -1) {
                let end = tail.rawStart + length
                // 終わりがかなの区切りに合う語(「kite」→ きて)は日本語として打ったものとみなす
                guard !aligned.contains(end) else { continue }
                let word = String(keys[tail.rawStart..<end])
                // 英単語の後ろは，かなになり切る日本語でなければならない
                var following = Composition()
                for key in keys[end...] { following.insertRomaji(key) }
                guard !following.containsInvalidRomaji, following.pending.isEmpty || following.pending == "n",
                    TypoCorrectionRule.startsLikeFollowingEnglish(following.conversionReading),
                    lexicon.isWord(word), !customization.isException(keys: word, reading: "") else { continue }
                let score = converter.plausibility(of: following.conversionReading)
                let whole = japanese ?? converter.plausibility(of: String(kana[tail.kanaStart...]))
                japanese = whole
                guard rule.readsAsEnglish(endsOnBoundary: false, japanese: whole, following: score, followingReading: following.conversionReading) else { continue }
                let gain = score - whole
                if best.map({ gain > $0.gain }) ?? true {
                    best = (gain, Correction(rawStart: tail.rawStart, kanaStart: tail.kanaStart, keys: word, word: word))
                }
            }
        }
        return best?.correction
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

    /// 直した英単語ではなく，打ったとおりの英字で確定させる．英単語のあとに識別子の続き(大文字・数字・「_」)を打ったとき(R-06)．
    /// 「pthon」+「N」を「pythonN」にしないため
    func commitAsTyped(into composition: inout Composition) {
        guard var current = active else { return }
        current.word = current.keys
        active = current
        commit(into: &composition)
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
