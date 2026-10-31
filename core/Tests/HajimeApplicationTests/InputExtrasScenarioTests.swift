import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

@MainActor
@Suite("コマンド・ローマ字の読み・動的な語・変換マクロ・手のずれ(入力の流れ)")
struct InputExtrasScenarioTests {
    private static let claude = LauncherCommand(id: "0F8E2C1A-3B4D-4E5F-8A9B-1C2D3E4F5A6B", reading: "くろーど", title: "Claude を開く",
                                                kind: .openApplication, target: "/Applications/Claude.app")

    private func harness(_ base: Settings = DefaultSettings.settings, table: [String: [(text: String, readingCount: Int?)]] = ["くろーど": [("クロード", nil)]],
                         change: (inout Settings) -> Void = { _ in }) -> Harness {
        var settings = base
        settings.liveConversionSkipLength = 0
        change(&settings)
        return Harness(converter: FakeConverter(table), settings: settings,
                       wrap: { SupplementedConverter($0, settings: $1, calendar: FakeCalendar()) })
    }

    private func withCommands(_ settings: inout Settings) {
        settings.launcherCommands = true
        settings.commands = [Self.claude]
    }

    // MARK: コマンド(R-22)

    @Test("R-22: 打っているあいだ(ライブ変換)にはコマンドを出さず，Enter で確定しても動かない")
    func commandNeverInLiveConversion() {
        let harness = harness(change: withCommands)
        harness.type("kuro-do")
        harness.settle()
        #expect(harness.marked.text == "クロード")
        harness.press(.enter)
        #expect(harness.committed == "クロード")
        #expect(harness.ranCommands.isEmpty)
    }

    @Test("R-22: 一覧ではコマンドが 2 番目に並び，そのまま Enter では第 1 候補を確定する")
    func commandIsSecondInList() throws {
        let harness = harness(.listPresentation, change: withCommands)
        harness.type("kuro-do")
        harness.press(.space)
        let panel = try #require(harness.panel)
        #expect(panel.entries.first?.text == "クロード")
        #expect(panel.entries.dropFirst().first?.text == Self.claude.candidateText)
        harness.press(.enter)
        #expect(harness.committed == "クロード")
        #expect(harness.ranCommands.isEmpty)
    }

    @Test("R-22: 一覧でコマンドの候補を選んで確定したときだけ動かし，文字は入れない")
    func commandRunsWhenChosen() {
        let harness = harness(.listPresentation, change: withCommands)
        harness.type("kuro-do")
        harness.press(.space)
        harness.press(.space)
        harness.press(.enter)
        #expect(harness.ranCommands == [Self.claude])
        #expect(harness.committed.isEmpty)
        #expect(!harness.session.isComposing)
    }

    @Test("R-22: 分岐図でも，読み全体の文節の下の枝にコマンドが並び，選んで確定したときだけ動く")
    func commandInLattice() throws {
        let harness = harness(change: withCommands)
        harness.type("kuro-do")
        harness.press(.space)
        let lattice = try #require(harness.lattice)
        #expect(lattice.columns.count == 1)
        #expect(lattice.columns[0].text == "クロード")
        #expect(lattice.columns[0].alternatives.contains(Self.claude.candidateText))
        let index = try #require(lattice.columns[0].alternatives.firstIndex(of: Self.claude.candidateText))
        #expect(index > 0)
        for _ in 0..<index { harness.press(.down) }
        harness.press(.enter)
        #expect(harness.ranCommands == [Self.claude])
        #expect(harness.committed.isEmpty)
    }

    @Test("R-22: コマンドを使わない設定と，使わないコマンドは出さない")
    func commandsOff() throws {
        let off = harness(.listPresentation) { $0.commands = [Self.claude] }
        off.type("kuro-do")
        off.press(.space)
        #expect(try #require(off.panel).entries.allSatisfy { $0.text != Self.claude.candidateText })

        var disabled = Self.claude
        disabled.isEnabled = false
        let harness = harness(.listPresentation) {
            $0.launcherCommands = true
            $0.commands = [disabled]
        }
        harness.type("kuro-do")
        harness.press(.space)
        #expect(try #require(harness.panel).entries.allSatisfy { $0.text != Self.claude.candidateText })
    }

    @Test("R-22: 一覧を出してからコマンドを使わない設定にしたら，選んで確定しても動かさず読みを入れる")
    func commandRemovedAfterListing() {
        let harness = harness(.listPresentation, change: withCommands)
        harness.type("kuro-do")
        harness.press(.space)
        harness.press(.space)
        harness.settings.current.launcherCommands = false
        harness.press(.enter)
        #expect(harness.ranCommands.isEmpty)
        #expect(harness.committed == "くろーど")
    }

    // MARK: ユーザー辞書(R-21)

    @Test("R-21: ローマ字の読みで登録した語は，そのキーを打って変換すると出る")
    func romajiReading() throws {
        let harness = harness(.listPresentation, table: [:]) {
            $0.userDictionary = [UserDictionaryEntry(reading: "gh", word: "GitHub"), UserDictionaryEntry(reading: "toyota", word: "トヨタ自動車")]
        }
        harness.type("gh")
        harness.press(.space)
        #expect(try #require(harness.panel).entries.first?.text == "GitHub")
        harness.press(.escape)
        harness.press(.escape)
        harness.press(.enter)

        let toyota = self.harness(.listPresentation, table: [:]) { $0.userDictionary = [UserDictionaryEntry(reading: "toyota", word: "トヨタ自動車")] }
        toyota.type("toyota")
        toyota.press(.space)
        #expect(try #require(toyota.panel).entries.first?.text == "トヨタ自動車")
    }

    @Test("R-21: 動的なユーザー辞書をオンにすると，{datetime:...} を入れるときの日時にする．オフなら書いたまま")
    func dynamicDictionary() throws {
        let entry = UserDictionaryEntry(reading: "にちじ", word: "{datetime:YYYY/MM/DD hh:mm}")
        let on = harness(.listPresentation, table: [:]) {
            $0.userDictionary = [entry]
            $0.dynamicDictionary = true
            $0.dateConversion = false
        }
        on.type("nitiji")
        on.press(.space)
        #expect(try #require(on.panel).entries.first?.text == "2026/10/26 14:05")

        let off = harness(.listPresentation, table: [:]) {
            $0.userDictionary = [entry]
            $0.dateConversion = false
        }
        off.type("nitiji")
        off.press(.space)
        #expect(try #require(off.panel).entries.first?.text == entry.word)
    }

    // MARK: 変換マクロ(R-22)

    @Test("R-22: 変換マクロをオンにすると，連想変換のキーで選んでいる語を整えた形の一覧を出す(連想の辞書が無くても)")
    func macrosInAssociationList() throws {
        let harness = harness(table: ["とうきょう": [("東京", nil)]]) {
            $0.association = false
            $0.conversionMacros = true
        }
        harness.type("toukyou")
        harness.press(.space, .shift)
        let lattice = try #require(harness.lattice)
        #expect(lattice.association?.label == DefaultSettings.macroGroupLabel)
        #expect(lattice.columns.first(where: \.isFocused)?.alternatives.first == "「東京」")
        harness.press(.enter)
        #expect(harness.committed == "「東京」")
    }

    @Test("R-22: 変換マクロも連想変換も使わない設定なら，連想変換のキーはふつうの変換になる")
    func macrosOff() {
        let harness = harness(table: ["とうきょう": [("東京", nil)]]) { $0.association = false }
        harness.type("toukyou")
        harness.press(.space, .shift)
        #expect(harness.lattice?.association == nil)
    }
}
