import HajimeApplication
import HajimeDomain

extension KeyEvent {
    public init?(_ wire: WireKeyInput) {
        let key: Key
        switch wire.key {
        case .character(let text):
            guard text.count == 1, let character = text.first else { return nil }
            key = .character(character)
        case .space: key = .space
        case .enter: key = .enter
        case .backspace: key = .backspace
        case .delete: key = .delete
        case .escape: key = .escape
        case .tab: key = .tab
        case .up: key = .up
        case .down: key = .down
        case .left: key = .left
        case .right: key = .right
        case .home: key = .home
        case .end: key = .end
        case .pageUp: key = .pageUp
        case .pageDown: key = .pageDown
        case .eisu: key = .eisu
        case .kana: key = .kana
        case .yen: key = .yen
        case .function(let number): key = .function(Int(number))
        case .hankakuZenkaku: key = .hankakuZenkaku
        case .henkan: key = .henkan
        case .muhenkan: key = .muhenkan
        }
        var modifiers: Modifiers = []
        if wire.modifiers.shift { modifiers.insert(.shift) }
        if wire.modifiers.control { modifiers.insert(.control) }
        if wire.modifiers.alt { modifiers.insert(.option) }
        self.init(key, modifiers: modifiers, keyLabel: wire.keyLabel, isKeypad: wire.isKeypad)
    }
}

extension InputContext {
    public init(_ wire: WireFieldContext, settings: Settings) {
        self.init(
            profile: settings.profile(forApplication: wire.applicationId),
            isSecure: wire.isSecure,
            precedingText: wire.isSecure ? nil : wire.precedingText,
            applicationID: wire.applicationId,
            // 入力位置の前の文字を置き換えられる DLL だけが知らせる(古い DLL は setComposition の replacedLength を読まない)
            canReplacePrecedingText: wire.canReplacePrecedingText ?? false,
            // 入力メニューを出せる DLL と，選んでいる文字を読んで単語の登録に渡せる DLL だけが知らせる(古い DLL は新しい操作を読めない)
            canOpenMenu: wire.canShowMenu ?? false,
            canReadSelectionForRegistration: wire.canRequestWordRegistration ?? false
        )
    }
}

extension WireCustomTheme {
    /// 保存したカスタムテーマを候補ウィンドウに渡す形にする．元のテーマは名前(ThemePreference の値)で渡す
    public init(_ theme: CustomTheme) {
        self.init(base: theme.base.rawValue, surface: WireColor(theme.surface), text: WireColor(theme.text), textMuted: WireColor(theme.textMuted),
                  selection: WireColor(theme.selection), selectionText: WireColor(theme.selectionText), correction: WireColor(theme.correction),
                  line: WireColor(theme.line), fontName: theme.fontName, cornerRadius: theme.cornerRadius,
                  straightBranches: theme.branchStyle == .straight)
    }
}

extension WireContrastPair {
    public init(_ pair: CustomTheme.ContrastPair) {
        switch pair {
        case .text: self = .text
        case .textMuted: self = .textMuted
        case .selectionText: self = .selectionText
        case .correction: self = .correction
        }
    }
}

extension WireColor {
    public init(_ color: HexColor) {
        self.init(red: color.red, green: color.green, blue: color.blue)
    }
}

extension InputMode {
    public init(_ wire: WireInputMode) {
        switch wire {
        case .japanese: self = .japanese
        case .direct: self = .direct
        }
    }
}

extension WireInputMode {
    public init(_ mode: InputMode) {
        switch mode {
        case .japanese: self = .japanese
        case .direct: self = .direct
        }
    }
}

