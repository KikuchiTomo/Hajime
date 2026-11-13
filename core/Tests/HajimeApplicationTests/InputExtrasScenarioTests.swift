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
                       wrap: { SupplementedConverter($0, settings: $1, calendar: FakeCalendar()) }, calendar: FakeCalendar())
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
        #expect(panel.entries.first?.command == nil)
        // 一覧では印を除いた名前に，種類と「コマンド」のタグを付けて見せる
        let entry = try #require(panel.entries.dropFirst().first)
        #expect(entry.text == Self.claude.title)
        #expect(entry.command == .openApplication)
        #expect(entry.annotation == CandidatePanel.commandAnnotation)
        #expect(panel.note == nil)
        harness.press(.enter)
        #expect(harness.committed == "クロード")
        #expect(harness.ranCommands.isEmpty)
    }

    @Test("R-22: 一覧でコマンドの候補を選んで確定したときだけ動かし，文字は入れない")
    func commandRunsWhenChosen() throws {
        let harness = harness(.listPresentation, change: withCommands)
        harness.type("kuro-do")
        harness.press(.space)
        harness.press(.space)
        // 選んでいるあいだは，確定のキーで動くことを足元に出す．入力中の文字には印を付けた名前を出す
        let note = try #require(harness.panel?.note)
        #expect(note.key == "Enter")
        #expect(note.keyAction == "実行")
        #expect(note.text == "Enter 実行")
        #expect(harness.marked.text == Self.claude.candidateText)
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
        let index = try #require(lattice.columns[0].alternatives.firstIndex(of: Self.claude.title))
        #expect(index > 0)
        #expect(lattice.columns[0].alternativeCommands[index] == .openApplication)
        #expect(lattice.columns[0].alternativeCommands[0] == nil)
        #expect(lattice.columns[0].alternativeNotes[index] == CandidatePanel.commandAnnotation)
        #expect(lattice.note == nil)
        for _ in 0..<index { harness.press(.down) }
        #expect(harness.lattice?.note?.keyAction == "実行")
        harness.press(.enter)
        #expect(harness.ranCommands == [Self.claude])
        #expect(harness.committed.isEmpty)
    }

    @Test("R-22: 文節ごとの一覧でも，コマンドに種類とタグを付け，選んでいるあいだは確定のキーで動くことを出す")
    func commandInSegmentList() throws {
        let harness = harness(change: {
            withCommands(&$0)
            $0.candidatePresentation = .segmentList
        })
        harness.type("kuro-do")
        harness.press(.space)
        let panel = try #require(harness.panel)
        let index = try #require(panel.entries.firstIndex { $0.command != nil })
        #expect(index > 0)
        #expect(panel.entries[index].text == Self.claude.title)
        #expect(panel.entries[index].annotation == CandidatePanel.commandAnnotation)
        #expect(panel.note == nil)
        for _ in 0..<index { harness.press(.down) }
        #expect(harness.panel?.note?.keyAction == "実行")
        harness.press(.enter)
        #expect(harness.ranCommands == [Self.claude])
    }

    @Test("R-22: コマンドを使わない設定と，使わないコマンドは出さない")
    func commandsOff() throws {
        let off = harness(.listPresentation) {
            $0.commands = [Self.claude]
            $0.launcherCommands = false
        }
        off.type("kuro-do")
        off.press(.space)
        #expect(try #require(off.panel).entries.allSatisfy { $0.command == nil && $0.text != Self.claude.title })

        var disabled = Self.claude
        disabled.isEnabled = false
        let harness = harness(.listPresentation) {
            $0.launcherCommands = true
            $0.commands = [disabled]
        }
        harness.type("kuro-do")
        harness.press(.space)
        #expect(try #require(harness.panel).entries.allSatisfy { $0.command == nil && $0.text != Self.claude.title })
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
            $0.dynamicDictionary = false
        }
        off.type("nitiji")
        off.press(.space)
        #expect(try #require(off.panel).entries.first?.text == entry.word)
    }

    @Test("R-21: コメントを付けた語は候補のタグにコメントを出し，タグを押すとコメントを入れる．長いコメントはタグでは先頭だけを出す")
    func userComment() throws {
        let address = "東京都千代田区千代田1-1 ピヨピヨビル 10 階 受付"
        let harness = harness(.listPresentation, table: ["かいしゃ": [("会社", nil)]]) {
            $0.userDictionary = [UserDictionaryEntry(reading: "かいしゃ", word: "ピヨ株式会社", comment: address)]
        }
        harness.type("kaisya")
        harness.press(.space)
        let panel = try #require(harness.panel)
        let index = try #require(panel.entries.firstIndex { $0.text == "ピヨ株式会社" })
        #expect(panel.entries[index].hasComment)
        #expect(panel.entries[index].annotation == String(address.prefix(DefaultSettings.userDictionaryCommentShownLength)) + "…")
        #expect(panel.entries.filter(\.hasComment).count == 1)
        harness.click(.comment(index))
        #expect(harness.committed == address)
    }

    @Test("R-21: 分岐図でも，コメントを付けた語の枝にコメントを添え，押すとその文節をコメントにする")
    func userCommentInLattice() throws {
        let harness = harness(table: ["かいしゃ": [("会社", nil)]]) {
            $0.userDictionary = [UserDictionaryEntry(reading: "かいしゃ", word: "ピヨ株式会社", comment: "ぴよ")]
        }
        harness.type("kaisya")
        harness.press(.space)
        let columns = harness.lattice?.columns ?? []
        let column = try #require(columns.first { $0.isFocused })
        let index = try #require(column.alternatives.firstIndex(of: "ピヨ株式会社"))
        #expect(column.alternativeNotes[index] == "ぴよ")
        #expect(column.alternativeComments[index])
        harness.click(.comment(index))
        harness.press(.enter)
        #expect(harness.committed == "ぴよ")
    }

    // MARK: 単語の登録と入力メニュー(R-21)

    @Test("R-21: 入力中の単語の登録のキーは，見えている語と読みを登録に渡し，組み立て中の文字は入れずに消す")
    func registerWordWhileComposing() throws {
        let harness = harness(table: ["かいしゃ": [("会社", nil)]])
        harness.type("kaisya")
        harness.press(.space)
        harness.press(.function(7), .control)
        #expect(harness.registrations.count == 1)
        #expect(harness.registrations.first?.word == "会社")
        #expect(harness.registrations.first?.reading == "かいしゃ")
        #expect(harness.committed.isEmpty)
        #expect(harness.marked.text.isEmpty)
    }

    @Test("R-21: 入力していないときの単語の登録は，選んでいる文字を読めるアプリなら読んでもらい，読めなければ空の欄で開く")
    func registerWordWhileIdle() {
        let harness = harness()
        harness.press(.function(7), .control)
        #expect(harness.registrations.count == 1)
        #expect(harness.registrations.first?.word == nil)
        harness.context.canReadSelectionForRegistration = false
        harness.press(.function(7), .control)
        #expect(harness.registrations.last?.word == "")
    }

    @Test("R-21: 入力メニューのキー(Ctrl+F10・Ctrl+変換)は入力メニューを出す．出せないアプリではキーをそのまま渡す")
    func openMenu() {
        let harness = harness()
        harness.press(.function(10), .control)
        harness.press(.henkan, .control)
        #expect(harness.openedMenus == 2)
        harness.context.canOpenMenu = false
        harness.press(.function(10), .control)
        #expect(harness.openedMenus == 2)
        #expect(!harness.lastResult.handled)
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

    @Test("R-22: 利用者が足した変換マクロを一覧に並べ，オフにしたマクロは並べない")
    func customMacros() throws {
        let added = ConversionMacro(pattern: "【{text}】")
        let harness = harness(table: ["とうきょう": [("東京", nil)]]) {
            $0.association = false
            $0.conversionMacros = true
            $0.macros = [added, ConversionMacro(pattern: "〈{text}〉", isEnabled: false)]
        }
        harness.type("toukyou")
        harness.press(.space, .shift)
        let alternatives = try #require(harness.lattice?.columns.first(where: \.isFocused)?.alternatives)
        #expect(alternatives.first == "【東京】")
        #expect(!alternatives.contains("〈東京〉"))
        #expect(!alternatives.contains("「東京」"))
    }

    @Test("R-22: 変換マクロの日時は暦から読む．かなの語には，語と読みを並べる形を出さない")
    func macrosUseCalendarAndSkipKanaWords() throws {
        let macros = [ConversionMacro(pattern: "{text}（{date:M/D}）"), ConversionMacro(pattern: "{text}（{reading}）")]
        let harness = harness(table: ["とうきょう": [("東京", nil)], "すし": [("すし", nil)]]) {
            $0.association = false
            $0.conversionMacros = true
            $0.macros = macros
        }
        harness.type("toukyou")
        harness.press(.space, .shift)
        let kanji = try #require(harness.lattice?.columns.first { $0.isFocused })
        #expect(kanji.alternatives == ["東京（10/26）", "東京（とうきょう）"])
        harness.press(.escape)
        harness.press(.escape)
        harness.press(.escape)
        harness.type("susi")
        harness.press(.space, .shift)
        let kana = try #require(harness.lattice?.columns.first { $0.isFocused })
        #expect(kana.alternatives == ["すし（10/26）"])
    }

    @Test("R-22: 設定の画面の「試す」は，見本の語に有効な変換マクロを当て，書いている途中の形はその形だけを当てる")
    func macroPreview() {
        var settings = DefaultSettings.settings
        settings.macros = [ConversionMacro(pattern: "【{text}】"), ConversionMacro(pattern: "{text}（{reading}）"),
                           ConversionMacro(pattern: "<{text}>", isEnabled: false)]
        let store = FakeSettings(settings)
        let preview = ConversionMacroPreview(settings: store, calendar: FakeCalendar())
        #expect(preview.preview(text: "", reading: "") == ["【東京】", "東京（とうきょう）"])
        #expect(preview.preview(text: " すし ", reading: "") == ["【すし】"])
        #expect(preview.preview(text: "大阪", reading: "オオサカ") == ["【大阪】", "大阪（おおさか）"])
        #expect(preview.preview(text: "大阪", reading: "おおさか", pattern: "{text}（{date:M/D}）") == ["大阪（10/26）"])
        #expect(preview.preview(text: "", reading: "", pattern: String(repeating: "x", count: DefaultSettings.maximumMacroPatternLength + 1)).isEmpty)
        store.current.macroSkipsSameReading = false
        #expect(preview.preview(text: "すし", reading: "") == ["【すし】", "すし（すし）"])
    }

    @Test("R-22: 変換マクロも連想変換も使わない設定なら，連想変換のキーはふつうの変換になる")
    func macrosOff() {
        let harness = harness(table: ["とうきょう": [("東京", nil)]]) {
            $0.association = false
            $0.conversionMacros = false
        }
        harness.type("toukyou")
        harness.press(.space, .shift)
        #expect(harness.lattice?.association == nil)
    }
}
