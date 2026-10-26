import S90Application
import S90Domain
import S90IPC
import Testing

@Suite("分岐図の足元のキーの案内(Windows)")
struct BranchHintsTests {
    private let panel = LatticePanel(columns: [LatticePanel.Column(text: "今日は", isFocused: true, isUncertain: false)])

    @Test("キーは Windows の書き方にする")
    func label() {
        #expect(BranchHints.label(of: KeyStroke(.left, shift: true)) == "Shift+←")
        #expect(BranchHints.label(of: KeyStroke(.character("k"), control: true)) == "Ctrl+K")
        #expect(BranchHints.label(of: KeyStroke(.hankakuZenkaku)) == "半角/全角")
        #expect(BranchHints.pair("Shift+←", "Shift+→") == "Shift+←→")
    }

    @Test("キー設定の表のキーで案内を作り，出さない設定なら空")
    func hints() {
        var settings = DefaultSettings.settings
        let hints = BranchHints.make(for: panel, settings: settings)
        #expect(hints.contains { $0.label == "候補" && !$0.keys.isEmpty })
        settings.showsKeyHints = false
        #expect(BranchHints.make(for: panel, settings: settings).isEmpty)
    }
}
