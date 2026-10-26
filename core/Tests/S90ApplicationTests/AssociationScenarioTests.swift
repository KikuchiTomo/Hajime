import S90Application
import S90Domain
import S90TestSupport
import Testing

@MainActor
@Suite("連想変換(R-18)")
struct AssociationScenarioTests {
    private static let dictionary = AssociationDictionary(id: "6F9619FF-8B86-D011-B42D-00C04FC964FF", name: "類語", groupCount: 2)
    private static let groups = [
        AssociationGroup(label: "見た目が快い", words: ["綺麗", "麗しい", "華麗"]),
        AssociationGroup(label: "心を打つ", words: ["清らか", "綺麗"]),
    ]

    private func makeSettings(_ change: (inout Settings) -> Void = { _ in }) -> Settings {
        var settings = DefaultSettings.settings
        settings.associationDictionaries = [Self.dictionary]
        change(&settings)
        return settings
    }

    private func harness(_ settings: Settings? = nil, lookup: FakeAssociationLookup? = nil) -> Harness {
        let converter = FakeConverter(["うつくしい": [("美しい", nil), ("美しき", nil)]], clauses: ["うつくしい": [("美しい", 5), ("美しき", 5)]])
        let lookup = lookup ?? FakeAssociationLookup([Self.dictionary.id: ["美しい": Self.groups]])
        return Harness(converter: converter, settings: settings ?? makeSettings(), associations: lookup)
    }

    @Test("入力中の Shift+Space で変換し，選んでいる文節を連想の一覧にする．見出しは元の語と意味の説明")
    func shiftSpaceEntersAssociation() throws {
        let harness = harness()
        harness.type("utukusii")
        harness.press(.space, .shift)
        let lattice = try #require(harness.lattice)
        #expect(lattice.association == AssociationHeading(headword: "美しい", label: "見た目が快い", group: 1, groupCount: 2))
        let focused = try #require(lattice.columns.first { $0.isFocused })
        #expect(focused.alternatives == ["綺麗", "麗しい", "華麗"])
        #expect(focused.selectedAlternative == 0)
        #expect(focused.variants.isEmpty)
        #expect(harness.marked.text == "綺麗")
    }

    @Test("↓ で次の語，→ で次の意味のまとまり．前のまとまりに出た語は繰り返さない．Enter で確定し，学習しない")
    func navigateAndCommit() throws {
        let harness = harness()
        harness.type("utukusii")
        harness.press(.space, .shift)
        harness.press(.down)
        #expect(harness.marked.text == "麗しい")
        harness.press(.right)
        let lattice = try #require(harness.lattice)
        #expect(lattice.association?.label == "心を打つ")
        #expect(lattice.columns.first(where: \.isFocused)?.alternatives == ["清らか"])
        harness.press(.enter)
        #expect(harness.committed == "清らか")
        #expect(harness.converter.committed.allSatisfy { $0.text != "清らか" })
    }

    @Test("Esc で元の変換に戻る．もう一度 Esc で読みに戻る")
    func escapeReturnsToConversion() throws {
        let harness = harness()
        harness.type("utukusii")
        harness.press(.space, .shift)
        harness.press(.down)
        harness.press(.escape)
        let lattice = try #require(harness.lattice)
        #expect(lattice.association == nil)
        #expect(harness.marked.text == "美しい")
        #expect(harness.committed.isEmpty)
    }

    @Test("変換中の Ctrl+Tab で連想の一覧にし，もう一度押すと元の変換に戻る．変換中の Shift+Space は前の候補のまま")
    func controlTabInConversion() throws {
        let harness = harness()
        harness.type("utukusii")
        harness.press(.space)
        #expect(harness.lattice?.association == nil)
        harness.press(.tab, .control)
        #expect(harness.lattice?.association?.headword == "美しい")
        harness.press(.tab, .control)
        #expect(harness.lattice?.association == nil)
        #expect(harness.marked.text == "美しい")
        harness.press(.down)
        harness.press(.space, .shift)
        #expect(harness.marked.text == "美しい")
        #expect(harness.lattice?.association == nil)
    }

    @Test("連想の一覧で一覧の外のコマンドを押すと，選んでいる語を文節に入れて元の変換に戻ってから行う")
    func otherCommandsKeepTheWord() {
        let harness = harness()
        harness.type("utukusii")
        harness.press(.space, .shift)
        harness.press(.down)
        harness.press(.down, .shift)
        #expect(harness.lattice?.association == nil)
        #expect(harness.marked.text == "麗しい")
        harness.press(.enter)
        #expect(harness.committed == "麗しい")
    }

