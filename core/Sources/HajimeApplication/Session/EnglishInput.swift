import HajimeDomain

/// 英語のまま入力する(EN 入力と英字入力(自動)．R-05)．打った英字を 1 語ずつ組み立て，日本語にできる語には日本語を添えるか，日本語にして見せる．
///
/// - 英字入力(behavior が manual)
///   - ライブ変換がオフ(既定)なら，打った英字をそのまま見せ，ローマ字として読める並びに日本語の候補を 1 つ添える．
///     日本語にするのは Tab を押したときだけ(Q-02)．英語を打つ人の手の流れを変えないため
///   - ライブ変換がオン(設定 englishInputLiveConversion)なら，ローマ字として読め，英語の辞書にない語は日本語にして見せる
/// - 英字入力(自動)(behavior が automatic): 語ごとに英語か日本語かを見分け(WordLanguageClassifier)，日本語にする語は日本語にして見せる．
///   「kyouhaiitenki」は日本語に，「hello」は英語のまま．英語にも読める語(「make」)は前の語で見分ける．
///   空白を挟まずに続けて打った並び(「kyouhazoomdekaigi」)は，ローマ字として読めない英単語のところで語に分けて(MixedWordSplit)
///   語ごとに見分ける(「今日はzoomで会議」)．英単語で読めなくなった並びを丸ごと英語にすると，後ろの日本語まで英語のままになるため．
///   分けるのは変換を伴って重いので，打鍵では求めない．打鍵の合間(InputSession.performDeferredConversion)に 1 歩(変換 1 回)ずつ進め，
///   打っているあいだは前に分け終えた結果に打ち足した英字をつないで見せる(打鍵を待たせない)．打鍵が止まったとき(InputSession.settle)に
///   残りを求めて表示を差し替える．確定するときは残りを求めてから確定する
///
/// 日本語にして見せているときは，Space と Enter で日本語を確定し(Space は入れない)，Esc で英字に戻す．
/// 英字を見せているときは，Space・Enter・記号は英語の入力と同じに動く(打った英字を確定し，キーはアプリに渡す)．
/// どちらでも Tab で分岐図を開いて変換を選べ，Esc で英字に戻せる
@MainActor
final class EnglishInput: InputStyleHandling {
    enum Behavior {
        /// 英字入力．日本語にするかは設定(englishInputLiveConversion)と Tab で決める
        case manual
        /// 英字入力(自動)．語ごとに見分ける
        case automatic
    }

    private let converter: any KanaKanjiConverting
    private let classifier: WordLanguageClassifier
    private let settings: any SettingsReading
    private let behavior: Behavior
    private(set) var typed = ""
    /// 利用者が Esc で選んだ言語．語を打ち直すまで見分けた結果より優先する
    private var override: WordLanguage?
    /// 打っている語の前が英語か日本語か．語を打ち始めたときに決める
    private var context = WordLanguageContext.sentenceStart
    /// 前に確定した語の言語．入力位置の前の文字列を読めないアプリで，前の手がかりに使う
    private var lastLanguage: WordLanguage?
    /// 最後に分け終えた結果
    private var mixedCache: (typed: String, context: WordLanguageContext, words: [MixedWord]?)?
    /// 分けている途中の並び．1 歩ずつ進める
    private var mixedProgress: MixedProgress?
    /// 打鍵が止まって分けた結果を見せた並び
    private var settledMixed: (typed: String, context: WordLanguageContext)?
    /// 語と前の手がかりごとに見分けた結果．打ち足しても前の語を見分け直さない(打ち終えるまで覚える)
    private var mixedDecisions: [String: MixedWord] = [:]

    /// 分けている途中の並び
    private struct MixedProgress {
        var typed: String
        var context: WordLanguageContext
        /// 分けた語．まだ分けていなければ nil
        var pieces: [MixedWordSplit.Piece]?
        /// 見分け終えた語
        var words: [MixedWord] = []
    }

    /// 空白を挟まずに打った並びを分けた 1 語．japanese が nil なら英字のまま入れる
    struct MixedWord {
        var keys: String
        var japanese: Candidate?
        var text: String { japanese?.text ?? keys }
    }

    init(converter: any KanaKanjiConverting, classifier: WordLanguageClassifier, settings: any SettingsReading, behavior: Behavior) {
        self.converter = converter
        self.classifier = classifier
        self.settings = settings
        self.behavior = behavior
    }

    var isComposing: Bool { !typed.isEmpty }

