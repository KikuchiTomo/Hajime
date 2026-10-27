import S90Application
import S90Domain
import S90IPC
import Testing

@Suite("通信の型と core の型の置き換え")
struct WireTranslationTests {
    private let noModifiers = WireModifiers(shift: false, control: false, alt: false)

    @Test("DLL から来たキーを core のキーにする．Alt は option にあたる")
    func keyEvent() {
        let wire = WireKeyInput(key: .character(text: "A"), modifiers: WireModifiers(shift: true, control: false, alt: true), keyLabel: "a", isKeypad: false)
        #expect(KeyEvent(wire) == KeyEvent(.character("A"), modifiers: [.shift, .option], keyLabel: "a"))
        #expect(KeyEvent(WireKeyInput(key: .function(number: 7), modifiers: noModifiers, isKeypad: false)) == KeyEvent(.function(7)))
        #expect(KeyEvent(WireKeyInput(key: .hankakuZenkaku, modifiers: noModifiers, isKeypad: false)) == KeyEvent(.hankakuZenkaku))
    }

    @Test("1 文字にならない文字のキーは受け取らない")
    func invalidCharacter() {
        #expect(KeyEvent(WireKeyInput(key: .character(text: ""), modifiers: noModifiers, isKeypad: false)) == nil)
        #expect(KeyEvent(WireKeyInput(key: .character(text: "ab"), modifiers: noModifiers, isKeypad: false)) == nil)
    }

    @Test("アプリの種類は設定のアプリごとの決まりで選び，パスワード欄では前の文字列を捨てる")
    func context() {
        var settings = Settings()
        settings.profileRules = [ProfileRule(applicationPrefix: "windowsterminal.exe", profile: .terminal)]
        let terminal = InputContext(WireFieldContext(applicationId: "windowsterminal.exe", isSecure: false, precedingText: "ls "), settings: settings)
        #expect(terminal.profile == .terminal)
        #expect(terminal.precedingText == "ls ")
        let secure = InputContext(WireFieldContext(applicationId: "notepad.exe", isSecure: true, precedingText: "秘密"), settings: settings)
        #expect(secure.profile == .standard)
        #expect(secure.isSecure)
        #expect(secure.precedingText == nil)
    }