    @Test("連想の一覧で文字を打つと，選んでいる語を確定して打ち続ける")
    func typingCommitsTheWord() {
        let harness = harness()
        harness.type("utukusii")
        harness.press(.space, .shift)
        harness.press(.down)
        harness.type("a")
        #expect(harness.committed == "麗しい")
        #expect(harness.marked.text == "あ")
    }

    @Test("番号キーで語を選んで確定する")
    func numberKeyCommits() {
        let harness = harness()
        harness.type("utukusii")
        harness.press(.space, .shift)
        harness.press(.character("3"))
        #expect(harness.committed == "華麗")
    }

    @Test("候補を一覧で出す設定では，連想も一覧に出す")
    func listPresentation() throws {
        let harness = harness(makeSettings { $0.candidatePresentation = .list })
        harness.type("utukusii")
        harness.press(.space, .shift)
        let panel = try #require(harness.panel)
        #expect(panel.association?.headword == "美しい")
        #expect(panel.entries.map(\.text) == ["綺麗", "麗しい", "華麗"])
        #expect(panel.variants.isEmpty)
        #expect(panel.position == 1 && panel.total == 3)
        harness.press(.right)
        #expect(harness.panel?.entries.map(\.text) == ["清らか"])
        harness.press(.escape)
        #expect(harness.panel?.association == nil)
        #expect(harness.marked.text == "美しい")
        harness.press(.tab, .control)
        harness.press(.enter)
        #expect(harness.committed == "綺麗")
    }

    @Test("どの辞書にも見出しが無ければ読みでも引く")
    func fallsBackToReading() throws {
        let lookup = FakeAssociationLookup([Self.dictionary.id: ["うつくしい": Self.groups]])
        let harness = harness(lookup: lookup)
        harness.type("utukusii")
        harness.press(.space, .shift)
        #expect(lookup.queries == ["美しい", "うつくしい"])
        #expect(harness.lattice?.association?.headword == "美しい")
    }

    @Test("連想が無ければ変換のまま知らせる．辞書が無ければ辞書が無いことを知らせる")
    func notFound() {
        let missing = harness(lookup: FakeAssociationLookup())
        missing.type("utukusii")
        missing.press(.space, .shift)
        #expect(missing.lattice?.association == nil)
        #expect(missing.lattice?.note == "連想はありません")

        let noDictionary = harness(makeSettings { $0.associationDictionaries = [] })
        noDictionary.type("utukusii")
        noDictionary.press(.space, .shift)
        #expect(noDictionary.lattice?.note == "連想の辞書がありません")
    }

    @Test("連想変換を切ると，入力中の Shift+Space はふつうの変換．変換中の Ctrl+Tab は何もしない")
    func disabled() {
        let harness = harness(makeSettings { $0.association = false })
        harness.type("utukusii")
        harness.press(.space, .shift)
        #expect(harness.lattice != nil)
        #expect(harness.lattice?.association == nil)
        #expect(harness.lattice?.note == nil)
        harness.press(.tab, .control)
        #expect(harness.lattice?.association == nil)
        #expect(harness.marked.text == "美しい")
    }

    @Test("選んでいる候補に連想があれば，分岐図の足元に連想のキーを知らせる．知らせない設定では出さない")
    func hint() {
        let harness = harness()
        harness.type("utukusii")
        harness.press(.space)
        #expect(harness.lattice?.associationHint == "⌃Tab 連想")
        harness.press(.down)
        #expect(harness.lattice?.associationHint == nil)

        let quiet = self.harness(makeSettings { $0.showsAssociationHint = false })
        quiet.type("utukusii")
        quiet.press(.space)
        #expect(quiet.lattice?.associationHint == nil)
    }

    @Test("一覧に出す語の数は設定の数まで")
    func limit() throws {
        let harness = harness(makeSettings { $0.associationLimit = 2 })
        harness.type("utukusii")
        harness.press(.space, .shift)
        #expect(harness.lattice?.association?.groupCount == 1)
        #expect(harness.lattice?.columns.first(where: \.isFocused)?.alternatives == ["綺麗", "麗しい"])
    }
}
