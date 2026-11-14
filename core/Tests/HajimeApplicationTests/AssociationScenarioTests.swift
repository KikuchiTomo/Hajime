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
        // 連想の語だけを確かめる．変換マクロ(既定でオン)を入れると，どの語にも「整形」のまとまりが足される
        settings.conversionMacros = false
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
        #expect(harness.lattice?.trunkFocused == false)
        // 候補にいるときの ← は，幹の上へ戻る
        harness.press(.left)
        #expect(harness.lattice?.trunkFocused == true)
        #expect(harness.lattice?.columns.firstIndex(where: \.isFocused) == 0)
    }

    @Test("長い文: 先の枝の丸を出さない作り(Windows)でも，まとまりに区切り，文節へ移るキーをまとまりの中で数える")
    func segmentGroupsWithoutStations() throws {
        let reading = "あいうえお"
        let five = FakeConverter([reading: [("亜胃鵜絵尾", nil)], "あ": [("亜", nil)], "い": [("胃", nil)], "う": [("鵜", nil)], "え": [("絵", nil)], "お": [("尾", nil)]])
        five.words[reading] = ["亜", "胃", "鵜", "絵", "尾"].map { Candidate.Word(text: $0, readingCount: 1) }
        var settings = makeSettings { $0.branchSegmentsPerGroup = 3 }
        settings.initialFocus = .start
        let harness = Harness(converter: five, settings: settings, keyNames: .windows, branchStations: false, groupsBranchSegments: true)
        harness.type("aiueo")
        harness.press(.space)
        let first = try #require(harness.lattice)
        #expect(first.group == 0..<3 && first.detail == nil)
        #expect(first.columns.prefix(3).allSatisfy { $0.jumpKey != nil } && first.columns.suffix(2).allSatisfy { $0.jumpKey == nil })
        // 4 番目の文節へ移ると，次のまとまりに入れ替わり，キーもそのまとまりの中で数える
        harness.press(.right)
        harness.press(.right)
        harness.press(.right)
        let second = try #require(harness.lattice)
        #expect(second.columns.firstIndex(where: \.isFocused) == 3 && second.group == 3..<5)
        #expect(second.columns.prefix(3).allSatisfy { $0.jumpKey == nil } && second.columns[3].jumpKey == first.columns[0].jumpKey)
        // 旗が無ければ(前の作り)区切らない
        let plain = Harness(converter: five, settings: settings, keyNames: .windows, branchStations: false, groupsBranchSegments: false)
        plain.type("aiueo")
        plain.press(.space)
        #expect(plain.lattice?.group == nil)
    }

    @Test("長い文: 区切らない設定で文節がキーの数より多いときは，選んでいる文節のまわりの 8 文節に，文節へ移るキーを付ける")
    func jumpKeysFollowFocus() throws {
        let kana = ["あ", "い", "う", "え", "お", "か", "き", "く", "け", "こ"]
        let reading = kana.joined()
        let words = ["亜", "胃", "鵜", "絵", "尾", "蚊", "木", "区", "毛", "子"]
        var table: [String: [(text: String, readingCount: Int?)]] = [reading: [(words.joined(), nil)]]
        for (character, word) in zip(kana, words) { table[character] = [(word, nil)] }
        let ten = FakeConverter(table)
        ten.words[reading] = words.map { Candidate.Word(text: $0, readingCount: 1) }
        var settings = makeSettings { $0.branchSegmentsPerGroup = 0 }
        settings.initialFocus = .start
        let harness = Harness(converter: ten, settings: settings, branchStations: true)
        harness.type("aiueokakikukeko")
        harness.press(.space)
        #expect(harness.lattice?.group == nil)
        #expect(harness.lattice?.columns.map(\.jumpKey) == ["⌥A", "⌥S", "⌥D", "⌥F", "⌥J", "⌥K", "⌥L", "⌥;", nil, nil])
        // 9 番目の文節へ移ると，9 番目からの文節にキーが付く
        harness.press(.end)
        #expect(harness.lattice?.columns.firstIndex(where: \.isFocused) == 9)
        #expect(harness.lattice?.columns.map(\.jumpKey) == [nil, nil, nil, nil, nil, nil, nil, nil, "⌥A", "⌥S"])
        harness.press(.character("a"), .option)
        #expect(harness.lattice?.columns.firstIndex(where: \.isFocused) == 8)
    }

    @Test("矢印で木をたどる: 文字種は横に並ぶので，幹の上の ↑ で入り，← → で移り，↓ で幹の上へ戻る．端では動かない")
    func variantsByHorizontalArrows() throws {
        let two = FakeConverter(["きょうはいい": [("今日はいい", nil)], "きょうは": [("今日は", nil)], "いい": [("良い", nil), ("いい", nil)]])
        two.words["きょうはいい"] = [
            Candidate.Word(text: "今日", readingCount: 3), Candidate.Word(text: "はいい", readingCount: 3, startsWithParticle: true),
        ]
        var settings = makeSettings { _ in }
        settings.initialFocus = .start
        let harness = Harness(converter: two, settings: settings, branchStations: true)
        harness.type("kyouhaii")
        harness.press(.space)
        harness.press(.up)
        #expect(harness.lattice?.trunkFocused == true)
        // 幹の上の ↑ で，文字種の先頭(ひらがな)に入る
        harness.press(.up)
        #expect(harness.lattice?.trunkFocused == false && harness.lattice?.columns.first?.selectedVariant == 0)
        // 先頭の ← と，上へは動かない
        harness.press(.left)
        harness.press(.up)
        #expect(harness.lattice?.columns.first?.selectedVariant == 0 && harness.lattice?.columns.firstIndex(where: \.isFocused) == 0)
        // → で次の文字種(カタカナ)へ．文節は移らない
        harness.press(.right)
        #expect(harness.lattice?.columns.first?.selectedVariant == 1 && harness.lattice?.columns.firstIndex(where: \.isFocused) == 0)
        harness.press(.left)
        #expect(harness.lattice?.columns.first?.selectedVariant == 0)
        // ↓ で幹の上へ戻る
        harness.press(.down)
        #expect(harness.lattice?.trunkFocused == true && harness.lattice?.columns.first?.selectedVariant == nil)
        // 2 番目の文字種からも，↓ の 1 回で幹の上へ戻る(1 つ前の文字種へは移らない)
        harness.press(.up)
        harness.press(.right)
        #expect(harness.lattice?.columns.first?.selectedVariant == 1)
        harness.press(.down)
        #expect(harness.lattice?.trunkFocused == true && harness.lattice?.columns.first?.selectedVariant == nil)
        #expect(harness.lattice?.columns.first?.selectedAlternative == 0)
    }

    @Test("矢印で木をたどる: 先の枝を左へ出しているとき(反転)は，← で先の枝へ入って進み，→ で戻る．丸の中身でも同じ向き")
    func mirroredBranch() throws {
        let harness = stationHarness()
        harness.type("utukusii")
        harness.press(.space)
        harness.session.branchMirrored = true
        // 候補の上の → は，先の枝と反対の向きなので，幹の上へ戻る
        harness.press(.right)
        #expect(harness.lattice?.detail?.current == nil)
        #expect(harness.lattice?.trunkFocused == true)
        harness.press(.down)
        #expect(harness.lattice?.trunkFocused == false)
        // ← で先の枝の最初の丸へ，もう一度 ← で次の丸へ
        harness.press(.left)
        #expect(harness.lattice?.detail?.current == 0)
        let count = try #require(harness.lattice?.detail?.stations.count)
        #expect(count >= 2)
        harness.press(.left)
        #expect(harness.lattice?.detail?.current == 1)
        // → で前の丸へ，最初の丸の → で候補へ戻る
        harness.press(.right)
        #expect(harness.lattice?.detail?.current == 0)
        harness.press(.right)
        #expect(harness.lattice?.detail?.current == nil)
    }

    @Test("長い文: 文節が上限を超えたら，選んでいる文節のまとまりだけを出す．文節へ移るキーは，出しているまとまりの中で数える．0 なら区切らない")
    func segmentGroups() throws {
        let reading = "あいうえお"
        let five = FakeConverter([reading: [("亜胃鵜絵尾", nil)], "あ": [("亜", nil)], "い": [("胃", nil)], "う": [("鵜", nil)], "え": [("絵", nil)], "お": [("尾", nil)]])
        five.words[reading] = ["亜", "胃", "鵜", "絵", "尾"].map { Candidate.Word(text: $0, readingCount: 1) }
        var settings = makeSettings { $0.branchSegmentsPerGroup = 3 }
        settings.initialFocus = .start
        let harness = Harness(converter: five, settings: settings, branchStations: true)
        harness.type("aiueo")
        harness.press(.space)
        let first = try #require(harness.lattice)
        #expect(first.columns.count == 5 && first.group == 0..<3)
        #expect(first.columns.map(\.jumpKey) == ["⌥A", "⌥S", "⌥D", nil, nil])
        let shown = first.shownGroup()
        #expect(shown.panel.columns.map(\.text) == ["亜", "胃", "鵜"] && shown.offset == 0)
        #expect(shown.panel.continuesBefore == false && shown.panel.continuesAfter == true)
        // 3 番目から → で 4 番目へ移ると，次のまとまりに入れ替わる
        harness.press(.character("d"), .option)
        harness.press(.right)
        let second = try #require(harness.lattice)
        #expect(second.columns.firstIndex(where: \.isFocused) == 3 && second.group == 3..<5)
        #expect(second.columns.map(\.jumpKey) == [nil, nil, nil, "⌥A", "⌥S"])
        #expect(second.shownGroup().panel.continuesBefore == true && second.shownGroup().panel.continuesAfter == false)
        // 文節へ移るキーは，出しているまとまりの中で数える．まとまりに無い位置は何もしない
        harness.press(.character("s"), .option)
        #expect(harness.lattice?.columns.firstIndex(where: \.isFocused) == 4)
        harness.press(.character("d"), .option)
        #expect(harness.lattice?.columns.firstIndex(where: \.isFocused) == 4)
        // 区切らない設定では，文の全体を出す
        var whole = makeSettings { $0.branchSegmentsPerGroup = 0 }
        whole.branchWindowWidth = .fixed
        let all = Harness(converter: five, settings: whole, branchStations: true)
        all.type("aiueo")
        all.press(.space)
        #expect(all.lattice?.group == nil && all.lattice?.keepsWidth == true)
        #expect(all.lattice?.columns.map(\.jumpKey) == ["⌥A", "⌥S", "⌥D", "⌥F", "⌥J"])
        #expect(harness.lattice?.keepsWidth == false)
    }

    @Test("矢印で木をたどる: 先頭の候補で ↑ を押すと幹の上へ上り，幹の上の ← → は文節を移り，↓ で候補へ下りる．丸の上の Space は中身に入らず次の候補")
    func trunkLevel() throws {
        let two = FakeConverter(["きょうはいい": [("今日はいい", nil)], "きょうは": [("今日は", nil)], "いい": [("良い", nil), ("いい", nil)]])
        two.words["きょうはいい"] = [
            Candidate.Word(text: "今日", readingCount: 3), Candidate.Word(text: "はいい", readingCount: 3, startsWithParticle: true),
        ]
        var settings = makeSettings { $0.conversionMacros = true }
        settings.initialFocus = .start
        let harness = Harness(converter: two, settings: settings, branchStations: true)
        harness.type("kyouhaii")
        harness.press(.space)
        #expect(harness.lattice?.trunkFocused == false)
        // 先頭の候補で ↑: 幹の上へ．選んでいる候補は変わらない
        harness.press(.up)
        #expect(harness.lattice?.trunkFocused == true)
        #expect(harness.lattice?.columns.first?.selectedAlternative == 0)
        // 幹の上の → は次の文節(候補の先の枝ではない)
        harness.press(.right)
        #expect(harness.lattice?.columns.firstIndex(where: \.isFocused) == 1)
        #expect(harness.lattice?.trunkFocused == true && harness.lattice?.detail?.current == nil)
        // ↓ で候補へ下りる．選んでいる候補は変えない
        harness.press(.down)
        #expect(harness.lattice?.trunkFocused == false)
        #expect(harness.lattice?.columns[1].selectedAlternative == 0)
        // 候補の上の → は先の枝へ
        harness.press(.right)
        #expect(harness.lattice?.detail?.current == 0)
        // 丸の上の Space は，中身に入らずに候補へ戻って次の候補へ進む(選ぶつもりのない中身を入れない)
        harness.press(.space)
        #expect(harness.lattice?.detail?.current == nil && harness.lattice?.association == nil)
        #expect(harness.lattice?.columns[1].selectedAlternative == 1)
    }

    @Test("先の枝: 丸の中身で Enter を押すと，選んだ語をその文節に採って幹の上へ戻る．全文は確定しない．もう一度 Enter で確定する．連想変換のキーでも先の枝へ入れる．先の枝が無ければ → は次の文節")
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
        #expect(harness.committed.isEmpty)
        #expect(harness.marked.text == Self.groups[0].words[1])
        #expect(harness.lattice?.association == nil && harness.lattice?.detail?.current == nil)
        #expect(harness.lattice?.trunkFocused == true)
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

    /// 2 文節の文．2 番目の文節「うつくしい」に連想がある
    private func twoSegmentHarness(_ change: (inout Settings) -> Void = { _ in }) -> Harness {
        let converter = FakeConverter([
            "きょうはうつくしい": [("今日は美しい", nil)], "きょうは": [("今日は", nil), ("京は", nil), ("教は", nil)],
            "うつくしい": [("美しい", nil), ("美しき", nil)],
        ])
        converter.words["きょうはうつくしい"] = [
            Candidate.Word(text: "今日は", readingCount: 4), Candidate.Word(text: "美しい", readingCount: 5),
        ]
        let lookup = FakeAssociationLookup([Self.dictionary.id: ["美しい": Self.groups]])
        var settings = makeSettings(change)
        settings.initialFocus = .start
        return Harness(converter: converter, settings: settings, associations: lookup, branchStations: true)
    }

    @Test("先の枝: 丸の中身で選んだ語は，戻る向きの矢印でもその文節に採る．そのままほかの文節の候補を選べて，最後に Enter で全文を確定する")
    func adoptItemAndContinue() throws {
        let harness = twoSegmentHarness()
        harness.type("kyouhautukusii")
        harness.press(.space)
        // 2 番目の文節へ移り，連想の丸の中身で 2 番目の語を選ぶ
        harness.press(.up)
        harness.press(.right)
        harness.press(.down)
        harness.press(.right)
        #expect(harness.lattice?.detail?.current == 0)
        harness.press(.down)
        harness.press(.down)
        #expect(harness.lattice?.detail?.selectedItem == 1)
        // ← で戻る: 選んでいる語を文節に採って幹の上へ．全文は確定しない
        harness.press(.left)
        #expect(harness.committed.isEmpty)
        #expect(harness.marked.text == "今日は" + Self.groups[0].words[1])
        #expect(harness.lattice?.association == nil && harness.lattice?.trunkFocused == true)
        #expect(harness.lattice?.columns.firstIndex(where: \.isFocused) == 1)
        // 幹の上の ← で前の文節へ移り，候補を選ぶ．採った語はそのまま
        harness.press(.left)
        harness.press(.down)
        harness.press(.down)
        #expect(harness.marked.text == "京は" + Self.groups[0].words[1])
        harness.press(.enter)
        #expect(harness.committed == "京は" + Self.groups[0].words[1])
    }

    @Test("先の枝: 丸の中身の番号キーも，その語を文節に採るだけで全文は確定しない．先頭の項目の ↑ と Esc は採らずに戻る")
    func adoptItemByNumber() throws {
        let harness = twoSegmentHarness()
        harness.type("kyouhautukusii")
        harness.press(.space)
        harness.press(.up)
        harness.press(.right)
        harness.press(.down)
        harness.press(.right)
        harness.press(.down)
        // 先頭の項目の ↑ は丸へ戻り，元の語に戻る
        harness.press(.up)
        #expect(harness.marked.text == "今日は美しい" && harness.lattice?.detail?.current == 0)
        // Esc も採らずに戻る
        harness.press(.down)
        harness.press(.down)
        harness.press(.escape)
        #expect(harness.marked.text == "今日は美しい")
        // 番号キーは採る
        harness.press(.right)
        harness.press(.down)
        harness.type("3")
        #expect(harness.committed.isEmpty)
        #expect(harness.marked.text == "今日は" + Self.groups[0].words[2])
        #expect(harness.lattice?.trunkFocused == true)
    }

    @Test("矢印で木をたどる: 候補を選んだあと，先の枝と反対の向きの矢印で幹の上へ戻る．選んだ候補は変わらず，幹の上の ← → でほかの文節へ移れる")
    func backToTrunkKeepsCandidate() throws {
        let harness = twoSegmentHarness()
        harness.type("kyouhautukusii")
        harness.press(.space)
        harness.press(.down)
        harness.press(.down)
        #expect(harness.marked.text == "教は美しい")
        harness.press(.left)
        #expect(harness.lattice?.trunkFocused == true)
        #expect(harness.lattice?.columns.firstIndex(where: \.isFocused) == 0)
        #expect(harness.marked.text == "教は美しい")
        harness.press(.right)
        #expect(harness.lattice?.columns.firstIndex(where: \.isFocused) == 1)
        #expect(harness.marked.text == "教は美しい")
    }

    @Test("矢印で木をたどらない表(Windows 風)でも，丸の中身の Enter は語を文節に採るだけで，全文は確定しない")
    func adoptItemWithoutTreeNavigation() throws {
        let harness = twoSegmentHarness { $0.keymap = KeymapPreset.windows.keymap }
        harness.type("kyouhautukusii")
        harness.press(.space)
        harness.press(.right)
        #expect(harness.lattice?.columns.firstIndex(where: \.isFocused) == 1)
        harness.press(.up, .shift)
        #expect(harness.lattice?.detail?.current == 0)
        harness.press(.down)
        harness.press(.down)
        harness.press(.enter)
        #expect(harness.committed.isEmpty)
        #expect(harness.marked.text == "今日は" + Self.groups[0].words[1])
        #expect(harness.lattice?.trunkFocused == false)
        harness.press(.enter)
        #expect(harness.committed == "今日は" + Self.groups[0].words[1])
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
