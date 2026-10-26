import S90Domain

/// 英語のまま入力する(EN 入力と英字入力(自動)．R-05)．打った英字を 1 語ずつ組み立て，日本語にできる語には日本語を添えるか，日本語にして見せる．
///
/// - 英字入力(behavior が manual)
///   - ライブ変換がオフ(既定)なら，打った英字をそのまま見せ，ローマ字として読める並びに日本語の候補を 1 つ添える．
///     日本語にするのは Tab を押したときだけ(Q-02)．英語を打つ人の手の流れを変えないため
///   - ライブ変換がオン(設定 englishInputLiveConversion)なら，ローマ字として読め，英語の辞書にない語は日本語にして見せる
/// - 英字入力(自動)(behavior が automatic): 語ごとに英語か日本語かを見分け(WordLanguageClassifier)，日本語にする語は日本語にして見せる．
///   「kyouhaiitenki」は日本語に，「hello」は英語のまま．英語にも読める語(「make」)は前の語で見分ける
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

    func commit() -> [ClientAction] { showsJapanese ? commitSuggestion() : commitTyped() }

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
        if showsJapanese, let suggestion {
            // 日本語にして見せ，英字を候補に添える
            let panel = CandidatePanel(variants: [], selectedVariant: nil, entries: [.init(text: typed, annotation: nil)],
                                       selectedEntry: nil, focus: .candidate, position: 1, total: 1, note: PanelBuilder.englishInputJapaneseNote)
            return [.setMarkedText(MarkedText([.init(suggestion.text, style: .converted)])), .showCandidates(panel)]
        }
        let marked = MarkedText([.init(typed, style: .reading)])
        guard let suggestion, suggestion.text != typed else { return [.setMarkedText(marked), .hideCandidates] }
        let panel = CandidatePanel(variants: [], selectedVariant: nil, entries: [.init(text: suggestion.text, annotation: nil)],
                                   selectedEntry: nil, focus: .candidate, position: 1, total: 1, note: PanelBuilder.englishInputNote)
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
            if showsJapanese {
                // 日本語にして見せていたら英字に戻す
                override = .english
                return .handled(KeyResult(handled: true, actions: render()))
            }
            // 打っている途中なら英字を確定し，Escape もアプリに渡す(Vim のノーマルモードに 1 回で戻れる)
            return .handled(KeyResult(handled: false, actions: commitTyped()))
        case .space, .enter:
            // 日本語にして見せている語は，日本語の入力と同じく Space と Enter で確定する(空白や改行は入れない)．
            // 英字なら英語の入力と同じく，確定してキーをアプリに渡す
            guard showsJapanese, event.modifiers.subtracting(.shift).isEmpty else { return .handled(KeyResult(handled: false, actions: commitTyped())) }
            return .handled(KeyResult(handled: true, actions: commitSuggestion()))
        case .eisu, .kana, .yen:
            return nil
        default:
            // Space・Enter・数字・記号・矢印は，見せている語を確定してからアプリに渡す(英語の入力と同じ動き)
            return .handled(KeyResult(handled: false, actions: commit()))
        }
    }
}
