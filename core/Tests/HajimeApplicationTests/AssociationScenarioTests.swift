import HajimeApplication
import HajimeDomain
import HajimeTestSupport
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

    private func harness(_ settings: Settings? = nil, lookup: FakeAssociationLookup? = nil, keyNames: KeyNameStyle = .mac) -> Harness {
        let converter = FakeConverter(["うつくしい": [("美しい", nil), ("美しき", nil)]], clauses: ["うつくしい": [("美しい", 5), ("美しき", 5)]])
        let lookup = lookup ?? FakeAssociationLookup([Self.dictionary.id: ["美しい": Self.groups]])
        return Harness(converter: converter, settings: settings ?? makeSettings(), associations: lookup, keyNames: keyNames)
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

    @Test("変換中の Shift+↑ で連想の一覧にし，もう一度押すと元の変換に戻る．変換中の Shift+Space は前の候補のまま")
    func controlTabInConversion() throws {
        let harness = harness()
        harness.type("utukusii")
        harness.press(.space)
        #expect(harness.lattice?.association == nil)
        harness.press(.up, .shift)
        #expect(harness.lattice?.association?.headword == "美しい")
        harness.press(.up, .shift)
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
        harness.press(.up, .shift)
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
        #expect(missing.lattice?.note?.text == "連想候補なし")

        let noDictionary = harness(makeSettings { $0.associationDictionaries = [] })
        noDictionary.type("utukusii")
        noDictionary.press(.space, .shift)
        #expect(noDictionary.lattice?.note?.text == "連想辞書なし")
    }

    @Test("連想変換を切ると，入力中の Shift+Space はふつうの変換．変換中の Ctrl+Tab は何もしない")
    func disabled() {
        let harness = harness(makeSettings { $0.association = false })
        harness.type("utukusii")
        harness.press(.space, .shift)
        #expect(harness.lattice != nil)
        #expect(harness.lattice?.association == nil)
        #expect(harness.lattice?.note == nil)
        harness.press(.up, .shift)
        #expect(harness.lattice?.association == nil)
        #expect(harness.marked.text == "美しい")
    }

    /// 先の枝を丸として出す作り(macOS の分岐図)の試し．変換マクロもオンにする
    private func stationHarness(_ change: (inout Settings) -> Void = { _ in }) -> Harness {
        let converter = FakeConverter(["うつくしい": [("美しい", nil), ("美しき", nil)]], clauses: ["うつくしい": [("美しい", 5), ("美しき", 5)]])
        let lookup = FakeAssociationLookup([Self.dictionary.id: ["美しい": Self.groups]])
        let settings = makeSettings {
            $0.conversionMacros = true
            change(&$0)
        }
        return Harness(converter: converter, settings: settings, associations: lookup, branchStations: true)
    }

    @Test("先の枝: 連想と変換マクロは別々の丸になる．→ で候補から丸へ入り，→ ← で丸を移り，↓ で丸の中身へ入り，↑ で戻る")
    func branchStations() throws {
        let harness = stationHarness()
        harness.type("utukusii")
        harness.press(.space)
        // 候補にいるあいだ: 丸は並ぶが，どの丸にも入っていない．連想の語と変換マクロは混ざらない
        var detail = try #require(harness.lattice?.detail)
        #expect(detail.stations.map(\.kind) == [.association, .macro])
        #expect(detail.stations.map(\.title) == ["連想", "マクロ"])
        #expect(detail.current == nil && detail.items.isEmpty)
        // → で最初の丸(連想)へ．丸の上では中身の先頭のページが見えるが，まだ選んでいない
        harness.press(.right)
        detail = try #require(harness.lattice?.detail)
        #expect(detail.current == 0 && detail.selectedItem == nil)
        #expect(detail.items == Self.groups[0].words)
        #expect(harness.lattice?.association == nil)
        #expect(harness.marked.text == "美しい")
        // → で次の丸(マクロ)へ．中身は変換マクロの結果だけ
        harness.press(.right)
        detail = try #require(harness.lattice?.detail)
        #expect(detail.current == 1)
        #expect(!detail.items.isEmpty && Set(detail.items).isDisjoint(with: Self.groups.flatMap(\.words)))
        let macro = try #require(detail.items.first)
        // ↓ で丸の中身へ入る．先頭の結果を選び，入力欄に入る．元の候補は控えめに出すために残す
        harness.press(.down)
        detail = try #require(harness.lattice?.detail)
        #expect(detail.current == 1 && detail.selectedItem == 0)
        #expect(detail.candidates == ["美しい", "美しき"] && detail.selectedCandidate == 0)
        #expect(harness.marked.text == macro)
        // ↑ で丸の上へ戻り，元の語に戻る．← で前の丸へ，もう一度 ← で候補へ戻る
        harness.press(.up)
        #expect(harness.lattice?.detail?.current == 1 && harness.lattice?.detail?.selectedItem == nil)
        #expect(harness.marked.text == "美しい")
        harness.press(.left)
        #expect(harness.lattice?.detail?.current == 0)
        harness.press(.left)
        #expect(harness.lattice?.detail?.current == nil)
        // 候補にいるときの ← は，今までどおり前の文節(文節が 1 つなので動かない)
        #expect(harness.lattice?.columns.firstIndex(where: \.isFocused) == 0)
    }

    @Test("先の枝: 丸の中身で Enter を押すと選んだ語で確定する．連想変換のキーでも先の枝へ入れる．先の枝が無ければ → は次の文節")
    func branchCommit() throws {
        let harness = stationHarness()
        harness.type("utukusii")
        harness.press(.space)
        harness.press(.up, .shift)
        #expect(harness.lattice?.detail?.current == 0)
        harness.press(.down)
        harness.press(.down)
        #expect(harness.lattice?.detail?.selectedItem == 1)
        harness.press(.enter)
        #expect(harness.committed == Self.groups[0].words[1])

        // 連想も変換マクロも語の意味も無い語では，丸が無い．→ は今までどおり次の文節へ移る
        let two = FakeConverter(["きょうはいい": [("今日はいい", nil)], "きょうは": [("今日は", nil)], "いい": [("良い", nil), ("いい", nil)]])
        two.words["きょうはいい"] = [
            Candidate.Word(text: "今日", readingCount: 3), Candidate.Word(text: "はいい", readingCount: 3, startsWithParticle: true),
        ]
        let plain = Harness(converter: two, settings: makeSettings { $0.association = false }, branchStations: true)
        plain.type("kyouhaii")
        plain.press(.space)
        #expect(plain.lattice?.detail == nil)
        plain.press(.right)
        #expect(plain.lattice?.columns.firstIndex(where: \.isFocused) == 1)
    }

    @Test("表示項目を減らす設定では，文字種の枝は文字種を選んでいるあいだだけ，候補の先の枝は連想変換のキーで開いたあとだけ出す")
    func fewerItems() {
        let harness = harness(makeSettings { $0.showsFewerItems = true })
        harness.type("utukusii")
        harness.press(.space)
        // 畳んでいる枝は中身を入れず，畳んでいることだけを伝える
        #expect(harness.lattice?.columns.first?.variants.isEmpty == true)
        #expect(harness.lattice?.collapsesVariants == true)
        #expect(harness.lattice?.associationHint == nil)
        #expect(harness.lattice?.collapsesDetail == true)
        // 1 回目の連想変換のキーで先の枝を開く．連想の一覧にはまだ移らない
        harness.press(.up, .shift)
        #expect(harness.lattice?.association == nil)
        #expect(harness.lattice?.associationHint == AssociationHint(key: "⇧↑", label: "連想"))
        #expect(harness.lattice?.collapsesDetail == false)
        // 2 回目で連想の一覧に移る
        harness.press(.up, .shift)
        #expect(harness.lattice?.association != nil)
        harness.press(.escape)
        // 第 1 候補から前の候補へ進むと文字種に入り，文字種の枝が出る
        harness.press(.up)
        #expect(harness.lattice?.columns.first?.selectedVariant != nil)
        #expect(harness.lattice?.columns.first?.variants.isEmpty == false)
        #expect(harness.lattice?.collapsesVariants == false)

        // 設定がオフなら，どちらも始めから出す
        let full = self.harness()
        full.type("utukusii")
        full.press(.space)
        #expect(full.lattice?.columns.first?.variants.isEmpty == false)
        #expect(full.lattice?.collapsesVariants == false)
        #expect(full.lattice?.collapsesDetail == false)
    }

    @Test("選んでいる候補に連想があれば，分岐図の足元に連想のキーを知らせる．知らせない設定では出さない")
    func hint() {
        let harness = harness()
        harness.type("utukusii")
        harness.press(.space)
        #expect(harness.lattice?.associationHint == AssociationHint(key: "⇧↑", label: "連想"))
        harness.press(.down)
        #expect(harness.lattice?.associationHint == nil)

        // Windows のエンジンでは Windows のキーの書き方で知らせる
        let windows = self.harness(keyNames: .windows)
        windows.type("utukusii")
        windows.press(.space)
        #expect(windows.lattice?.associationHint == AssociationHint(key: "Shift+↑", label: "連想"))

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