    /// 英字を足す．語の打ち始めには，入力位置の前の文字列から前の手がかりを決める
    func append(_ character: Character, precedingText: String? = nil) {
        if typed.isEmpty {
            if let precedingText {
                context = WordLanguageContext.of(precedingText: precedingText)
            } else {
                context = switch lastLanguage {
                case .english: .afterEnglish
                case .japanese: .afterJapanese
                case nil: .sentenceStart
                }
            }
        }
        typed.append(character)
        override = nil
    }

    /// 分岐図から英字に戻す(Esc)
    func restore(_ text: String) {
        typed = text
        override = .english
    }

    func deleteBackward() {
        if !typed.isEmpty { typed.removeLast() }
        override = nil
    }

    /// 打った英字をローマ字として読んだ日本語の候補．ローマ字として読めなければ nil．
    /// 大文字を含むなら英語として打っているので出さない(「Documents」などの補完を妨げない)
    var suggestion: Candidate? {
        guard typed.count >= DefaultSettings.minimumEnglishInputSuggestionLength, let reading = WordLanguageClassifier.reading(of: typed) else { return nil }
        return converter.candidates(for: reading).first { $0.readingCount == reading.count }
            ?? Candidate(text: reading, readingCount: reading.count, origin: .variant(.hiragana))
    }

    /// 日本語にして見せるか
    var showsJapanese: Bool {
        guard suggestion != nil else { return false }
        if let override { return override == .japanese }
        switch behavior {
        case .manual:
            guard settings.current.englishInputLiveConversion else { return false }
            return classifier.language(of: typed, context: context, mode: .dictionaryOnly) == .japanese
        case .automatic: return classifier.language(of: typed, context: context, mode: .englishFirst) == .japanese
        }
    }

    /// 英字入力(自動)で，空白を挟まずに続けて打った英語と日本語を語に分けたもの．並び全体がローマ字として読めるか，
    /// 分けられないか，どの語も日本語にしないなら nil(並び全体で見分ける)．Esc で英字に戻した並びは分けない．
    /// 分け終えていなければ残りを今求める(確定するとき)
    var mixedWords: [MixedWord]? {
        guard splitsMixedWords else { return nil }
        while advanceMixedSplit() {}
        guard let mixedCache, mixedCache.typed == typed, mixedCache.context == context else { return nil }
        return mixedCache.words
    }

    /// 英語と日本語に分ける並びか．並び全体がローマ字として読めるなら分けない(並び全体で見分ける)
    private var splitsMixedWords: Bool {
        behavior == .automatic && override == nil && typed.count >= DefaultSettings.minimumEnglishInputSuggestionLength
            && WordLanguageClassifier.reading(of: typed) == nil
    }

    /// 今の並びをまだ分け終えていないか(InputSession.awaitsDeferredConversion)
    var awaitsMixedSplit: Bool {
        guard splitsMixedWords else { return false }
        guard let mixedCache else { return true }
        return mixedCache.typed != typed || mixedCache.context != context
    }

    /// 打鍵が止まったら，分けた結果を見せ直す並びがあるか(InputSession.awaitsSettle)
    var awaitsSettle: Bool {
        guard splitsMixedWords else { return false }
        guard let settledMixed else { return true }
        return settledMixed.typed != typed || settledMixed.context != context
    }

    /// 打鍵の合間に，分ける処理を 1 歩進める．表示は変えない(次の打鍵か，打鍵が止まったときに見せる)
    func performDeferredSplit() {
        advanceMixedSplit()
    }

    /// 打鍵が止まった．残りを求め，今の並びを分けた結果で表示を差し替える
    func settle() -> [ClientAction] {
        guard awaitsSettle else { return [] }
        _ = mixedWords
        settledMixed = (typed, context)
        return render()
    }

    /// 見せる語．求めはしない．分け終えた並びに打ち足したなら，打ち足した英字を英字のまま後ろにつなぐ
    private var shownMixedWords: [MixedWord]? {
        guard splitsMixedWords, let mixedCache, mixedCache.context == context, let words = mixedCache.words,
              typed.hasPrefix(mixedCache.typed) else { return nil }
        let tail = String(typed.dropFirst(mixedCache.typed.count))
        return tail.isEmpty ? words : words + [MixedWord(keys: tail, japanese: nil)]
    }

