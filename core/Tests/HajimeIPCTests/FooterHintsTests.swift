import HajimeApplication
import HajimeDomain
import HajimeIPC
import Testing

@Suite("候補ウィンドウの足元のキーの案内(Windows)")
struct FooterHintsTests {
    private let panel = LatticePanel(columns: [LatticePanel.Column(text: "今日は", isFocused: true, isUncertain: false)])

    @Test("キーは Windows の書き方にする")
    func label() {
        #expect(FooterHints.label(of: KeyStroke(.left, shift: true)) == "Shift+←")
        #expect(FooterHints.label(of: KeyStroke(.character("k"), control: true)) == "Ctrl+K")
        #expect(FooterHints.label(of: KeyStroke(.hankakuZenkaku)) == "半角/全角")
        #expect(FooterHints.pair("Shift+←", "Shift+→") == "Shift+←→")
    }

    @Test("キー設定の表のキーで案内を作り，出さない設定なら空")
    func hints() {
        var settings = DefaultSettings.settings
        let hints = FooterHints.make(for: panel, settings: settings)
        #expect(hints.contains { $0.label == "候補" && !$0.keys.isEmpty })
        #expect(hints.contains { $0.label == "打ち直し" && $0.keys == FooterHints.label(of: KeyStroke(.backspace, shift: true)) })
        settings.showsKeyHints = false
        #expect(FooterHints.make(for: panel, settings: settings).isEmpty)
    }

    @Test("連想の一覧では単語を選ぶ・意味を移る・戻るだけを案内し，見出しと連想の知らせを送る")
    func association() {
        var association = panel
        association.association = AssociationHeading(headword: "速い", label: "速度", group: 1, groupCount: 3)
        association.associationHint = AssociationHint(key: "Ctrl+Tab", label: "連想")
        let hints = FooterHints.make(for: association, settings: DefaultSettings.settings)
        #expect(hints.map(\.label) == ["選択", "意味", "戻る"])
        let map = WireBranchMap(association, hints: hints)
        #expect(map.association == WireAssociationHeading(headword: "速い", label: "速度", group: 1, groupCount: 3))
        #expect(map.associationHint == "連想")
        #expect(map.associationKey == "Ctrl+Tab")
    }

    @Test("一覧では，候補にいれば文字種の行へ移るキー，文字種の行にいれば字種を選ぶキーと候補へ戻るキーを，キー設定の表から案内する")
    func list() {
        let variants = ScriptVariant.allCases.map { CandidatePanel.Variant(label: $0.label, isAvailable: true) }
        var list = CandidatePanel(variants: variants, selectedVariant: nil, entries: [.init(text: "変換", annotation: nil)], selectedEntry: 0,
                                  focus: .candidate, position: 1, total: 1, note: nil)
        var settings = DefaultSettings.settings
        #expect(FooterHints.make(for: list, settings: settings) == [WireKeyHint(keys: "Shift+Space", label: "文字種"), WireKeyHint(keys: "Alt+↓", label: "表に広げる")])

        // 表で前の候補を ↑ だけにすると，案内も ↑ にする
        settings.keymap.entries.removeAll { $0.command == .previousCandidate }
        settings.keymap.entries.append(KeymapEntry(.converting, KeyStroke(.up), .previousCandidate))
        #expect(FooterHints.make(for: list, settings: settings) == [WireKeyHint(keys: "↑", label: "文字種"), WireKeyHint(keys: "Alt+↓", label: "表に広げる")])

        // 表に広げているときは，列を移るキーと戻すキー
        var grid = list
        grid.columnLength = 9
        #expect(FooterHints.make(for: grid, settings: settings) == [WireKeyHint(keys: "←→", label: "列"), WireKeyHint(keys: "Alt+↓", label: "戻す")])

        list.focus = .variants
        list.selectedVariant = 0
        #expect(FooterHints.make(for: list, settings: settings) == [WireKeyHint(keys: "←→", label: "選択"), WireKeyHint(keys: "Space", label: "候補")])

        // 文字種の行が無い一覧(入力中の候補の窓など)には文字種の案内を出さない
        let plain = CandidatePanel(variants: [], selectedVariant: nil, entries: [.init(text: "変換", annotation: nil)], selectedEntry: 0,
                                   focus: .candidate, position: 1, total: 1, note: nil)
        #expect(FooterHints.make(for: plain, settings: settings).isEmpty)

        settings.showsKeyHints = false
        #expect(FooterHints.make(for: list, settings: settings).isEmpty)
    }

    @Test("連想の一覧の一覧表示でも，単語を選ぶ・意味を移る・戻るだけを案内する")
    func associationList() {
        var list = CandidatePanel(variants: [], selectedVariant: nil, entries: [.init(text: "早い", annotation: nil)], selectedEntry: 0,
                                  focus: .candidate, position: 1, total: 1, note: nil)
        list.association = AssociationHeading(headword: "速い", label: "速度", group: 1, groupCount: 3)
        #expect(FooterHints.make(for: list, settings: DefaultSettings.settings).map(\.label) == ["選択", "意味", "戻る"])
    }

    @Test("文節を区切っているときは区切る操作だけを案内する")
    func split() {
        var column = LatticePanel.Column(text: "問題がある", isFocused: true, isUncertain: true)
        column.split = .init(pieces: ["問題", "が", "ある"])
        let hints = FooterHints.make(for: LatticePanel(columns: [column]), settings: DefaultSettings.settings)
        #expect(hints == [WireKeyHint(keys: "1–2", label: "区切り"), WireKeyHint(keys: "Esc", label: "取り消し")])
        column.split = .init(pieces: ["問題", "がある"])
        #expect(FooterHints.make(for: LatticePanel(columns: [column]), settings: DefaultSettings.settings).first?.keys == "1")
    }
}
