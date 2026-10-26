import S90Domain

/// 日本語の打ち間違いを直す(R-02)．「kyounotenkihayoudesune」→「今日の天気は良いですね」，「koonnichiha」→「こんにちは」．
///
/// 打ったキー全体を Zenzai で見直し，ReadingCorrectionRule で決めた強さで扱う．
/// - 確かなときは直して見せる．直したことは画面に出し，Esc で打ったままに戻せる
/// - 確かでないときは直さず「もしかして」と示すだけにし，Tab で直せるようにする
///
/// 見直すのは，ライブ変換で打鍵が止まったときと，変換を始めるとき．打鍵ごとには見直さない(重いため)．
/// 直したあとに打ったキーは直した読みに続けて入れ，戻すときは打ったままの読みに同じキーを入れ直す
@MainActor
final class ReadingCorrector {
    /// 直した結果
    private struct Applied {
        /// 直す前の読み
        var typed: Composition
        /// 直した読みのキーの数．これより後ろのキーは，直したあとに打ったもの
        var correctedKeyCount: Int
    }

    private let converter: any KanaKanjiConverting
    private let settings: any SettingsReading

    private var applied: Applied?
    /// 示しているだけの直した読み
    private(set) var suggestion: Composition?
    /// 利用者が戻した，打ったキー．このキーで始まるあいだは直し直さない
    private var dismissedKeys: String?
    /// 前に見直したキーと結果．同じキーを何度も Zenzai に問い合わせない
    private var lastReview: (keys: String, decision: ReadingCorrectionRule.Decision?)?
    /// 別のところで求めた訂正の候補(キーの並びごと)．入力を最後まで確定したら捨てる
    private var provided: [String: [ReadingCorrection]] = [:]
    /// 訂正を別のところで求めるか．true なら，求め終わっていないキーは見直さない(入力の処理を待たせない)
    private let usesProvidedCorrections: Bool

    init(converter: any KanaKanjiConverting, settings: any SettingsReading, usesProvidedCorrections: Bool = false) {
        self.converter = converter
        self.settings = settings
        self.usesProvidedCorrections = usesProvidedCorrections
    }

    /// 見直しに要るのに，まだ求めていないキーの並び(打ったキーと，重なりを 1 回にした並び)．要らなければ nil
    func pendingKeys(for composition: Composition) -> [String]? {
        guard usesProvidedCorrections, let keys = reviewableKeys(of: composition) else { return nil }
        let all = [keys] + (settings.current.correction.repeatedKeys ? ReadingCorrectionRule.repeatedKeyVariants(of: keys) : [])
        let missing = all.filter { provided[$0] == nil }
        return missing.isEmpty ? nil : missing
    }

    /// 別のところで求めた訂正の候補を受け取る
    func provide(_ corrections: [String: [ReadingCorrection]]) {
        provided.merge(corrections) { _, new in new }
        if provided.count > DefaultSettings.maximumProvidedCorrections { provided = corrections }
    }

    /// 見直す部分．読みに英単語(確定させた英単語や Shift で打った英字)があれば，最後の英単語より後ろの日本語だけを見直す．
    /// 英単語は英単語の補正(EnglishWordCorrector)の受け持ちで，日本語の打ち間違いとして直すと「python」が「ぴょん」になる
    private struct Region {
        /// 見直さない前の部分(英単語まで)．直したキーはこれに続けて入れ直す
        var prefix: Composition?
        /// 見直すキー
        var keys: String
        /// 見直すキーの読み
        var reading: String
    }

    /// 見直せる部分．キーが英小文字と「-」だけで，戻した並びで始まらず，長すぎないもの
    private func reviewableRegion(of typed: Composition) -> Region? {
        guard let all = typed.rawKeys, let boundary = typed.boundaryAfterEnglish,
            typed.pending.isEmpty || typed.pending == "n",
            !(dismissedKeys.map(all.hasPrefix) ?? false) else { return nil }
        // 「nn」のあとの母音をな行で読んだところ(「honno」→「本の」)は，訂正を求める変換器でも同じ読みになるよう打ち分けた並びにする．
        // 打ったままの並びを渡すと，変換器は「ほんお」と読み，こちらの読みと比べられないので直せない
        let keys = typed.unambiguousKeys(from: boundary) ?? String(all.dropFirst(boundary.rawCount))
        // 比べる読みはキーから組み立てる．綴りを直した英単語(「gakusri」の「sri」→「bride」)を入れた読みは，
        // 訂正を求める変換器の読み(「がくsり」)と食い違い，比べられずに直せなくなる
        let reading = KeyEditSearch.rawReading(of: keys)
        guard !keys.isEmpty, keys.count <= DefaultSettings.maximumKeysForCorrection, keys.allSatisfy(Self.isLetterKey) else { return nil }
        guard boundary.rawCount > 0 else { return Region(prefix: nil, keys: keys, reading: reading) }
        // 英単語の後ろが短いと，打ち間違いと見分けにくく直す意味も薄い
        guard keys.count >= DefaultSettings.minimumKeysForLiveCorrection else { return nil }
        return Region(prefix: typed.truncated(to: boundary), keys: keys, reading: reading)
    }

