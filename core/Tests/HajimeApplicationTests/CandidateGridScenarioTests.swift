import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

/// 候補を表に広げる(キー設定の表の「候補を表に広げる」．R-17)
@Suite("候補の表")
@MainActor
struct CandidateGridScenarioTests {
    /// 「かん」の候補を count 件返す変換器(「缶1」「缶2」…)
    private static func converter(count: Int = 40) -> FakeConverter {
        FakeConverter(["かん": (1...count).map { ("缶\($0)", nil) }])
    }

    private static let optionDown = (key: KeyEvent.Key.down, modifiers: KeyEvent.Modifiers.option)

    /// 「kan」を変換して表に広げる
    private static func expanded(_ settings: Settings = DefaultSettings.settings, converter: FakeConverter = converter()) -> Harness {
        let harness = Harness(converter: converter, settings: settings)
        harness.type("kan")
        harness.press(.space)
        harness.press(optionDown.key, optionDown.modifiers)
        return harness
    }

    @Test("分岐図で ⌥↓ を押すと，注目している文節の候補を 9 行 × 4 列の表に広げる．選んでいる候補はそのまま")
    func expandsLattice() {
        let harness = Self.expanded()
        #expect(harness.lastResult.actions.contains { if case .showCandidates = $0 { true } else { false } })
        #expect(harness.panel?.columnLength == DefaultSettings.candidatesPerPage)
        #expect(harness.panel?.entries.count == DefaultSettings.candidatesPerPage * DefaultSettings.candidateGridColumns)
        #expect(harness.panel?.columnCount == DefaultSettings.candidateGridColumns)
        #expect(harness.panel?.selectedEntry == 0)
        #expect(harness.panel?.total == 40)
        #expect(harness.marked.text == "缶1")
    }

    @Test("表では ↓ で下へ，→ と Tab で右の列の同じ行へ，← で左の列へ移る．右の端の列を越えると次のページを見せる")
    func movesInGrid() {
        let harness = Self.expanded()
        harness.press(.down)
        harness.press(.right)
        #expect(harness.panel?.selectedEntry == 10)
        #expect(harness.marked.text == "缶11")
        harness.press(.tab)
        #expect(harness.panel?.selectedEntry == 19)
        harness.press(.left)
        #expect(harness.panel?.selectedEntry == 10)
        // 左の端の列からは動かない
        harness.press(.left)
        harness.press(.left)
        #expect(harness.panel?.selectedEntry == 1)
        // 4 列目の右は次のページ(37 件目から)
        harness.press(.right)
        harness.press(.right)
        harness.press(.right)
        harness.press(.right)
        #expect(harness.panel?.position == 38)
        #expect(harness.panel?.entries.first?.text == "缶37")
        // 同じ行が無ければ最後の候補へ
        harness.press(.right)
        #expect(harness.marked.text == "缶40")
    }

    @Test("番号は選んでいる列にだけ振り，番号キーはその列の中で選ぶ．分岐図では選んだら表を閉じて確定へ進む")
    func numbersInFocusedColumn() throws {
        let harness = Self.expanded()
        harness.press(.right)
        let panel = try #require(harness.panel)
        #expect(panel.numberedColumn == 1)
        #expect(panel.number(ofEntry: 9) == 1)
        #expect(panel.number(ofEntry: 17) == 9)
        #expect(panel.number(ofEntry: 0) == nil)
        #expect(panel.number(ofEntry: 18) == nil)
        harness.press(.character("3"))
        #expect(harness.committed == "缶12")
    }

    @Test("Esc と広げるキーで元の分岐図に戻す．選んだ候補はそのまま")
    func collapses() {
        let harness = Self.expanded()
        harness.press(.right)
        harness.press(.escape)
        #expect(harness.lastResult.actions.contains { if case .showLattice = $0 { true } else { false } })
        #expect(harness.lattice?.columns.first?.text == "缶10")
        // もう一度 Esc を押すと，ふつうの Esc(直前の変更の取り消し)になる
        harness.press(.escape)
        #expect(harness.lattice?.columns.first?.text == "缶1")

        let toggled = Self.expanded()
        toggled.press(.down)
        toggled.press(Self.optionDown.key, Self.optionDown.modifiers)
        #expect(toggled.lastResult.actions.contains { if case .showLattice = $0 { true } else { false } })
        #expect(toggled.marked.text == "缶2")
    }

    @Test("ページ送りは表の候補の数ずつ進む．マウスで押した候補を選ぶ")
    func pagesAndClicks() {
        let harness = Self.expanded()
        harness.press(.pageDown)
        #expect(harness.panel?.position == 37)
        let clicked = Self.expanded()
        clicked.click(.entry(12))
        #expect(clicked.committed == "缶13")
    }

    @Test("一覧(文全体の候補)も表に広げられ，番号キーは選んでいる列の中で選んで確定する")
    func expandsList() {
        let harness = Self.expanded(.listPresentation)
        #expect(harness.panel?.columnLength == DefaultSettings.candidatesPerPage)
        #expect(harness.panel?.entries.count == DefaultSettings.candidatesPerPage * DefaultSettings.candidateGridColumns)
        harness.press(.right)
        harness.press(.right)
        #expect(harness.panel?.selectedEntry == 18)
        harness.press(.character("2"))
        #expect(harness.committed == "缶20")
    }

    @Test("列の数と 1 列の候補の数は設定に従う")
    func followsSettings() {
        var settings = DefaultSettings.settings
        settings.candidateGridColumns = 2
        settings.listCandidatesPerPage = 5
        let harness = Self.expanded(settings)
        #expect(harness.panel?.columnLength == 5)
        #expect(harness.panel?.entries.count == 10)
        harness.press(.right)
        #expect(harness.marked.text == "缶6")
    }

    @Test("足元の案内は列を移るキーと戻すキー．広げる前の一覧には広げるキーを案内する")
    func hints() throws {
        let harness = Self.expanded()
        let panel = try #require(harness.panel)
        #expect(IndicatorLabels.listHints(for: panel) == IndicatorLabels.gridHints)
        let list = Harness(converter: Self.converter(), settings: .listPresentation)
        list.type("kan")
        list.press(.space)
        let listPanel = try #require(list.panel)
        #expect(IndicatorLabels.listHints(for: listPanel).contains { $0.first == .expandCandidates })
    }

    @Test("読みに戻すと表を閉じ，次の変換はふつうの出し方で出す")
    func closesWhenLeavingConversion() {
        let harness = Self.expanded()
        harness.press(.backspace)
        harness.press(.space)
        #expect(harness.lastResult.actions.contains { if case .showLattice = $0 { true } else { false } })
    }

    @Test("Windows 風・Mac 風・ATOK 風のひな形は変換中の Tab で広げる", arguments: [KeymapPreset.windows, .mac, .atok])
    func presetTab(preset: KeymapPreset) {
        #expect(preset.keymap.command(for: KeyStroke(.tab), in: .converting) == .expandCandidates)
        var settings = DefaultSettings.settings
        settings.keymap = preset.keymap
        let harness = Harness(converter: Self.converter(), settings: settings)
        harness.type("kan")
        harness.press(.space)
        harness.press(.tab)
        #expect(harness.panel?.columnLength == DefaultSettings.candidatesPerPage)
    }
}
