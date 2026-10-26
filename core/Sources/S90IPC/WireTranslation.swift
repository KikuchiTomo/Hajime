import S90Application
import S90Domain

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
            applicationID: wire.applicationId
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
    public init(mode: InputMode, isComposing: Bool, keymap: Keymap, wakeAfterMilliseconds: UInt32?) {
        let state: KeymapState = mode == .direct ? .direct : .idle
        var chords: [WireKeyChord] = []
        if !isComposing {
            for entry in keymap.entries where (entry.state == state || entry.state == .anywhere) && entry.command.isAvailable(in: state) {
                guard let chord = WireKeyChord(entry.stroke), !chords.contains(chord) else { continue }
                chords.append(chord)
            }
            chords.append(WireKeyChord(key: .yen, modifiers: WireModifiers(shift: false, control: false, alt: false)))
        }
        self.init(mode: WireInputMode(mode), isComposing: isComposing, consumedKeys: chords, wakeAfterMilliseconds: wakeAfterMilliseconds)
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
    public init(_ panel: CandidatePanel) {
        self.init(
            variants: panel.variants.map { WireCandidateVariant(label: $0.label, isAvailable: $0.isAvailable) },
            selectedVariant: panel.selectedVariant.map(UInt32.init(clamping:)),
            entries: panel.entries.map { WireCandidateEntry(text: $0.text, annotation: $0.annotation) },
            selectedEntry: panel.selectedEntry.map(UInt32.init(clamping:)),
            focus: panel.focus == .candidate ? .candidate : .variants,
            position: UInt32(clamping: panel.position),
            total: UInt32(clamping: panel.total),
            note: panel.note
        )
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
                    preview: column.preview,
                    shorter: column.shorter,
                    longer: column.longer,
                    usageNote: column.usageNote,
                    alternativeNotes: column.alternativeNotes,
                    sourceName: column.sourceName,
                    split: column.split.map { WireBranchSplit(pieces: $0.pieces) }
                )
            },
            position: UInt32(clamping: panel.position),
            total: UInt32(clamping: panel.total),
            note: panel.note,
            hints: hints
        )
    }
}

public enum HostAction: Sendable, Equatable {
    case selectInputStyle(InputStyle)
    case openSettings
    case toggleLiveConversion
    case showHandwriting
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

    public init(_ actions: [ClientAction], anchor: WireRect?, hints: (LatticePanel) -> [WireKeyHint] = { _ in [] }) {
        for action in actions {
            switch action {
            case .commit(let text):
                edits.append(.commit(text: text))
            case .setMarkedText(let marked):
                edits.append(.setComposition(segments: marked.segments.map { WireTextSegment(text: $0.text, style: WireTextStyle($0.style)) }))
            case .selectMode(let mode):
                edits.append(.selectMode(mode: WireInputMode(mode)))
            case .showCandidates(let panel):
                ui.append(.showCandidates(list: WireCandidateList(panel), anchor: anchor))
            case .showLattice(let panel):
                ui.append(.showBranchMap(map: WireBranchMap(panel, hints: hints(panel)), anchor: anchor))
            case .hideCandidates:
                ui.append(.hide)
            case .showModeIndicator(let mode):
                ui.append(.showMode(mode: WireInputMode(mode), anchor: anchor))
            case .showNote(let text):
                ui.append(.showNote(text: text, anchor: anchor))
            case .selectInputStyle(let style):
                host.append(.selectInputStyle(style))
            case .awaitCorrections:
                // 訂正を別のところで求める作り(typoService)のときだけ出る．エンジンのプロセスはその作りを使わないので来ない
                break
            case .openSettings:
                host.append(.openSettings)
            case .toggleLiveConversion:
                host.append(.toggleLiveConversion)
            case .showHandwriting:
                host.append(.showHandwriting)
            }
        }
    }
}
