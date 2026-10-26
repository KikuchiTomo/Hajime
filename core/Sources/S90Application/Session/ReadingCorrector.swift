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

    init(converter: any KanaKanjiConverting, settings: any SettingsReading) {
        self.converter = converter
        self.settings = settings
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
        guard following.allSatisfy(Self.isRomajiKey) else { return nil }
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
        suggestion = nil
        let typed = typedComposition(from: composition) ?? composition
        guard let keys = typed.rawKeys, keys.count <= DefaultSettings.maximumKeysForCorrection,
            !keys.isEmpty, keys.allSatisfy(Self.isRomajiKey),
            typed.pending.isEmpty || typed.pending == "n",
            !(dismissedKeys.map(keys.hasPrefix) ?? false) else { return }
        let decision = decision(forKeys: keys, reading: typed.conversionReading)
        switch decision {
        case .apply(let correction):
            guard let corrected = compose(correction.keys, makeComposition: makeComposition),
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
            suggestion = compose(correction.keys, makeComposition: makeComposition)
        case nil:
            if applied != nil { composition = typed }
            applied = nil
        }
    }

    /// 示していた直した読みにする(Tab)．直したら true
    func acceptSuggestion(_ composition: inout Composition) -> Bool {
        guard let suggested = suggestion else { return false }
        applied = Applied(typed: composition, correctedKeyCount: suggested.rawKeys?.count ?? 0)
        composition = suggested
        suggestion = nil
        return true
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

    /// 打ち続けた．示していた読みは古くなるので消す
    func didType() {
        suggestion = nil
    }

    /// 英字のまま確定した数字や記号を足した．直したものはそのまま受け入れたことにする
    func didInsertLiteral() {
        applied = nil
        suggestion = nil
    }

    func reset() {
        applied = nil
        suggestion = nil
        dismissedKeys = nil
        lastReview = nil
    }

    // MARK: - 内部

    private func decision(forKeys keys: String, reading: String) -> ReadingCorrectionRule.Decision? {
        if let lastReview, lastReview.keys == keys { return lastReview.decision }
        var candidates = converter.typoCorrections(forKeys: keys)
        // 同じキーを続けて 2 回打った誤りは Zenzai の訂正では探さないので，1 回にした並びも見直して比べる．
        // 直すと決まったあとも試す．試さないと，重なりを 1 回にした文よりもっともらしくない文に直すことがある(評価で 1 件 → 4 件)
        for variant in ReadingCorrectionRule.repeatedKeyVariants(of: keys) {
            candidates += converter.typoCorrections(forKeys: variant).map { $0.adding(cost: DefaultSettings.repeatedKeyCost) }
        }
        candidates.sort { $0.score > $1.score }
        let decision = ReadingCorrectionRule(level: settings.current.typoCorrection).decision(among: candidates, reading: reading)
        lastReview = (keys, decision)
        return decision
    }

    /// 打ったときと同じ順にキーを入れ直し，「nn」のあとの母音の読みも打つときと同じ決まりで選ぶ
    private func compose(_ keys: String, makeComposition: () -> Composition) -> Composition? {
        var composition = makeComposition()
        let resolver = NasalReadingResolver(converter: converter)
        for key in keys {
            composition.insertRomaji(key)
            resolver.resolve(&composition)
        }
        return composition.isEmpty ? nil : composition
    }

    private static func isRomajiKey(_ key: Character) -> Bool {
        (key.isASCII && key.isLetter && key.isLowercase) || key == "-"
    }
}