extension WireKeyChord {
    public init?(_ stroke: KeyStroke) {
        guard !stroke.command else { return nil }
        let key: WireKey
        switch stroke.key {
        case .character(let text): key = .character(text: text)
        case .space: key = .space
        case .enter: key = .enter
        case .tab: key = .tab
        case .backspace: key = .backspace
        case .delete: key = .delete
        case .escape: key = .escape
        case .up: key = .up
        case .down: key = .down
        case .left: key = .left
        case .right: key = .right
        case .home: key = .home
        case .end: key = .end
        case .pageUp: key = .pageUp
        case .pageDown: key = .pageDown
        case .function(let number): key = .function(number: UInt8(clamping: number))
        case .eisu: key = .eisu
        case .kana: key = .kana
        case .hankakuZenkaku: key = .hankakuZenkaku
        case .henkan: key = .henkan
        case .muhenkan: key = .muhenkan
        }
        self.init(key: key, modifiers: WireModifiers(shift: stroke.shift, control: stroke.control, alt: stroke.option))
    }
}

extension WireSessionState {
    /// undoablePrediction は予測の確定を，undoableCommit は確定(予測も含む)を取り消せるか．取り消すキー(入力文字なしの Backspace・
    /// Ctrl+Backspace など)は，取り消せるときだけ送ってもらう(いつも送ってもらうと，ふだんの Backspace もエンジンを通る)
    public init(mode: InputMode, isComposing: Bool, keymap: Keymap, wakeAfterMilliseconds: UInt32?, keyboardLayout: String? = nil,
                undoablePrediction: Bool = false, undoableCommit: Bool = false) {
        let state: KeymapState = mode == .direct ? .direct : .idle
        var chords: [WireKeyChord] = []
        if !isComposing {
            for entry in keymap.entries where (entry.state == state || entry.state == .anywhere) && entry.command.isAvailable(in: state)
                && (undoablePrediction || entry.command != .undoPrediction) && (undoableCommit || entry.command != .undoCommit) {
                guard let chord = WireKeyChord(entry.stroke), !chords.contains(chord) else { continue }
                chords.append(chord)
            }
            chords.append(WireKeyChord(key: .yen, modifiers: WireModifiers(shift: false, control: false, alt: false)))
        }
        // 打ち始めのときだけ，入力位置の前の文字列を頼む(macOS と同じ．毎キー読まないため)．組み立て中は頼まない
        let precedingTextLength = isComposing ? nil : UInt32(DefaultSettings.maximumLeftContextLength)
        self.init(mode: WireInputMode(mode), isComposing: isComposing, consumedKeys: chords, wakeAfterMilliseconds: wakeAfterMilliseconds,
                  precedingTextLength: precedingTextLength, keyboardLayout: keyboardLayout)
    }

    /// DLL が英字を打つときに使う配列(設定の「キー配列」)．macOS と同じく，ローマ字入力と英字入力のときだけ使う．
    /// OS の配列のままなら nil
    public static func keyboardLayout(for settings: Settings) -> String? {
        guard settings.keyboardLayout != .system, settings.inputStyle != .kana else { return nil }
        return settings.keyboardLayout.rawValue
    }
}

extension WireTextStyle {
    public init(_ style: MarkedText.Style) {
        switch style {
        case .reading: self = .reading
        case .converted: self = .converted
        case .focused: self = .focused
        case .correction: self = .correction
        }
    }
}

