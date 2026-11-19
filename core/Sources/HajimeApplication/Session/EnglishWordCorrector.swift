import HajimeDomain

/// 読みの末尾に打った英単語を見つけて直す(R-02)．「pyてょn」→「python」，「pthon」→「python」．
/// 英語の語の辞書(R-24)にある語は，辞書の書き方にする(「chatgpt」→「ChatGPT」．EnglishLexicon.spelling)．
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
        /// 辞書に無い綴りを似た英単語に直したもの(「pthon」→「python」)．ローマ字として読めない並びはこれになりやすいので，
        /// 日本語の打ち間違い(「tkitou」→ 適当)と取り合ったら日本語に譲る
        var isMisspelling = false
    }

    /// 綴りを直した英単語を，日本語の打ち間違いの見直しにかけるか．ローマ字として読めない並びは綴りの誤りにも
    /// 日本語の打ち間違い(tkitou → 適当)にも見えるので，日本語として直せるなら日本語に譲る
    func yieldsToJapanese(in composition: Composition) -> Bool {
        guard let active, active.isMisspelling else { return false }
        let following = KanaWidth.hiragana(from: followingReading(in: composition).conversionReading)
        return following.isEmpty || !TypoCorrectionRule.startsLikeFollowingEnglish(following)
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
    private let classifier: WordLanguageClassifier

    private(set) var active: Correction?
    /// 最後に補正を求めたときの入力先の文脈．英単語を延ばすとき(handleFollowingRomaji)にも同じ文脈で探す
    private var context = Context()
    /// 利用者が Space で取り消した補正の位置．同じ位置では補正し直さない(Q-01)
    private var dismissedKanaStart: Int?
    /// 打鍵が止まったときに読みの中から英単語にした語．続きを打ったあとの読みで 1 回だけ見分け直す(freezeWordReadAsRomaji)
    private var tentative: TentativeWord?

    /// 打鍵が止まったときに英単語にした語と，その前後の読み．止まったところが語の終わりとは限らず，
    /// 語の途中まで(「めちゃくちゃ」の「metyaku」)を英単語と後ろの日本語(met + 役)に取り違えることがあるため，前の読みを覚えておく
    private struct TentativeWord {
        /// 英単語にする前の読み
        var typed: Composition
        /// 英単語にしたあとの読み
        var frozen: Composition
        var rawStart: Int
        var keys: String
    }

    /// 読みの中の英単語を見分けた結果(freezeWordReadAsRomaji)
    enum RomajiWordOutcome: Equatable {
        /// 読みを変えていない
        case unchanged
        /// 英単語として確定させた
        case frozen
        /// 打鍵が止まったときに英単語にした語を，続きを打ったあとの読みで日本語に戻した
        case restored
    }

    init(lexicon: any EnglishLexicon, settings: any SettingsReading, converter: any KanaKanjiConverting, classifier: WordLanguageClassifier) {
        self.lexicon = lexicon
        self.settings = settings
        self.converter = converter
        self.classifier = classifier
    }

    /// 読みの末尾から英単語を探して，補正を求め直す．
    /// - Parameter context: 入力先の文脈．プログラミング用のアプリでは日本語の文の中の英単語だけを直す(R-06)
    /// 見つけた補正をいったん取り下げる．手がかり(読みのもっともらしさ)を待たずに探したときに，そろうまで補正を見せないために使う．
    /// そろったら update を呼び直す
    func withhold() {
        active = nil
    }

    func update(for composition: Composition, context: Context = Context()) {
        self.context = context
        guard settings.current.correction.english else {
            active = nil
            return
        }
        active = search(in: composition, includingPending: false)
    }

    /// 補正の対象を探す．includingPending なら，打ちかけのローマ字も英単語に含めて探す(英単語を延ばすとき)
    private func search(in composition: Composition, includingPending: Bool) -> Correction? {
        let rule = TypoCorrectionRule(level: settings.current.typoCorrection)
        let customization = settings.current.correction
        let kana = Array(composition.kana)
        // 直さない語を含む部分と，識別子の一部(「user_」「a.」「userN」のあと)は除く
        let tails = rule.tails(in: composition, includingPending: includingPending)
            .filter { $0.kanaStart != dismissedKanaStart && !customization.isException(keys: $0.keys, reading: "") && !readsAsShortJapanese($0.keys) }
            .filter { tail in
                let before = tail.kanaStart > 0 ? kana[tail.kanaStart - 1] : context.precedingCharacter
                return !(before.map(TypoCorrectionRule.continuesIdentifier) ?? false)
                    && (!context.correctsOnlyInJapanese || rule.isInJapaneseSentence(before: kana.prefix(tail.kanaStart), precedingCharacter: context.precedingCharacter))
            }
        // 0. 利用者が足した置き換えの決まり(「teh」→「the」)を，長い部分から探す
        if let tail = tails.first(where: { customization.rule(for: $0.keys) != nil }), let custom = customization.rule(for: tail.keys) {
            return Correction(rawStart: tail.rawStart, kanaStart: tail.kanaStart, keys: tail.keys, word: custom.word)
        }
        // 綴りの誤り．どの部分を調べるかは TypoCorrectionRule.misspellingTails にある
        func misspelling(startingBefore bound: Int?) -> Correction? {
            for tail in rule.misspellingTails(from: tails) where (bound.map({ tail.rawStart < $0 }) ?? true)
                && !TypoCorrectionRule.endsWithJapaneseAfterLetters(tail.keys) {
                if let word = rule.correction(for: tail.keys, isWord: false, suggestions: lexicon.suggestions(for: tail.keys)) {
                    return Correction(rawStart: tail.rawStart, kanaStart: tail.kanaStart, keys: tail.keys, word: word, isMisspelling: true)
                }
            }
            return nil
        }
        // 1. 英単語そのものを，長い部分から探す．ただし，それより長い部分が英字の打ち始めからの綴りの誤りなら，そちらを直す．
        //    「jvascript」の「script」は英単語だが，打ったのは javascript のつもりなので，英単語全体で直す
        if let tail = tails.first(where: { lexicon.isWord($0.keys) }),
            let word = rule.correction(for: tail.keys, isWord: true, suggestions: []) {
            return misspelling(startingBefore: tail.rawStart)
                ?? Correction(rawStart: tail.rawStart, kanaStart: tail.kanaStart, keys: tail.keys, word: lexicon.spelling(of: word) ?? word)
        }
        // 2. 英単語の終わりが次の日本語の綴りにかかったもの(「react」+「wo」)．綴りの誤りより先に調べる
        //    (「reactwo」の「ctwo」に two を返す綴りの候補で，react を two にしないため)
        if let found = wordReadAsRomaji(in: composition, onlyUnreadable: true) {
            return found
        }
        // 3. 綴りの誤り
        return misspelling(startingBefore: nil)
    }

    /// 読み全体が，英語にも日本語にも読める語(「make」→ まけ)で，英語にすると見分けたら英単語として確定させる．
    /// ローマ字入力では日本語を打つのが主なので，前が英語のとき(「Let's」のあと)と，利用者が英語にすると決めた語だけを英語にする
    /// (WordLanguageJudge の japaneseFirst)．打鍵が止まったときと変換・確定の前に呼ぶ．確定させたら true
    func freezeEnglishWord(in composition: inout Composition, context: WordLanguageContext) -> Bool {
        guard active == nil, settings.current.correction.english, settings.current.typoCorrection != .off,
            let keys = composition.rawKeys, !keys.isEmpty, keys.allSatisfy({ $0.isASCII && $0.isLowercase && $0.isLetter }),
            composition.pending.isEmpty || composition.pending == "n",
            WordLanguageClassifier.reading(of: keys) != nil,
            classifier.language(of: keys, context: context, mode: .japaneseFirst) == .english else { return false }
        active = Correction(rawStart: 0, kanaStart: 0, keys: keys, word: lexicon.spelling(of: keys) ?? keys)
        commit(into: &composition)
        return true
    }

    /// ローマ字として読んだかなが，英単語にしない長さ(設定)以下か(「make」→ まけ，「line」→ りね)．
    /// ローマ字として読めない並び(「pthon」)は日本語ではないので false．利用者が「いつも英語」にした語も false．
    /// 前の語で英語と見分ける語(「Let's make」)は freezeEnglishWord が見分け方の決まりで決める
    private func readsAsShortJapanese(_ keys: String) -> Bool {
        guard let reading = WordLanguageClassifier.reading(of: keys),
              !settings.current.wordLanguage.englishWords.contains(keys.lowercased()) else { return false }
        return reading.count <= settings.current.englishSkipLength
    }

    /// ローマ字として読めてしまう英単語を読みの中から探し，見つけたら英単語として確定させる(「gitwotukau」→「gitを使う」)．
    /// 変換を使うので，打鍵ごとには呼ばず，打鍵が止まったときと変換・確定の前に呼ぶ．
    ///
    /// 打鍵が止まったとき(tentatively)に英単語にした語は，続きを打ったあとに呼ばれたとき，英単語にする前の読みに続きを足して見分け直す．
    /// 同じ語を英単語と見分ければそのままにし，見分けなければ日本語に戻す(「metyaku」で止まり「tya」と続けた「めちゃくちゃ」)．
    /// 見分け直すのは 1 回だけ(続きを打って確かめた語は，それ以上は戻さない)
    func freezeWordReadAsRomaji(in composition: inout Composition, tentatively: Bool = false) -> RomajiWordOutcome {
        guard active == nil else { return .unchanged }
        var base = composition
        var found: Correction?
        var restored = false
        if let previous = tentative, let typed = typedBeforeTentativeWord(previous, in: composition) {
            tentative = nil
            found = wordReadAsRomaji(in: typed, onlyUnreadable: false)
            if found?.rawStart == previous.rawStart, found?.keys == previous.keys {
                // 同じ語だった．今の読みのまま，後ろに別の英単語が無いかを探す
                found = wordReadAsRomaji(in: composition, onlyUnreadable: false)
            } else {
                base = typed
                restored = true
            }
        } else {
            found = wordReadAsRomaji(in: composition, onlyUnreadable: false)
        }
        guard let found else {
            if restored { composition = base }
            return restored ? .restored : .unchanged
        }
        composition = base
        active = found
        commit(into: &composition)
        tentative = tentatively ? TentativeWord(typed: base, frozen: composition, rawStart: found.rawStart, keys: found.keys) : nil
        return .frozen
    }

    /// 打鍵が止まったときに英単語にした語(word)を英単語にしなかった読みに，そのあとに打ったキーを足したもの．
    /// 英単語にしたあとに打ったのがローマ字だけで，打ち終えていて(打ちかけのローマ字が無い)，
    /// ほかに読みが変わっていない(別の英単語の補正・打ち間違いの訂正・消した文字が無い)ときだけ返す
    private func typedBeforeTentativeWord(_ word: TentativeWord, in composition: Composition) -> Composition? {
        guard let keys = composition.rawKeys, let frozenKeys = word.frozen.rawKeys, keys.count > frozenKeys.count, keys.hasPrefix(frozenKeys),
            composition.pending.isEmpty || composition.pending == "n" else { return nil }
        let following = keys.dropFirst(frozenKeys.count)
        guard following.allSatisfy({ ($0.isASCII && $0.isLetter && $0.isLowercase) || $0 == "-" }),
            replaying(following, onto: word.frozen).conversionReading == composition.conversionReading else { return nil }
        return replaying(following, onto: word.typed)
    }

    /// 打ったときと同じ順にキーを足す．「nn」のあとの母音の読みも，打つときと同じ決まりで選び，打ち終えた読みで選び直す
    /// (呼ばれるのは打鍵が止まったときと変換・確定の前で，今の読みも選び直してある．InputSession.resolveSettledNasalReadings)
    private func replaying(_ keys: Substring, onto base: Composition) -> Composition {
        var composition = base
        let resolver = NasalReadingResolver(converter: converter)
        for key in keys {
            composition.insertRomaji(key)
            resolver.resolve(&composition)
        }
        _ = resolver.resolveSettled(&composition)
        return composition
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
        // 英小文字だけの部分(と，読めない並びを含む部分)だけを調べる．長い読みでは区切りが多いので，要らない部分は作らない
        // 英単語の後ろの読み．英単語の終わりの位置で決まるので，同じ位置は 1 回だけ組み立てる
        var followings: [Int: Composition] = [:]
        for tail in composition.tails(requiresInvalidRomaji: onlyUnreadable, requiresLowercaseLetters: true) where tail.kanaStart != dismissedKanaStart {
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
                let following: Composition
                if let made = followings[end] {
                    following = made
                } else {
                    var made = Composition()
                    for key in keys[end...] { made.insertRomaji(key) }
                    followings[end] = made
                    following = made
                }
                guard !following.containsInvalidRomaji, following.pending.isEmpty || following.pending == "n",
                    TypoCorrectionRule.startsLikeFollowingEnglish(following.conversionReading),
                    lexicon.isWord(word), !customization.isException(keys: word, reading: ""), !readsAsShortJapanese(word) else { continue }
                let score = converter.plausibility(of: following.conversionReading)
                let whole = japanese ?? converter.plausibility(of: String(kana[tail.kanaStart...]))
                japanese = whole
                guard rule.readsAsEnglish(endsOnBoundary: false, japanese: whole, following: score, followingReading: following.conversionReading) else { continue }
                let gain = score - whole
                if best.map({ gain > $0.gain }) ?? true {
                    best = (gain, Correction(rawStart: tail.rawStart, kanaStart: tail.kanaStart, keys: word, word: lexicon.spelling(of: word) ?? word))
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
            // 英字のまま残った．「pythons」のように別の英単語になるかもしれない．
            // 英字を打ち続けているので，最後の打ちかけのローマ字(「jvascript」の t)も英単語に含めて探し直す．
            // 含めずに求め直すと補正が消え，英単語全体(javascript)を直す機会を失う
            if let found = search(in: composition, includingPending: true) {
                active = found
                return .waiting
            }
            return .reevaluate
        }
        if following.pending.isEmpty, !following.kana.isEmpty {
            // 綴りを直した英単語のあとが，英単語に続く語(「が」「を」「です」)で始まらなければ確定させない．
            // 日本語の打ち間違い(tkitou → 適当)かもしれないので，打鍵が止まったときの見直し(yieldsToJapanese)で決める
            if current.isMisspelling, !TypoCorrectionRule.startsLikeFollowingEnglish(KanaWidth.hiragana(from: following.conversionReading)) {
                return .waiting
            }
            commit(into: &composition)
            return .reevaluate
        }
        // 「s」のように英単語の続きかもしれないキーは，英単語として読めるならそちらを優先する
        let extended = current.keys + followingKeys(in: composition)
        if lexicon.isWord(extended), !readsAsShortJapanese(extended) {
            active = Correction(rawStart: current.rawStart, kanaStart: current.kanaStart, keys: extended, word: lexicon.spelling(of: extended) ?? extended)
        }
        // 続けて打ったキーまで含めると，いま直している部分より前から始まる英単語になることがある．
        // 「jvascri」の「scri」を直したあとに「pt」と打つと，「jvascript」全体を javascript に直せる．
        // 子音で終わる英単語は最後のキーが打ちかけのローマ字として残るので，打ちかけを含めて探す
        if let current = active, let longer = search(in: composition, includingPending: true), longer.rawStart < current.rawStart {
            active = longer
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
        tentative = nil
        context = Context()
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
