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
            .showMode(mode: .direct, anchor: anchor),
        ])
        #expect(routed.host == [.toggleLiveConversion])
    }

    @Test("分岐図は文節の内容をそのまま運ぶ")
    func branchMap() {
        var column = LatticePanel.Column(text: "今日は", alternatives: ["今日は", "京は"], selectedAlternative: 1, isFocused: true, isUncertain: true, shorter: "今日")
        column.alternativeNotes = [nil, "修正"]
        column.sourceName = "医療"
        let hint = WireKeyHint(keys: "Shift+←", label: "今日")
        let routed = RoutedActions([.showLattice(LatticePanel(columns: [column], position: 1, total: 2, note: "案内"))], anchor: nil, hints: { _ in [hint] })
        guard case .showBranchMap(let map, let anchor) = routed.ui.first else {
            Issue.record("分岐図の指示にならない")
            return
        }
        #expect(anchor == nil)
        #expect(map.hints == [hint])
        #expect(map.note == "案内")
        #expect(map.columns.first?.selectedAlternative == 1)
        #expect(map.columns.first?.alternativeNotes == [nil, "修正"])
        #expect(map.columns.first?.sourceName == "医療")
    }

    @Test("組み立てていないときに受け取るキーは，キー設定の表の今の状態のもの")
    func consumedKeys() {
        let keymap = KeymapPreset.standard.keymap
        let direct = WireSessionState(mode: .direct, isComposing: false, keymap: keymap, wakeAfterMilliseconds: nil)
        // 英数のときも，日本語にするキーは受け取る
        #expect(direct.consumedKeys.contains(WireKeyChord(key: .kana, modifiers: noModifiers)))
        #expect(direct.consumedKeys.contains(WireKeyChord(key: .yen, modifiers: noModifiers)))
        // 英数のときの Space はアプリのもの
        #expect(!direct.consumedKeys.contains(WireKeyChord(key: .space, modifiers: noModifiers)))
        let idle = WireSessionState(mode: .japanese, isComposing: false, keymap: keymap, wakeAfterMilliseconds: nil)
        #expect(idle.consumedKeys.contains(WireKeyChord(key: .space, modifiers: noModifiers)))
        // 組み立て中はすべて受け取るので，表は送らない
        let composing = WireSessionState(mode: .japanese, isComposing: true, keymap: keymap, wakeAfterMilliseconds: 300)
        #expect(composing.consumedKeys.isEmpty)
        #expect(composing.wakeAfterMilliseconds == 300)
    }
}