extension WireCandidateList {
    /// hints は足元のキーの案内(FooterHints)．キーの名前は OS の書き方なのでエンジンの側で作って渡す．
    /// 案内が無ければ送らない(案内を知らない前の版の候補ウィンドウとも話せるよう，省ける項目にしてある)
    public init(_ panel: CandidatePanel, hints: [WireKeyHint] = []) {
        self.init(
            variants: panel.variants.map { WireCandidateVariant(label: $0.label, isAvailable: $0.isAvailable) },
            selectedVariant: panel.selectedVariant.map(UInt32.init(clamping:)),
            entries: panel.entries.map { entry in
                // 直した部分の位置は，Rust の char と同じ Unicode のスカラー値の数で送る(core は書記素の数で持つ)
                let corrected = entry.corrected.map { range -> (start: Int, length: Int) in
                    let characters = Array(entry.text)
                    let scalars = { (slice: ArraySlice<Character>) in slice.reduce(0) { $0 + $1.unicodeScalars.count } }
                    let start = min(range.lowerBound, characters.count), end = min(range.upperBound, characters.count)
                    return (scalars(characters[..<start]), scalars(characters[start..<end]))
                }
                return WireCandidateEntry(text: entry.text, annotation: entry.annotation,
                                          correctedStart: corrected.map { UInt32(clamping: $0.start) },
                                          correctedLength: corrected.map { UInt32(clamping: $0.length) },
                                          command: entry.command.map(WireCommandKind.init),
                                          // コメントでなければ送らない
                                          hasComment: entry.hasComment ? true : nil)
            },
            selectedEntry: panel.selectedEntry.map(UInt32.init(clamping:)),
            focus: panel.focus == .candidate ? .candidate : .variants,
            position: UInt32(clamping: panel.position),
            total: UInt32(clamping: panel.total),
            note: panel.note.map(WireNote.init),
            hints: hints.isEmpty ? nil : hints,
            association: panel.association.map(WireAssociationHeading.init),
            associationHint: panel.associationHint?.label,
            associationKey: panel.associationHint?.key,
            homophone: panel.homophone.map(WireHomophoneNote.init),
            // 振るとき(ふつうの一覧)は送らない
            showsNumbers: panel.showsNumbers ? nil : false,
            // 意味が無ければ送らない
            meaningPlacement: panel.homophone == nil ? nil : WireMeaningPlacement(panel.meaningPlacement),
            // 表に広げていなければ送らない(知らない候補ウィンドウは 1 列の一覧として出す)
            columnLength: panel.columnLength.map(UInt32.init(clamping:))
        )
    }
}

extension WireDictionaryEntry {
    public init(_ entry: UserDictionaryEntry) {
        self.init(reading: entry.reading, word: entry.word, wordClass: WireWordClass(rawValue: entry.wordClass.rawValue),
                  comment: entry.comment.isEmpty ? nil : entry.comment)
    }

    /// 品詞を送らない設定の画面(品詞を選べるようになる前のもの)から来た語は，登録するときの既定の品詞にする
    public var entry: UserDictionaryEntry {
        UserDictionaryEntry(reading: reading, word: word,
                            wordClass: wordClass.flatMap { WordClass(rawValue: $0.rawValue) } ?? DefaultSettings.userWordClass, comment: comment ?? "")
    }
}

extension WireCommandKind {
    public init(_ kind: LauncherCommand.Kind) {
        switch kind {
        case .openApplication: self = .openApplication
        case .openURL: self = .openURL
        case .openFile: self = .openFile
        case .runShortcut: self = .runShortcut
        }
    }
}

extension WireHomophoneNote {
    public init(_ note: HomophoneNote) {
        self.init(word: note.word, partOfSpeech: note.partOfSpeech.map(WirePartOfSpeech.init), senses: note.senses.map { WireHomophoneSense(meaning: $0.meaning, example: $0.example) },
                  others: note.others)
    }
}

extension WirePartOfSpeech {
    public init(_ partOfSpeech: PartOfSpeech) {
        switch partOfSpeech {
        case .noun: self = .noun
        case .verb: self = .verb
        case .adjective: self = .adjective
        case .adjectivalNoun: self = .adjectivalNoun
        case .adverb: self = .adverb
        case .prenominal: self = .prenominal
        case .conjunction: self = .conjunction
        case .interjection: self = .interjection
        case .pronoun: self = .pronoun
        case .prefix: self = .prefix
        case .suffix: self = .suffix
        }
    }
}

extension WireMeaningPlacement {
    public init(_ placement: MeaningPlacement) {
        switch placement {
        case .side: self = .side
        case .below: self = .below
        }
    }
}

extension WirePrediction {
    public init(_ prediction: Prediction) {
        self.init(typed: prediction.typed, completion: prediction.completion, key: prediction.key)
    }
}

extension WireAssociationHeading {
    public init(_ heading: AssociationHeading) {
        self.init(headword: heading.headword, label: heading.label,
                  group: UInt32(clamping: heading.group), groupCount: UInt32(clamping: heading.groupCount))
    }
}