    /// 分ける処理を 1 歩進める．1 歩は語に分けること(英語の辞書を引く)か，ローマ字として読める語を 1 つ見分けて変換すること．
    /// 見分けたことのある語は歩数に数えずに続ける．進めることが無ければ false
    @discardableResult
    private func advanceMixedSplit() -> Bool {
        guard awaitsMixedSplit else { return false }
        var progress = mixedProgress.flatMap { $0.typed == typed && $0.context == context ? $0 : nil }
            ?? MixedProgress(typed: typed, context: context)
        guard let pieces = progress.pieces else {
            progress.pieces = MixedWordSplit.split(typed, isEnglishWord: { self.classifier.isEnglishWord($0) })
            if progress.pieces == nil {
                finishMixedSplit(nil)
            } else {
                mixedProgress = progress
            }
            return true
        }
        var decided = false
        while progress.words.count < pieces.count {
            let piece = pieces[progress.words.count]
            let previous = mixedContext(of: piece, index: progress.words.count, after: progress.words.last)
            let key = "\(previous.rawValue):\(piece.keys)"
            if let word = mixedDecisions[key] {
                progress.words.append(word)
                continue
            }
            // 変換するのは 1 歩に 1 語まで
            guard !decided else { break }
            let word = decideMixedWord(piece, context: previous)
            if !piece.isEnglishWord {
                decided = true
                if mixedDecisions.count >= DefaultSettings.maximumWordLanguageCache { mixedDecisions = [:] }
                mixedDecisions[key] = word
            }
            progress.words.append(word)
        }
        if progress.words.count == pieces.count {
            finishMixedSplit(progress.words.contains { $0.japanese != nil } ? progress.words : nil)
        } else {
            mixedProgress = progress
        }
        return true
    }

    private func finishMixedSplit(_ words: [MixedWord]?) {
        mixedCache = (typed, context, words)
        mixedProgress = nil
    }

    /// 語を見分けるときの前の手がかり．英単語に続けて打った語は，読みが短ければ(英単語にしない文字数以下．「githubni」の に)
    /// 英単語に付けた助詞などなので前が日本語として，長ければ前が英語として見分ける
    /// (「pushnotification」の notification は英語のまま，「zoomdekaigi」の でかいぎ は英語の辞書になく日本語らしいので日本語)
    private func mixedContext(of piece: MixedWordSplit.Piece, index: Int, after previous: MixedWord?) -> WordLanguageContext {
        guard index > 0 else { return context }
        guard previous?.japanese == nil else { return .afterJapanese }
        let length = WordLanguageClassifier.reading(of: piece.keys)?.count ?? .max
        return length <= settings.current.englishSkipLength ? .afterJapanese : .afterEnglish
    }

    /// 語を見分け，日本語にする語は変換する
    private func decideMixedWord(_ piece: MixedWordSplit.Piece, context previous: WordLanguageContext) -> MixedWord {
        guard !piece.isEnglishWord, let reading = WordLanguageClassifier.reading(of: piece.keys),
              classifier.language(of: piece.keys, context: previous, mode: .englishFirst) == .japanese else {
            return MixedWord(keys: piece.keys, japanese: nil)
        }
        let japanese = converter.candidates(for: reading).first { $0.readingCount == reading.count }
            ?? Candidate(text: reading, readingCount: reading.count, origin: .variant(.hiragana))
        return MixedWord(keys: piece.keys, japanese: japanese)
    }

    func commit() -> [ClientAction] {
        if let words = mixedWords { return commitMixed(words) }
        return showsJapanese ? commitSuggestion() : commitTyped()
    }

    /// 分けた語を，日本語にする語は日本語で，ほかは英字のままつないで確定する
    private func commitMixed(_ words: [MixedWord]) -> [ClientAction] {
        for candidate in words.compactMap(\.japanese) where candidate.isFromEngine { converter.didCommit(candidate) }
        mixedDecisions = [:]
        typed = ""
        override = nil
        lastLanguage = words.last?.japanese == nil ? .english : .japanese
        converter.endComposition()
        return [.commit(words.map(\.text).joined()), .setMarkedText(.empty), .hideCandidates]
    }

    /// 打った英字のまま確定する
    func commitTyped() -> [ClientAction] {
        guard isComposing else { return [] }
        let text = typed
        typed = ""
        override = nil
        lastLanguage = .english
        return [.commit(text), .setMarkedText(.empty), .hideCandidates]
    }

    /// 日本語の候補で確定する．候補が無ければ英字のまま
    func commitSuggestion() -> [ClientAction] {
        guard let suggestion else { return commitTyped() }
        if suggestion.isFromEngine { converter.didCommit(suggestion) }
        typed = ""
        override = nil
        lastLanguage = .japanese
        converter.endComposition()
        return [.commit(suggestion.text), .setMarkedText(.empty), .hideCandidates]
    }

