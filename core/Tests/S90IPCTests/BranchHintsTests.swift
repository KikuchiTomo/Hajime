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

    @Test("連想の一覧では単語を選ぶ・意味を移る・戻るだけを案内し，見出しと連想の知らせを送る")
    func association() {
        var association = panel
        association.association = AssociationHeading(headword: "速い", label: "速度", group: 1, groupCount: 3)
        association.associationHint = "Ctrl+Tab 連想"
        let hints = BranchHints.make(for: association, settings: DefaultSettings.settings)
        #expect(hints.map(\.label) == ["選択", "意味", "戻る"])
        let map = WireBranchMap(association, hints: hints)
        #expect(map.association == WireAssociationHeading(headword: "速い", label: "速度", group: 1, groupCount: 3))
        #expect(map.associationHint == "Ctrl+Tab 連想")
    }

    @Test("文節を区切っているときは区切る操作だけを案内する")
    func split() {
        var column = LatticePanel.Column(text: "問題がある", isFocused: true, isUncertain: true)
        column.split = .init(pieces: ["問題", "が", "ある"])
        let hints = BranchHints.make(for: LatticePanel(columns: [column]), settings: DefaultSettings.settings)
        #expect(hints == [WireKeyHint(keys: "1–2", label: "区切り"), WireKeyHint(keys: "Esc", label: "取消")])
        column.split = .init(pieces: ["問題", "がある"])
        #expect(BranchHints.make(for: LatticePanel(columns: [column]), settings: DefaultSettings.settings).first?.keys == "1")
    }
}