extension WireBranchMap {
    public init(_ panel: LatticePanel, hints: [WireKeyHint]) {
        self.init(
            columns: panel.columns.map { column in
                WireBranchColumn(
                    text: column.text,
                    alternatives: column.alternatives,
                    selectedAlternative: column.selectedAlternative.map(UInt32.init(clamping:)),
                    variants: column.variants,
                    selectedVariant: column.selectedVariant.map(UInt32.init(clamping:)),
                    isFocused: column.isFocused,
                    isUncertain: column.isUncertain,
                    isDecided: column.isDecided,
                    isCorrected: column.isCorrected ? true : nil,
                    preview: column.preview,
                    shorter: column.shorter,
                    longer: column.longer,
                    usageNote: column.usageNote,
                    homophone: column.homophone.map(WireHomophoneNote.init),
                    alternativeNotes: column.alternativeNotes,
                    alternativeCommands: column.alternativeCommands.isEmpty ? nil : column.alternativeCommands.map { $0.map(WireCommandKind.init) },
                    alternativeComments: column.alternativeComments.isEmpty ? nil : column.alternativeComments,
                    sourceName: column.sourceName,
                    split: column.split.map { WireBranchSplit(pieces: $0.pieces) }
                )
            },
            position: UInt32(clamping: panel.position),
            total: UInt32(clamping: panel.total),
            note: panel.note.map(WireNote.init),
            hints: hints,
            association: panel.association.map(WireAssociationHeading.init),
            associationHint: panel.associationHint?.label,
            associationKey: panel.associationHint?.key,
            // 注目している文節に意味が無ければ送らない
            meaningPlacement: panel.columns.contains { $0.homophone != nil } ? WireMeaningPlacement(panel.meaningPlacement) : nil
        )
    }
}

public enum HostAction: Sendable, Equatable {
    case selectInputStyle(InputStyle)
    case openSettings
    /// 設定のユーザー辞書の画面を開き，語と読みを登録の欄に入れる(空なら入れない)
    case openWordRegistration(word: String, reading: String)
    case openUserDictionary
    case toggleLiveConversion
    case showHandwriting
    /// コマンドを動かす(エンジンのプロセスで．DLL には送らない)
    case runCommand(LauncherCommand)
}

public struct RoutedActions: Sendable, Equatable {
    public var edits: [WireEditOperation] = []
    public var ui: [WireUiCommand] = []
    public var host: [HostAction] = []

    public init(edits: [WireEditOperation] = [], ui: [WireUiCommand] = [], host: [HostAction] = []) {
        self.edits = edits
        self.ui = ui
        self.host = host
    }

