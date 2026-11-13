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
        #expect(hints.contains { $0.label == "再入力" && $0.keys == FooterHints.label(of: KeyStroke(.backspace, shift: true)) })
        settings.showsKeyHints = false
        #expect(FooterHints.make(for: panel, settings: settings).isEmpty)
    }

    @Test("連想の一覧では単語を選ぶ・意味を移る・戻るだけを案内し，見出しと連想の知らせを送る")
    func association() {
        var association = panel
        association.association = AssociationHeading(headword: "速い", label: "速度", group: 1, groupCount: 3)
        association.associationHint = AssociationHint(key: "Ctrl+Tab", label: "連想")
        let hints = FooterHints.make(for: association, settings: DefaultSettings.settings)
        #expect(hints.map(\.label) == ["選択", "意味の切り替え", "戻る"])
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
        #expect(FooterHints.make(for: list, settings: settings) == [WireKeyHint(keys: "Shift+Space", label: "文字種"), WireKeyHint(keys: "Alt+↓", label: "表形式")])

        // 表で前の候補を ↑ だけにすると，案内も ↑ にする
        settings.keymap.entries.removeAll { $0.command == .previousCandidate }
        settings.keymap.entries.append(KeymapEntry(.converting, KeyStroke(.up), .previousCandidate))
        #expect(FooterHints.make(for: list, settings: settings) == [WireKeyHint(keys: "↑", label: "文字種"), WireKeyHint(keys: "Alt+↓", label: "表形式")])

        // 表に広げているときは，列を移るキーと戻すキー
        var grid = list
        grid.columnLength = 9
        #expect(FooterHints.make(for: grid, settings: settings) == [WireKeyHint(keys: "←→", label: "列"), WireKeyHint(keys: "Alt+↓", label: "戻る")])

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
        #expect(FooterHints.make(for: list, settings: DefaultSettings.settings).map(\.label) == ["選択", "意味の切り替え", "戻る"])
    }

    @Test("分岐図の操作する場所ごとの案内は，境目の上・文字種の先・候補の下・先の枝の先に分け，出さない設定なら送らない")
    func placed() throws {
        var settings = DefaultSettings.settings
        let hints = try #require(FooterHints.placed(for: panel, settings: settings))
        #expect(hints.boundary.map(\.label) == ["区切り", "分割"])
        #expect(hints.variant?.label == "文字種")
        #expect(hints.candidates.map(\.label) == ["再入力", "表形式"])
        #expect(hints.expand == nil)

        // 連想があれば，連想変換のキーで先の枝を展開する
        var associated = panel
        associated.associationHint = AssociationHint(key: "Alt+↑", label: "連想")
        #expect(FooterHints.placed(for: associated, settings: settings)?.expand == WireKeyHint(keys: "Alt+↑", label: "展開"))
        // 先の枝を畳んでいるときも，開くキーを案内する
        var collapsed = panel
        collapsed.collapsesDetail = true
        #expect(FooterHints.placed(for: collapsed, settings: settings)?.expand?.label == "展開")

        // 区切っているあいだは境目の上に区切る操作だけ．連想の一覧は候補の下に連想の操作だけ
        var column = LatticePanel.Column(text: "問題がある", isFocused: true, isUncertain: true)
        column.split = .init(pieces: ["問題", "が", "ある"])
        let split = try #require(FooterHints.placed(for: LatticePanel(columns: [column]), settings: settings))
        #expect(split.boundary == [WireKeyHint(keys: "1–2", label: "分割"), WireKeyHint(keys: "Esc", label: "キャンセル")])
        #expect(split.candidates.isEmpty && split.variant == nil)
        var association = panel
        association.association = AssociationHeading(headword: "速い", label: "速度", group: 1, groupCount: 3)
        #expect(FooterHints.placed(for: association, settings: settings)?.candidates.map(\.label) == ["選択", "意味の切り替え", "戻る"])

        settings.showsKeyHints = false
        #expect(FooterHints.placed(for: panel, settings: settings) == nil)
    }

    @Test("分岐図で足した項目(文節へ移るキー・文字種にするキー・畳んだ枝・置き場所ごとの案内)は，無ければ送らない")
    func optionalFields() {
        let plain = WireBranchMap(panel, hints: [])
        #expect(plain.columns[0].jumpKey == nil && plain.columns[0].variantKeys == nil)
        #expect(plain.collapsesVariants == nil && plain.collapsesDetail == nil && plain.placedHints == nil)
        #expect(plain.trunkFocused == nil && plain.pageSize == nil && plain.hintsOnHold == nil)

        var keyed = panel
        keyed.columns[0].jumpKey = "Alt+A"
        keyed.columns[0].variants = ["きょうは", "キョウハ"]
        keyed.columns[0].variantKeys = ["F6", nil]
        keyed.collapsesDetail = true
        keyed.trunkFocused = true
        keyed.pageSize = 4
        keyed.hintsOnHold = true
        let placed = WireBranchHints(boundary: [], candidates: [WireKeyHint(keys: "Shift+Backspace", label: "再入力")])
        let map = WireBranchMap(keyed, hints: [], placedHints: placed)
        #expect(map.columns[0].jumpKey == "Alt+A")
        #expect(map.columns[0].variantKeys == ["F6", nil])
        #expect(map.collapsesDetail == true && map.collapsesVariants == nil)
        #expect(map.placedHints == placed)
        #expect(map.trunkFocused == true && map.pageSize == 4 && map.hintsOnHold == true)
    }

    @Test("長い文をまとまりに区切ったときも文節は文の全体を送り，出すまとまりの範囲と前後に続くことを添える(前の版の候補ウィンドウは全体を出す)")
    func group() {
        var panel = LatticePanel(columns: (0..<5).map { LatticePanel.Column(text: "文節\($0)", isFocused: $0 == 2, isUncertain: false) })
        let whole = WireBranchMap(panel, hints: [])
        #expect(whole.columns.count == 5 && whole.groupStart == nil && whole.groupEnd == nil && whole.continuesBefore == nil && whole.continuesAfter == nil)
        panel.group = 2..<4
        panel.keepsWidth = true
        let shown = WireBranchMap(panel, hints: [])
        #expect(shown.columns.count == 5)
        #expect(shown.groupStart == 2 && shown.groupEnd == 4 && shown.continuesBefore == true && shown.continuesAfter == true && shown.keepsWidth == true)
    }

    @Test("文節を区切っているときは区切る操作だけを案内する")
    func split() {
        var column = LatticePanel.Column(text: "問題がある", isFocused: true, isUncertain: true)
        column.split = .init(pieces: ["問題", "が", "ある"])
        let hints = FooterHints.make(for: LatticePanel(columns: [column]), settings: DefaultSettings.settings)
        #expect(hints == [WireKeyHint(keys: "1–2", label: "分割"), WireKeyHint(keys: "Esc", label: "キャンセル")])
        column.split = .init(pieces: ["問題", "がある"])
        #expect(FooterHints.make(for: LatticePanel(columns: [column]), settings: DefaultSettings.settings).first?.keys == "1")
    }
}
