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

    /// 見直しに要るのに，まだ求めていないキーの並び(読みに合わせて綴り直したキー・打ったままのキー・重なりを 1 回にした並び)．要らなければ nil
    /// final は打ち終えたとき(Space で変換する)．かなになり切っていない末尾のローマ字(「…ましょうak」の k)も見直す
    func pendingKeys(for composition: Composition, final: Bool = false) -> [String]? {
        guard usesProvidedCorrections, let region = reviewableRegion(of: typedComposition(from: composition) ?? composition, final: final) else { return nil }
        let all = requiredKeys(for: region)
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
        /// 見直すキー(読みに合わせて綴り直した並び)
        var keys: String
        /// 打ったままのキー．直さない語句(設定)は打ったとおりの綴りでも比べる
        var typedKeys: String
        /// 見直すキーの読み
        var reading: String
    }

    /// 見直せる部分．キーが英小文字と「-」だけで，戻した並びで始まらず，長すぎないもの．
    /// 打っている途中は，かなになり切っていないローマ字が末尾にあれば見直さない(打ちかけの「k」を余分な 1 打として消さない)．
    /// 打ち終えたとき(final)は，それも打ち間違いとして見直す
    private func reviewableRegion(of typed: Composition, final: Bool = false) -> Region? {
        guard let all = typed.rawKeys, let boundary = typed.boundaryAfterEnglish,
            final || typed.pending.isEmpty || typed.pending == "n",
            !(dismissedKeys.map(all.hasPrefix) ?? false) else { return nil }
        // 「nn」のあとをな行で読んだところは綴り直す．訂正は打ったままの読みと比べるので，読みがそろっていないと直せない
        guard let keys = typed.spelledKeys(from: boundary.rawCount) else { return nil }
        // 読みはキーから作る．綴りを直した英単語を見せているとき(gakusri → がくscri)も，日本語として打った読みと比べるため
        let reading = KeyEditSearch.rawReading(of: keys)
        guard !keys.isEmpty, keys.count <= DefaultSettings.maximumKeysForCorrection, keys.allSatisfy(Self.isLetterKey) else { return nil }
        let typedKeys = String(all.dropFirst(boundary.rawCount))
        guard boundary.rawCount > 0 else { return Region(prefix: nil, keys: keys, typedKeys: typedKeys, reading: reading) }
        // 英単語の後ろが短いと，打ち間違いと見分けにくく直す意味も薄い
        guard keys.count >= DefaultSettings.minimumKeysForLiveCorrection else { return nil }
        return Region(prefix: typed.truncated(to: boundary), keys: keys, typedKeys: typedKeys, reading: reading)
    }

    /// 見直しに使う訂正を求めるキーの並び．
    /// 綴り直したキー(「honnno」)からは打ったままの読みの点数を，打ったままのキー(「honno」)からは打った指に近い直し(「honwo」)を求める．
    /// 綴り直すと 1 か所の打ち間違いが 2 か所に見えるので，両方から探す
    private func requiredKeys(for region: Region) -> [String] {
        let keys = region.keys
        let typed = region.typedKeys == keys ? [] : [region.typedKeys]
        return [keys] + typed + (settings.current.correction.repeatedKeys ? ReadingCorrectionRule.repeatedKeyVariants(of: keys) : [])
    }

    /// 見直さない前の部分(英単語まで)の読み．訂正を別のところで求めるとき，左の文脈に足す
    func unreviewedPrefix(of composition: Composition) -> String? {
        reviewableRegion(of: typedComposition(from: composition) ?? composition)?.prefix?.displayReading
    }

    /// 直した読みを見せているか
    var isApplied: Bool { applied != nil }

    /// 今の読みを，直さずに見直し済みにする(訂正が時間内に求まらなかったとき)
    func markReviewed(_ composition: Composition) {
        let typed = typedComposition(from: composition) ?? composition
        lastReview = (typed.rawKeys ?? "", nil)
    }

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
    func review(_ composition: inout Composition, makeComposition: () -> Composition, final: Bool = false) {
        // 訂正をまだ求め終わっていなければ，今の表示のまま待つ(直したものを打ったままに戻したりしない)
        if pendingKeys(for: composition, final: final) != nil { return }
        suggestion = nil
        suggestsMisreading = false
        let typed = typedComposition(from: composition) ?? composition
        guard let region = reviewableRegion(of: typed, final: final) else {
            // 打ちかけのローマ字があって見直さなかったときは，見直し済みにしない(打ち終えたときに見直す)
            if final || reviewableRegion(of: typed, final: true) == nil { lastReview = (typed.rawKeys ?? "", nil) }
            return
        }
        let current = settings.current
        // 誤りの種類ごとのオン・オフと，直さない語(設定)
        let checksTypos = current.typoCorrection == .standard && current.correction.japanese
            && !current.correction.isException(keys: region.keys, reading: region.reading)
            && !current.correction.isException(keys: region.typedKeys, reading: region.reading)
        let reviewedKeys = typed.rawKeys ?? ""
        let decision: ReadingCorrectionRule.Decision?
        if let lastReview, lastReview.keys == reviewedKeys {
            decision = lastReview.decision
        } else {
            decision = checksTypos ? self.decision(for: region) : nil
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
        // 綴りを直して確定させた英単語があるときは，それより大きく変える日本語の直しで英単語を消さない(jvascriptdekaku を 以下せっかく にしない)
        case .apply(let correction) where typed.correctedWordKeyEdits.map { winsOverEnglish(correction, in: region, englishKeyEdits: $0) } ?? true:
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
        case .apply, nil:
            if applied != nil { composition = typed }
            applied = nil
        }
    }

    /// 綴りを直した英単語と取り合ったときに，日本語の直しにするか．英単語の直しよりキーを変える数が少なければ日本語にする．
    /// 同じ数なら，日本語の直しを変換してカタカナの語(外来語)が出るときは英単語を残す(pyhton を ピュトン にしない)
    private func winsOverEnglish(_ correction: ReadingCorrection, in region: Region, englishKeyEdits: Int) -> Bool {
        let edits = Self.keyEdits(of: correction, in: region)
        guard edits == englishKeyEdits else { return edits < englishKeyEdits }
        let reading = KanaWidth.hiragana(from: correction.reading)
        let text = converter.candidates(for: reading).first { $0.readingCount == reading.count }?.text ?? reading
        return !text.contains(where: KanaWidth.isKatakana)
    }

    /// 直しで変えたキーの数．綴り直したキーと打ったままのキーの近い方と比べる
    private static func keyEdits(of correction: ReadingCorrection, in region: Region) -> Int {
        min(EditDistance.damerauLevenshtein(region.keys, correction.keys), EditDistance.damerauLevenshtein(region.typedKeys, correction.keys))
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

    private func decision(for region: Region) -> ReadingCorrectionRule.Decision? {
        let keys = region.keys
        // 別のところで求めるときは，求め終わっていなければ見直さない(入力の処理を待たせない)
        func corrections(_ keys: String) -> [ReadingCorrection]? {
            if let found = provided[keys] { return found }
            return usesProvidedCorrections ? nil : converter.typoCorrections(forKeys: keys)
        }
        guard var candidates = corrections(keys) else { return nil }
        if region.typedKeys != keys {
            // 打ったままのキーの読みは表示している読みと違う(「ほんお」)ので，打ったままの候補は比べる相手にしない
            guard let found = corrections(region.typedKeys) else { return nil }
            candidates = KeyEditSearch.merge(candidates, found.filter { !$0.isUnchanged && $0.keys != keys })
        }
        // 文の末尾で同じキーを続けて 2 回打った誤りは Zenzai の訂正では探さないので，1 回にした並びも見直して比べる．
        // 直すと決まったあとも試す．試さないと，重なりを 1 回にした文よりもっともらしくない文に直すことがある(評価で 1 件 → 4 件)
        for variant in settings.current.correction.repeatedKeys ? ReadingCorrectionRule.repeatedKeyVariants(of: keys) : [] {
            guard let found = corrections(variant) else { return nil }
            candidates += found.map { $0.adding(cost: DefaultSettings.repeatedKeyCost) }
        }
        candidates.sort { $0.score > $1.score }
        return ReadingCorrectionRule(level: settings.current.typoCorrection, sensitivity: settings.current.correctionSensitivity,
                                     suggests: settings.current.showsSuggestions).decision(among: candidates, reading: region.reading)
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