    @Test("ClientAction を DLL・候補ウィンドウ・エンジンの受け持ちに分ける")
    func routing() {
        let anchor = WireRect(x: 1, y: 2, width: 3, height: 4)
        let routed = RoutedActions([
            .commit("確定"),
            .setMarkedText(MarkedText([.init("にほん", style: .reading), .init("語", style: .focused)])),
            .showCandidates(CandidatePanel(variants: [], selectedVariant: nil, entries: [.init(text: "日本", annotation: nil)], selectedEntry: 0,
                                           focus: .candidate, position: 1, total: 1, note: nil)),
            .selectMode(.direct),
            .hideCandidates,
            .toggleLiveConversion,
            .showModeIndicator(.direct),
        ], anchor: anchor)
        #expect(routed.edits == [
            .commit(text: "確定"),
            .setComposition(segments: [WireTextSegment(text: "にほん", style: .reading), WireTextSegment(text: "語", style: .focused)]),
            .selectMode(mode: .direct),
        ])
        #expect(routed.ui == [
            .showCandidates(list: WireCandidateList(variants: [], selectedVariant: nil, entries: [WireCandidateEntry(text: "日本", annotation: nil)],
                                                    selectedEntry: 0, focus: .candidate, position: 1, total: 1, note: nil), anchor: anchor),
            .hide,
            .showMode(mode: .direct, anchor: anchor, label: nil),
        ])
        #expect(routed.host == [.toggleLiveConversion])
    }

    @Test("分岐図は文節の内容をそのまま運ぶ")
    func branchMap() {
        var column = LatticePanel.Column(text: "今日は", alternatives: ["今日は", "京は"], selectedAlternative: 1, isFocused: true, isUncertain: true, shorter: "今日")
        column.alternativeNotes = [nil, "修正"]
        column.sourceName = "医療"
        column.isCorrected = true
        let hint = WireKeyHint(keys: "Shift+←", label: "今日")
        let routed = RoutedActions([.showLattice(LatticePanel(columns: [column], position: 1, total: 2, note: .info("案内")))], anchor: nil, hints: { _ in [hint] })
        guard case .showBranchMap(let map, let anchor) = routed.ui.first else {
            Issue.record("分岐図の指示にならない")
            return
        }
        #expect(anchor == nil)
        #expect(map.hints == [hint])
        #expect(map.note?.text == "案内")
        #expect(map.columns.first?.selectedAlternative == 1)
        #expect(map.columns.first?.alternativeNotes == [nil, "修正"])
        #expect(map.columns.first?.sourceName == "医療")
        #expect(map.columns.first?.isCorrected == true)
    }

    @Test("候補の中の直した部分の位置は，Unicode のスカラー値の数で運ぶ(Rust の char と合わせる)")
    func correctedRangeInScalars() {
        // 「が」+ 結合の濁点(2 スカラーで 1 文字)のあとに直した「良い」がある
        let entry = CandidatePanel.Entry(text: "か\u{3099}良い", annotation: nil, corrected: 1..<3)
        let list = WireCandidateList(CandidatePanel(variants: [], selectedVariant: nil, entries: [entry], selectedEntry: 0, focus: .candidate,
                                                    position: 1, total: 1, note: nil))
        #expect(list.entries.first?.correctedStart == 2)
        #expect(list.entries.first?.correctedLength == 2)
    }

    @Test("組み立てていないときに受け取るキーは，キー設定の表の今の状態のもの")
    func consumedKeys() {
        let keymap = KeymapPreset.standard.keymap
        let direct = WireSessionState(mode: .direct, isComposing: false, keymap: keymap, wakeAfterMilliseconds: nil)
        #expect(direct.consumedKeys.contains(WireKeyChord(key: .kana, modifiers: noModifiers)))
        #expect(direct.consumedKeys.contains(WireKeyChord(key: .yen, modifiers: noModifiers)))
        #expect(!direct.consumedKeys.contains(WireKeyChord(key: .space, modifiers: noModifiers)))
        let idle = WireSessionState(mode: .japanese, isComposing: false, keymap: keymap, wakeAfterMilliseconds: nil)
        #expect(idle.consumedKeys.contains(WireKeyChord(key: .space, modifiers: noModifiers)))
        let composing = WireSessionState(mode: .japanese, isComposing: true, keymap: keymap, wakeAfterMilliseconds: 300)
        #expect(composing.consumedKeys.isEmpty)
        #expect(composing.wakeAfterMilliseconds == 300)
    }

    @Test("入力位置の前の文字列は打ち始めのときだけ頼む")
    func precedingTextLength() {
        let keymap = KeymapPreset.standard.keymap
        let idle = WireSessionState(mode: .japanese, isComposing: false, keymap: keymap, wakeAfterMilliseconds: nil)
        #expect(idle.precedingTextLength == UInt32(DefaultSettings.maximumLeftContextLength))
        let composing = WireSessionState(mode: .japanese, isComposing: true, keymap: keymap, wakeAfterMilliseconds: nil)
        #expect(composing.precedingTextLength == nil)
    }

    @Test("キー配列はローマ字入力と英字入力のときだけ DLL に伝える")
    func keyboardLayout() {
        var settings = DefaultSettings.settings
        #expect(WireSessionState.keyboardLayout(for: settings) == nil)
        settings.keyboardLayout = .dvorak
        #expect(WireSessionState.keyboardLayout(for: settings) == "dvorak")
        settings.inputStyle = .englishAuto
        #expect(WireSessionState.keyboardLayout(for: settings) == "dvorak")
        settings.inputStyle = .kana
        #expect(WireSessionState.keyboardLayout(for: settings) == nil)
    }
}