    func render() -> [ClientAction] {
        guard isComposing else { return [.setMarkedText(.empty), .hideCandidates] }
        if let words = shownMixedWords {
            // 日本語にした語と英字のままの語をつないで見せ，打った英字を候補に添える
            var panel = CandidatePanel(variants: [], selectedVariant: nil, entries: [.init(text: typed, annotation: nil)],
                                       selectedEntry: nil, focus: .candidate, position: 1, total: 1, note: PanelBuilder.englishInputJapaneseNote)
            panel.showsNumbers = false
            let segments = words.map { MarkedText.Segment($0.text, style: $0.japanese == nil ? .reading : .converted) }
            return [.setMarkedText(MarkedText(segments)), .showCandidates(panel)]
        }
        if showsJapanese, let suggestion {
            // 日本語にして見せ，英字を候補に添える
            var panel = CandidatePanel(variants: [], selectedVariant: nil, entries: [.init(text: typed, annotation: nil)],
                                       selectedEntry: nil, focus: .candidate, position: 1, total: 1, note: PanelBuilder.englishInputJapaneseNote)
            // 番号キーでは選べない(数字を打つ)ので番号を振らない
            panel.showsNumbers = false
            return [.setMarkedText(MarkedText([.init(suggestion.text, style: .converted)])), .showCandidates(panel)]
        }
        let marked = MarkedText([.init(typed, style: .reading)])
        guard let suggestion, suggestion.text != typed else { return [.setMarkedText(marked), .hideCandidates] }
        var panel = CandidatePanel(variants: [], selectedVariant: nil, entries: [.init(text: suggestion.text, annotation: nil)],
                                   selectedEntry: nil, focus: .candidate, position: 1, total: 1, note: PanelBuilder.englishInputNote)
        panel.showsNumbers = false
        return [.setMarkedText(marked), .showCandidates(panel)]
    }

    func interpret(_ event: KeyEvent, state: InputStyleState) -> InputStyleInterpretation? {
        switch event.key {
        case .character(let character) where character.isASCII && character.isLetter:
            append(character, precedingText: state.precedingText)
            return .handled(KeyResult(handled: true, actions: render()))
        case .character("-") where isComposing:
            // 語の途中の「-」は伸ばし棒として読む(「ra-men」→ ラーメン)．英字のまま確定すれば「ra-men」
            append("-")
            return .handled(KeyResult(handled: true, actions: render()))
        case .tab:
            guard isComposing else { return .handled(.passThrough) }
            // 英語と日本語に分けて見せている並びは，ローマ字入力と同じく分岐図で選ぶ
            if mixedWords != nil {
                let keys = typed
                typed = ""
                override = nil
                return .convertRomaji(keys)
            }
            // 日本語の候補が無ければ，英字を確定して Tab をアプリに渡す(ターミナルの補完を妨げない)
            guard let suggestion, suggestion.text != typed else { return .handled(KeyResult(handled: false, actions: commitTyped())) }
            let keys = typed
            typed = ""
            override = nil
            return .convertRomaji(keys)
        case .backspace:
            guard isComposing else { return .handled(.passThrough) }
            deleteBackward()
            return .handled(KeyResult(handled: true, actions: render()))
        case .escape:
            // 組み立てていなければふつうの処理(Escape で英数にする設定)に回す
            guard isComposing else { return nil }
            if showsJapanese || shownMixedWords != nil {
                // 日本語にして見せていたら英字に戻す
                override = .english
                return .handled(KeyResult(handled: true, actions: render()))
            }
            // 打っている途中なら英字を確定し，Escape もアプリに渡す(Vim のノーマルモードに 1 回で戻れる)
            return .handled(KeyResult(handled: false, actions: commitTyped()))
        case .space, .enter:
            // 日本語にして見せている語は，日本語の入力と同じく Space と Enter で確定する(空白や改行は入れない)．
            // 英字なら英語の入力と同じく，確定してキーをアプリに渡す
            guard showsJapanese || mixedWords != nil, event.modifiers.subtracting(.shift).isEmpty else {
                return .handled(KeyResult(handled: false, actions: commitTyped()))
            }
            return .handled(KeyResult(handled: true, actions: commit()))
        case .eisu, .kana, .yen:
            return nil
        default:
            // Space・Enter・数字・記号・矢印は，見せている語を確定してからアプリに渡す(英語の入力と同じ動き)
            return .handled(KeyResult(handled: false, actions: commit()))
        }
    }
}