    private func reviewableKeys(of composition: Composition) -> String? {
        reviewableRegion(of: typedComposition(from: composition) ?? composition)?.keys
    }

    /// 見直さない前の部分(英単語まで)の読み．訂正を別のところで求めるとき，左の文脈に足す
    func unreviewedPrefix(of composition: Composition) -> String? {
        reviewableRegion(of: typedComposition(from: composition) ?? composition)?.prefix?.displayReading
    }

    /// 直した読みを見せているか
    var isApplied: Bool { applied != nil }

    /// この読みは見直し済みか(打ったキーが前に見直したときと同じか)
    func isReviewed(_ composition: Composition) -> Bool {
        let typed = typedComposition(from: composition) ?? composition
        return lastReview?.keys == typed.rawKeys
    }

    /// 打ったままの読み．直したあとに打ったキーも入れる．直していなければ nil
    func typedComposition(from current: Composition) -> Composition? {
        guard let applied, let keys = current.rawKeys, keys.count >= applied.correctedKeyCount else { return nil }
        let following = keys.dropFirst(applied.correctedKeyCount)
        guard following.allSatisfy(Self.isLetterKey) else { return nil }
        var typed = applied.typed
        let resolver = NasalReadingResolver(converter: converter)
        for key in following {
            typed.insertRomaji(key)
            resolver.resolve(&typed)
        }
        return typed
    }

    /// 打ったキー全体を見直し，直すなら composition を直した読みにする．
    /// 前に直したものが，続けて打ったキーでもっともらしくなくなったら，打ったままに戻す
    func review(_ composition: inout Composition, makeComposition: () -> Composition) {
        // 訂正をまだ求め終わっていなければ，今の表示のまま待つ(直したものを打ったままに戻したりしない)
        if pendingKeys(for: composition) != nil { return }
        suggestion = nil
        suggestsMisreading = false
        let typed = typedComposition(from: composition) ?? composition
        guard let region = reviewableRegion(of: typed) else {
            lastReview = (typed.rawKeys ?? "", nil)
            return
        }
        let current = settings.current
        // 誤りの種類ごとのオン・オフと，直さない語(設定)
        let checksTypos = current.typoCorrection == .standard && current.correction.japanese
            && !current.correction.isException(keys: region.keys, reading: region.reading)
        let reviewedKeys = typed.rawKeys ?? ""
        let decision: ReadingCorrectionRule.Decision?
        if let lastReview, lastReview.keys == reviewedKeys {
            decision = lastReview.decision
        } else {
            decision = checksTypos ? self.decision(forKeys: region.keys, reading: region.reading) : nil
            lastReview = (reviewedKeys, decision)
        }
        if decision == nil, current.misreadings, applied == nil, let suggested = misreadingSuggestion(for: typed, makeComposition: makeComposition) {
            // よくある読み違い(「ふいんき」)は，打ち間違いではないので直さず，「もしかして」と示すだけにする
            suggestion = suggested
            suggestsMisreading = true
            return
        }
        let base = { region.prefix ?? makeComposition() }
        switch decision {
        case .apply(let correction):
            guard let corrected = compose(correction.keys, onto: base),
                corrected.conversionReading != typed.conversionReading else {
                if applied != nil { composition = typed }
                applied = nil
                return
            }
            applied = Applied(typed: typed, correctedKeyCount: corrected.rawKeys?.count ?? 0)
            composition = corrected
        case .suggest(let correction):
            if applied != nil { composition = typed }
            applied = nil
            suggestion = compose(correction.keys, onto: base)
        case nil:
            if applied != nil { composition = typed }
            applied = nil
        }
    }

    /// 示していた直した読みにする(Tab)．直したら true．
    /// 読み違いを直したときは，打ったキーと読みが対応しなくなるので，Esc で戻せる直しにはしない(Backspace で消せる)
    func acceptSuggestion(_ composition: inout Composition) -> Bool {
        guard let suggested = suggestion else { return false }
        if suggestsMisreading {
            composition = suggested
            suggestion = nil
            suggestsMisreading = false
            applied = nil
            return true
        }
        applied = Applied(typed: composition, correctedKeyCount: suggested.rawKeys?.count ?? 0)
        composition = suggested
        suggestion = nil
        return true
    }

    /// 示していた読みを出さないようにする．利用者が取り下げたのではないので，次に見直したときはまた示せる
    func withdrawSuggestion() {
        suggestion = nil
    }