    /// composition は組み立て中の文字全体の位置(予測の窓を置く基準)．知らせない DLL では nil．
    /// hints と listHints は分岐図と一覧の足元のキーの案内(FooterHints)．paletteCellSize は設定のパレットのマスの大きさ(パレットを出すときに添える)
    public init(_ actions: [ClientAction], anchor: WireRect?, composition: WireRect? = nil, hints: (LatticePanel) -> [WireKeyHint] = { _ in [] },
                listHints: (CandidatePanel) -> [WireKeyHint] = { _ in [] }, paletteCellSize: Double = DefaultSettings.paletteCellSize) {
        // 次の組み立て中の文字で置き換える，入力位置の前の文字の長さ(予測の確定の取り消し)
        var replacedLength: UInt32?
        for action in actions {
            switch action {
            case .commit(let text):
                edits.append(.commit(text: text))
            case .setMarkedText(let marked):
                edits.append(.setComposition(segments: marked.segments.map { WireTextSegment(text: $0.text, style: WireTextStyle($0.style)) },
                                             caret: marked.caret.map { _ in UInt32(marked.textBeforeCaret.utf16.count) },
                                             panelAnchor: nil, replacedLength: replacedLength))
                replacedLength = nil
            case .replacePrecedingText(let length):
                replacedLength = UInt32(clamping: length)
            case .selectMode(let mode):
                edits.append(.selectMode(mode: WireInputMode(mode)))
            case .showCandidates(let panel):
                ui.append(.showCandidates(list: WireCandidateList(panel, hints: listHints(panel)), anchor: anchor))
            case .showLattice(let panel):
                ui.append(.showBranchMap(map: WireBranchMap(panel, hints: hints(panel)), anchor: anchor))
            case .hideCandidates:
                ui.append(.hide)
            case .showModeIndicator(let mode):
                ui.append(.showMode(mode: WireInputMode(mode), anchor: anchor, label: nil))
            case .showNote(let note):
                ui.append(.showNote(note: WireNote(note), anchor: anchor))
            case .showPrediction(let prediction):
                // 予測の窓は組み立て中の文字の右に置く．組み立て中の文字の位置を知らせない古い DLL では，候補の窓と同じ基準を使う
                ui.append(.showPrediction(prediction: prediction.map(WirePrediction.init), anchor: composition ?? anchor))
            case .selectInputStyle(let style):
                host.append(.selectInputStyle(style))
            case .awaitCorrections:
                // 訂正を別のところで求める作り(typoService)のときだけ出る．エンジンのプロセスは EngineService が受けて訂正を待つので，ここには来ない
                break
            case .requestReconversion:
                // 入力先の選んでいる文字は DLL が読むので，読んで reconvert で送ってもらう
                edits.append(.requestReconversion(maximumLength: UInt32(DefaultSettings.maximumReconversionLength)))
            case .openSettings:
                host.append(.openSettings)
            case .openWordRegistration(let word, let reading):
                // 入力先の選んでいる文字は DLL が読むので，読んで openWordRegistration で送ってもらう(InputSession は読める DLL のときだけ nil にする)
                if let word {
                    host.append(.openWordRegistration(word: word, reading: reading ?? ""))
                } else {
                    edits.append(.requestWordRegistration(maximumLength: UInt32(DefaultSettings.maximumUserDictionaryWordLength)))
                }
            case .openUserDictionary:
                host.append(.openUserDictionary)
            case .openMenu:
                edits.append(.showMenu)
            case .toggleLiveConversion:
                host.append(.toggleLiveConversion)
            case .showHandwriting:
                host.append(.showHandwriting)
            case .showPalette(let panel):
                ui.append(.showPalette(panel: WirePalettePanel(panel, cellSize: paletteCellSize), anchor: anchor))
            case .hidePalette:
                ui.append(.hidePalette)
            case .runCommand(let command):
                host.append(.runCommand(command))
            }
        }
        // 候補の窓を組み立て中の文字の途中(今打っている文節・選んでいる文節)にそろえるときは，その位置を組み立て中の文字の
        // 書き換えに添える．画面の上の位置は入力先のアプリにしか分からないので，DLL がその字の位置を求めて送り直す(macOS は panelAnchor)
        let panelAnchor = actions.lazy.compactMap { action -> Int? in
            if case .showCandidates(let panel) = action { return panel.anchor }
            return nil
        }.first
        if let panelAnchor, let index = edits.lastIndex(where: { if case .setComposition = $0 { true } else { false } }),
           case .setComposition(let segments, let caret, _, let replaced) = edits[index] {
            edits[index] = .setComposition(segments: segments, caret: caret, panelAnchor: UInt32(clamping: panelAnchor), replacedLength: replaced)
        }
    }
}

extension SymbolRule.Kind {
    public init(_ kind: WireSymbolKind) {
        switch kind {
        case .sequence: self = .sequence
        case .reading: self = .reading
        }
    }
}

extension WireSymbolItem {
    public init(_ item: SymbolRuleEditing.Item) {
        let origin: WireSymbolOrigin = switch item.origin {
        case .standard: .standard
        case .changed: .changed
        case .added: .added
        }
        self.init(input: item.input, output: item.output, isEnabled: item.isEnabled, origin: origin)
    }
}

extension WireDictionaryAddResult {
    public init(_ result: UserDictionaryEditing.AddResult) {
        switch result {
        case .added: self = .added
        case .alreadyRegistered: self = .alreadyRegistered
        case .invalid: self = .invalid
        case .full: self = .full
        }
    }
}

extension WireNote {
    init(_ note: Note) {
        let tone: WireNoteTone = switch note.tone {
        case .correction: .correction
        case .suggestion: .suggestion
        case .info: .info
        }
        self.init(tone: tone, title: note.title, subject: note.subject, key: note.key, keyAction: note.keyAction, text: note.text)
    }
}