    /// 示していた読みを取り下げる(Esc)．このキーで始まるあいだは示し直さない．取り下げたら true
    func dismissSuggestion(for composition: Composition) -> Bool {
        guard suggestion != nil else { return false }
        suggestion = nil
        dismissedKeys = composition.rawKeys
        return true
    }

    /// 打ったままの読みに戻す(Esc)．戻したら true
    func revert(_ composition: inout Composition) -> Bool {
        guard let typed = typedComposition(from: composition) else {
            applied = nil
            return false
        }
        dismissedKeys = typed.rawKeys
        composition = typed
        applied = nil
        suggestion = nil
        return true
    }

    /// 読みを編集した(Backspace)．直した部分まで消したら，直した読みのまま受け入れたことにする
    func didEdit(_ composition: Composition) {
        suggestion = nil
        if let applied, (composition.rawKeys?.count ?? 0) < applied.correctedKeyCount {
            self.applied = nil
        }
        if let dismissed = dismissedKeys, let keys = composition.rawKeys, !keys.hasPrefix(dismissed) {
            dismissedKeys = nil
        }
    }

    /// 打ち続けた．示していた読みは古くなるので消す．英小文字と「-」のほかのキー(「'」や「z.」の「.」)を打ったら，
    /// 打ったままの読みを組み立て直せないので，直したものをそのまま受け入れたことにする
    func didType(_ key: Character) {
        suggestion = nil
        if !Self.isLetterKey(key) { applied = nil }
    }

    /// 英字のまま確定した数字や記号を足した．直したものはそのまま受け入れたことにする
    func didInsertLiteral() {
        applied = nil
        suggestion = nil
    }

    /// 読みの組み立てが変わった(英単語を確定させた)．打ったキーが同じでも見直し直す
    func forgetReview() {
        lastReview = nil
    }

    func reset() {
        applied = nil
        suggestion = nil
        dismissedKeys = nil
        lastReview = nil
        provided = [:]
    }

    // MARK: - 内部

    /// 示している読みが，よくある読み違いを直したものか
    private var suggestsMisreading = false

    /// 読みの末尾がよくある読み違いなら，正しい読みにした読み(Misreadings)
    private func misreadingSuggestion(for typed: Composition, makeComposition: () -> Composition) -> Composition? {
        let reading = typed.conversionReading
        guard let match = Misreadings.suffixEntry(in: reading), match.entry.correctReading != match.entry.reading else { return nil }
        var suggested = makeComposition()
        suggested.insertKana(String(reading.prefix(match.start)) + match.entry.correctReading)
        return suggested
    }

    private func decision(forKeys keys: String, reading: String) -> ReadingCorrectionRule.Decision? {
        // 別のところで求めるときは，求め終わっていなければ見直さない(入力の処理を待たせない)
        func corrections(_ keys: String) -> [ReadingCorrection]? {
            if let found = provided[keys] { return found }
            return usesProvidedCorrections ? nil : converter.typoCorrections(forKeys: keys)
        }
        guard var candidates = corrections(keys) else { return nil }
        // 文の末尾で同じキーを続けて 2 回打った誤りは Zenzai の訂正では探さないので，1 回にした並びも見直して比べる．
        // 直すと決まったあとも試す．試さないと，重なりを 1 回にした文よりもっともらしくない文に直すことがある(評価で 1 件 → 4 件)
        for variant in settings.current.correction.repeatedKeys ? ReadingCorrectionRule.repeatedKeyVariants(of: keys) : [] {
            guard let found = corrections(variant) else { return nil }
            candidates += found.map { $0.adding(cost: DefaultSettings.repeatedKeyCost) }
        }
        candidates.sort { $0.score > $1.score }
        return ReadingCorrectionRule(level: settings.current.typoCorrection, sensitivity: settings.current.correctionSensitivity,
                                     suggests: settings.current.showsSuggestions).decision(among: candidates, reading: reading)
    }

    /// 打ったときと同じ順にキーを入れ直し，「nn」のあとの母音の読みも打つときと同じ決まりで選ぶ．
    /// base は入れ直す前の読み(英単語までの部分か，空の読み)
    private func compose(_ keys: String, onto base: () -> Composition) -> Composition? {
        var composition = base()
        let resolver = NasalReadingResolver(converter: converter)
        for key in keys {
            composition.insertRomaji(key)
            resolver.resolve(&composition)
        }
        return composition.isEmpty ? nil : composition
    }

    /// 見直しと組み立て直しに使えるキー(英小文字と長音の「-」)
    private static func isLetterKey(_ key: Character) -> Bool {
        (key.isASCII && key.isLetter && key.isLowercase) || key == "-"
    }
}
