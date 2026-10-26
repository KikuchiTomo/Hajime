import S90Application
import S90Domain
import S90TestSupport
import Testing

/// キーの列を流し込み，画面への操作を確かめる．要件(R-xx)の受け入れ条件はここで確かめる
extension Settings {
    /// 候補を一覧で出す設定．一覧の動きを確かめるテストで使う
    static var listPresentation: Settings {
        var settings = DefaultSettings.settings
        settings.candidatePresentation = .list
        return settings
    }
}

@MainActor
final class Harness {
    let converter: FakeConverter
    let lexicon: FakeLexicon
    let settings: FakeSettings
    let session: InputSession
    var context = InputContext()
    private(set) var committed = ""
    private(set) var marked = MarkedText.empty
    private(set) var panel: CandidatePanel?
    private(set) var lattice: LatticePanel?
    private(set) var note: String?
    private(set) var lastResult = KeyResult.passThrough

    init(converter: FakeConverter = FakeConverter(), lexicon: FakeLexicon = FakeLexicon(), settings: Settings = DefaultSettings.settings) {
        self.converter = converter
        self.lexicon = lexicon
        self.settings = FakeSettings(settings)
        self.session = InputSession(converter: converter, lexicon: lexicon, settings: self.settings)
    }

    func type(_ text: String) {
        for character in text { press(.character(character)) }
    }

    /// 打鍵が止まり，さらに長く止まったときの処理(ライブ変換の表示と打ち間違いの見直し)
    func settle() {
        for action in session.settle(context: context) + session.review(context: context) {
            switch action {
            case .setMarkedText(let text): marked = text
            case .showNote(let text): note = text
            case .hideCandidates: note = nil
            default: break
            }
        }
    }

    func press(_ key: KeyEvent.Key, _ modifiers: KeyEvent.Modifiers = [], isKeypad: Bool = false) {
        lastResult = session.handle(KeyEvent(key, modifiers: modifiers, isKeypad: isKeypad), context: context)
        for action in lastResult.actions {
            switch action {
            case .commit(let text): committed += text
            case .setMarkedText(let text): marked = text
            case .showCandidates(let value): panel = value
            case .showLattice(let value): lattice = value
            case .showNote(let text): note = text
            case .hideCandidates:
                panel = nil
                lattice = nil
                note = nil
            case .showModeIndicator, .selectMode, .selectInputStyle, .openSettings, .toggleLiveConversion, .showHandwriting: break
            }
        }
    }
}

@Suite("入力の流れ")
@MainActor
struct InputSessionScenarioTests {
    @Test("打っている途中の ⌥Space で区切りを入れると，その位置で文節を分ける")
    func insertBoundaryWhileTyping() {
        let converter = FakeConverter(["きょうは": [("京は", nil)], "きょう": [("今日", nil)], "は": [("は", nil)]])
        let harness = Harness(converter: converter)
        harness.type("kyou")
        harness.press(.space, .option)
        harness.type("ha")
        harness.settle()
        #expect(harness.marked.segments.map(\.text).prefix(2) == ["今日", "は"])
        harness.press(.space)
        #expect(harness.lattice?.columns.map(\.text) == ["今日", "は"])
        harness.press(.enter)
        #expect(harness.committed == "今日は")
    }

    @Test("区切りを入れたあと Backspace でその位置より前に戻ると，区切りも消える")
    func boundaryRemovedByBackspace() {
        let converter = FakeConverter(["きょうは": [("京は", nil)], "きょう": [("今日", nil)], "きょ": [("巨", nil)]])
        let harness = Harness(converter: converter)
        harness.type("kyou")
        harness.press(.space, .option)
        harness.press(.backspace)
        harness.type("uha")
        harness.press(.space)
        #expect(harness.lattice?.columns.map(\.text) == ["京は"])
    }

    @Test("分岐図の ⇧↓ で区切れる位置に番号を出し，数字で選んだ位置で区切る")
    func splitInLattice() {
        let converter = FakeConverter(["きょうは": [("京は", nil)], "きょう": [("今日", nil)], "は": [("は", nil)]])
        let harness = Harness(converter: converter)
        harness.type("kyouha")
        harness.press(.space)
        #expect(harness.lattice?.columns.count == 1)
        harness.press(.down, .shift)
        // 小さい「ょ」の前には番号を出さない
        #expect(harness.lattice?.note?.hasPrefix("きょ①う②は") == true)
        harness.press(.character("2"))
        #expect(harness.lattice?.columns.map(\.text) == ["今日", "は"])
        #expect(harness.lattice?.note == nil)
    }

    @Test("区切れる位置は小さい仮名と長音の前を除き，9 個まで")
    func splitPositions() {
        #expect(InputSession.splitPositions(of: "きょうは") == [2, 3])
        #expect(InputSession.splitPositions(of: "らーめん") == [2, 3])
        #expect(InputSession.splitPositions(of: "あ") == [])
        #expect(InputSession.splitPositions(of: String(repeating: "あ", count: 20)).count == 9)
    }

    @Test("R-01: 打ちながらライブ変換の結果を表示し，Enter で確定する")
    func liveConversion() {
        let harness = Harness(converter: FakeConverter(["へんかん": [("変換", nil)]]))
        harness.type("henkan")
        // 末尾の n はまだ ん にしない
        #expect(harness.marked.text == "へんかn")
        harness.type("n")
        // nn を打った時点で ん にする
        #expect(harness.marked.text == "変換")
        harness.press(.enter)
        #expect(harness.committed == "変換")
        #expect(harness.marked.isEmpty)
    }

    @Test("ライブ変換を切ると読みのまま表示する")
    func liveConversionOff() {
        var settings = DefaultSettings.settings
        settings.liveConversion = false
        let harness = Harness(converter: FakeConverter(["へんかん": [("変換", nil)]]), settings: settings)
        harness.type("henkann")
        #expect(harness.marked.text == "へんかん")
        harness.press(.enter)
        #expect(harness.committed == "へんかん")
    }

    @Test("Space で候補を選び，番号キーで確定する")
    func selectCandidate() {
        let harness = Harness(converter: FakeConverter(["きしゃ": [("記者", nil), ("汽車", nil), ("帰社", nil)]]), settings: .listPresentation)
        harness.type("kisha")
        harness.press(.space)
        #expect(harness.panel?.entries.map(\.text) == ["記者", "汽車", "帰社"])
        #expect(harness.panel?.selectedEntry == 0)
        harness.press(.space)
        #expect(harness.panel?.selectedEntry == 1)
        #expect(harness.marked.text == "汽車")
        harness.type("3")
        #expect(harness.committed == "帰社")
        #expect(harness.panel == nil)
    }

    @Test("読みの先頭だけの候補を確定すると，残りを続けて確定する")
    func partialCommit() {
        let converter = FakeConverter([
            "きょうはあめ": [("今日は", 4)],
            "あめ": [("雨", nil)],
        ])
        let harness = Harness(converter: converter, settings: .listPresentation)
        harness.type("kyouhaame")
        harness.press(.space)
        harness.press(.enter)
        #expect(harness.committed == "今日は雨")
        #expect(converter.committed.count == 2)
    }

    @Test("R-03: 候補の先頭で上キーを押すと種類の行に移り，左右で選ぶ")
    func variantRow() {
        let harness = Harness(converter: FakeConverter(["とうきょう": [("東京", nil)]]), settings: .listPresentation)
        harness.type("toukyou")
        harness.press(.space)
        harness.press(.up)
        #expect(harness.panel?.focus == .variants)
        #expect(harness.panel?.selectedVariant == 0)
        harness.press(.right)
        #expect(harness.panel?.selectedVariant == 1)
        #expect(harness.marked.text == "トウキョウ")
        harness.press(.right)
        harness.press(.right)
        harness.press(.right)
        #expect(harness.marked.text == "toukyou")
        harness.press(.down)
        #expect(harness.panel?.focus == .candidate)
        harness.press(.enter)
        #expect(harness.committed == "東京")
    }

    @Test("R-03: Control+K でカタカナにする")
    func controlK() {
        let harness = Harness()
        harness.type("sushi")
        harness.press(.character("k"), .control)
        harness.press(.enter)
        #expect(harness.committed == "スシ")
    }

    @Test("R-02: ローマ字のまま打った英単語を補正し，Space で打ったままに戻す")
    func correctEnglishWord() {
        let harness = Harness(lexicon: FakeLexicon(words: ["python"]))
        harness.type("python")
        #expect(harness.marked.segments == [.init("python", style: .correction)])
        harness.press(.space)
        #expect(harness.marked.text == "pyてょn")
        // 取り消したあとは補正し直さない
        harness.type("s")
        #expect(!harness.marked.segments.contains { $0.style == .correction })
    }

    @Test("R-02: 文の途中に打った英単語も補正する")
    func correctWordInSentence() {
        let harness = Harness(converter: FakeConverter(["このばーじょんの": [("このバージョンの", nil)]]), lexicon: FakeLexicon(words: ["python"]))
        harness.type("konoba-jonnnopython")
        #expect(harness.marked.segments == [.init("このバージョンの", style: .converted), .init("python", style: .correction)])
    }

    @Test("R-02: 補正した英単語のあとは Enter を押さずに続けて日本語を打てる")
    func continueAfterCorrection() {
        let converter = FakeConverter([
            "このばーじょんの": [("このバージョンの", nil)],
            "このばーじょんのpythonは": [("このバージョンのpythonは", nil)],
        ])
        let harness = Harness(converter: converter, lexicon: FakeLexicon(words: ["python"]))
        harness.type("konoba-jonnnopythonha")
        #expect(harness.marked.text == "このバージョンのpythonは")
        harness.press(.enter)
        #expect(harness.committed == "このバージョンのpythonは")
    }

    @Test("R-02: 綴りの誤りの補正で，前の日本語まで英単語に飲み込まない")
    func misspellingDoesNotSwallowJapanese() {
        let lexicon = FakeLexicon(suggestions: ["nopthon": ["python"], "pthon": ["python"]])
        let harness = Harness(converter: FakeConverter(["この": [("この", nil)]]), lexicon: lexicon)
        harness.type("konopthon")
        #expect(harness.marked.segments == [.init("この", style: .converted), .init("python", style: .correction)])
    }

    @Test("R-02: 確定させた英単語の後ろの日本語は補正しない")
    func noCorrectionAfterFrozenWord() {
        let lexicon = FakeLexicon(words: ["python", "kodo"])
        let harness = Harness(lexicon: lexicon)
        harness.type("pythonnokodo")
        #expect(harness.marked.text.hasPrefix("python"))
        #expect(!harness.marked.segments.contains { $0.style == .correction })
    }

    @Test("R-02: 次のキーで別の英単語になるときは英単語のまま続ける")
    func extendCorrectedWord() {
        let harness = Harness(lexicon: FakeLexicon(words: ["python", "pythons"]))
        harness.type("pythons")
        #expect(harness.marked.segments == [.init("pythons", style: .correction)])
    }

    @Test("R-02: 綴りの誤りを補正し，Enter で補正した単語を確定する")
    func correctMisspelling() {
        let harness = Harness(lexicon: FakeLexicon(suggestions: ["pthon": ["python"]]))
        harness.type("pthon")
        #expect(harness.marked.text == "python")
        harness.press(.enter)
        #expect(harness.committed == "python")
    }

    @Test("R-02: Shift で打った大文字を含む並びは英単語として直さず，打ったままにする(「konoIMEha」→「このIMEは」)")
    func uppercaseIsNotCorrected() {
        let harness = Harness(lexicon: FakeLexicon(suggestions: ["konoIMEha": ["KinoMaha"], "IMEha": ["Imeha"]]))
        harness.type("konoIMEha")
        #expect(harness.marked.text == "このIMEは")
    }

    @Test("R-02: 一覧のときは，補正した単語の次に打ったままの文字列を出す")
    func correctionCandidates() {
        let harness = Harness(lexicon: FakeLexicon(words: ["python"]), settings: .listPresentation)
        harness.type("python")
        harness.press(.down)
        #expect(harness.panel?.entries.prefix(2).map(\.text) == ["python", "pyてょn"])
        #expect(harness.panel?.entries[1].annotation == "入力のまま")
    }

    @Test("R-02: 分岐図のときは，補正した単語を読みに入れてから分岐図にする")
    func correctionInBranchMap() {
        let harness = Harness(lexicon: FakeLexicon(words: ["python"]))
        harness.type("python")
        harness.press(.down)
        #expect(harness.panel == nil)
        #expect(harness.lattice?.columns.map(\.text).joined() == "python")
    }

    @Test("R-04: ¥ キーは既定で \\ を入れる")
    func yenKey() {
        let harness = Harness()
        harness.press(.yen)
        #expect(harness.committed == "\\")
        harness.press(.yen, .option)
        #expect(harness.committed == "\\¥")
    }

    @Test("R-04: 英数モードでも ¥ キーの設定に従う")
    func yenKeyInDirectMode() {
        let harness = Harness()
        harness.press(.eisu)
        harness.press(.yen)
        #expect(harness.committed == "\\")
        harness.press(.character("a"))
        #expect(!harness.lastResult.handled)
    }

    @Test("R-06: プログラミング用のアプリでは，組み立てていないときの半角の記号をアプリに渡す")
    func programmingSymbols() {
        let harness = Harness()
        harness.context = InputContext(profile: .programming)
        harness.press(.character("("))
        #expect(!harness.lastResult.handled)
        harness.context = InputContext(profile: .standard)
        harness.press(.character("("))
        #expect(harness.marked.text == "（")
    }

    @Test("英数キーで確定して英数モードに移る")
    func eisuCommits() {
        let harness = Harness()
        harness.type("aiu")
        harness.press(.eisu)
        #expect(harness.committed == "あいう")
        #expect(harness.session.mode == .direct)
    }

    @Test("打ち始めに入力位置の前の文字列を変換の手がかりとして渡す")
    func leftContext() {
        let converter = FakeConverter()
        let harness = Harness(converter: converter)
        harness.context = InputContext(precedingText: "AAA")
        harness.type("made")
        #expect(converter.leftContext == "AAA")
    }

    @Test("nn のあとの母音は，変換の点数が高い読みを選ぶ(onna → 女，hannei → 反映)")
    func nasalReading() {
        let converter = FakeConverter([
            "おんな": [("女", nil)], "おんあ": [("温亜", nil)],
            "はんえい": [("反映", nil)], "はんねい": [("反寧", nil)],
        ])
        converter.scores = ["おんな": -10, "おんあ": -30, "はんえい": -12, "はんねい": -25]
        let harness = Harness(converter: converter)
        harness.type("onna")
        #expect(harness.marked.text == "女")
        harness.press(.enter)
        harness.type("hannei")
        #expect(harness.marked.text == "反映")
    }

    @Test("Escape で組み立て中の文字を消す")
    func escape() {
        let harness = Harness()
        harness.type("aiu")
        harness.press(.escape)
        #expect(harness.marked.isEmpty)
        #expect(harness.committed.isEmpty)
    }

    @Test("Backspace で 1 文字ずつ消し，空になったら表示を消す")
    func backspace() {
        let harness = Harness()
        harness.type("ka")
        harness.press(.backspace)
        #expect(harness.marked.isEmpty)
        harness.press(.backspace)
        #expect(!harness.lastResult.handled)
    }

    @Test("パスワード欄では何もしない")
    func secure() {
        let harness = Harness()
        harness.context = InputContext(isSecure: true)
        harness.press(.character("a"))
        #expect(!harness.lastResult.handled)
    }

    @Test("Command を押したら組み立て中の文字を確定してアプリに渡す")
    func command() {
        let harness = Harness()
        harness.type("ai")
        harness.press(.character("s"), .command)
        #expect(harness.committed == "あい")
        #expect(!harness.lastResult.handled)
    }

    @Test("Option との組み合わせはアプリに渡す")
    func option() {
        let harness = Harness()
        harness.type("ka")
        harness.press(.character("å"), .option)
        #expect(harness.committed == "か")
        #expect(!harness.lastResult.handled)
    }

    // MARK: - 分岐図

    /// 「今日は / 雨」の 2 文節．「今日は」と「京は」は点数が近いので，最初の文節が迷う文節になる
    private func latticeConverter() -> FakeConverter {
        let converter = FakeConverter(
            ["きょうはあめ": [("今日は雨", nil)], "あめ": [("雨", nil)], "きょう": [("今日", nil)], "はあめ": [("は雨", nil)]],
            clauses: [
                "きょうはあめ": [("今日は", 4), ("京は", 4)],
                "あめ": [("雨", 2), ("飴", 2)],
                "はあめ": [("は雨", 3)],
            ]
        )
        converter.clauseScoreStep["きょうはあめ"] = 1
        return converter
    }

    @Test("Space で分岐図を出し，入力位置にいちばん近い迷う文節に注目する")
    func latticeAppears() {
        let harness = Harness(converter: latticeConverter())
        harness.type("kyouhaame")
        harness.press(.space)
        #expect(harness.panel == nil)
        #expect(harness.lattice?.columns.map(\.text) == ["今日は", "雨"])
        #expect(harness.lattice?.columns.map(\.isUncertain) == [true, false])
        #expect(harness.lattice?.columns.first?.isFocused == true)
        #expect(harness.marked.segments.map(\.style) == [.focused, .converted])
    }

    @Test("最初に選ぶ文節は設定に従う．先頭・末尾・自動(第 1 候補と 2 番目の差がいちばん小さい文節)", arguments: [
        (InitialFocus.start, [true, false]),
        (InitialFocus.end, [false, true]),
        (InitialFocus.automatic, [true, false]),
    ])
    func latticeInitialFocus(policy: InitialFocus, expected: [Bool]) {
        var settings = DefaultSettings.settings
        settings.initialFocus = policy
        let harness = Harness(converter: latticeConverter(), settings: settings)
        harness.type("kyouhaame")
        harness.press(.space)
        #expect(harness.lattice?.columns.map(\.isFocused) == expected)
    }

    @Test("分岐図は文節が 1 つでも出す")
    func latticeSingleSegment() {
        let harness = Harness(converter: FakeConverter(["あめ": [("雨", nil), ("飴", nil)]], clauses: ["あめ": [("雨", 2), ("飴", 2)]]))
        harness.type("ame")
        harness.press(.space)
        #expect(harness.lattice?.columns.map(\.text) == ["雨"])
        #expect(harness.lattice?.columns.first?.alternatives == ["雨", "飴"])
    }

    @Test("分岐図: →で文節を移り，↓で候補を変え，Enter で全体を確定する")
    func latticeNavigation() {
        let converter = latticeConverter()
        let harness = Harness(converter: converter)
        harness.type("kyouhaame")
        harness.press(.space)
        harness.press(.right)
        harness.press(.down)
        #expect(harness.marked.text == "今日は飴")
        #expect(harness.lattice?.columns[1].isDecided == true)
        harness.press(.enter)
        #expect(harness.committed == "今日は飴")
        #expect(converter.committed.count == 2)
    }

    @Test("分岐図: ↑で上の枝の字種(そのまま・カタカナ・半角カタカナ)を選び，上の端で止まる")
    func latticeVariants() {
        let harness = Harness(converter: latticeConverter())
        harness.type("kyouhaame")
        harness.press(.space)
        #expect(harness.lattice?.columns[0].variants == ["きょうは", "キョウハ", "ｷｮｳﾊ"])
        harness.press(.up)
        #expect(harness.marked.text == "きょうは雨")
        #expect(harness.lattice?.columns[0].selectedVariant == 0)
        #expect(harness.lattice?.columns[0].selectedAlternative == nil)
        harness.press(.up)
        harness.press(.up)
        harness.press(.up)
        #expect(harness.marked.text == "ｷｮｳﾊ雨")
        // ↓で幹に戻る
        harness.press(.down)
        harness.press(.down)
        harness.press(.down)
        #expect(harness.marked.text == "今日は雨")
    }

    @Test("分岐図: 番号で選ぶと，選んでいない迷う文節が残っていなければ確定する")
    func latticeNumbers() {
        let harness = Harness(converter: latticeConverter())
        harness.type("kyouhaame")
        harness.press(.space)
        harness.type("2")
        #expect(harness.committed == "京は雨")
    }

    @Test("分岐図: Tab は迷う文節だけを渡り歩く")
    func latticeTab() {
        let harness = Harness(converter: latticeConverter())
        harness.type("kyouhaame")
        harness.press(.space)
        harness.press(.right)
        harness.press(.tab)
        #expect(harness.lattice?.columns.map(\.isFocused) == [true, false])
    }

    @Test("分岐図: Shift+← で文節を縮め，後ろを分け直す")
    func latticeResize() {
        let harness = Harness(converter: latticeConverter())
        harness.type("kyouhaame")
        harness.press(.space)
        harness.press(.left, .shift)
        #expect(harness.lattice?.columns.map(\.text) == ["今日", "は雨"])
    }

    @Test("注目していない迷う文節には，次の候補を 1 つだけ添える")
    func latticePreview() {
        let harness = Harness(converter: latticeConverter())
        harness.type("kyouhaame")
        harness.press(.space)
        harness.press(.right)
        #expect(harness.lattice?.columns[0].preview == "京は")
        #expect(harness.lattice?.columns[0].alternatives.isEmpty == true)
        #expect(harness.lattice?.columns[1].preview == nil)
    }

    @Test("一覧の設定なら文節が多くても一覧を出す")
    func listSetting() {
        var settings = DefaultSettings.settings
        settings.candidatePresentation = .list
        let harness = Harness(converter: latticeConverter(), settings: settings)
        harness.type("kyouhaame")
        harness.press(.space)
        #expect(harness.lattice == nil)
        #expect(harness.panel != nil)
    }

    @Test("文節格子で Escape を押すと読みに戻る")
    func latticeEscape() {
        let harness = Harness(converter: latticeConverter())
        harness.type("kyouhaame")
        harness.press(.space)
        harness.press(.escape)
        #expect(harness.lattice == nil)
        #expect(harness.committed.isEmpty)
    }
}

@MainActor
@Suite("記号")
struct SymbolScenarioTests {
    @Test("「->」と打つとライブ変換の表示が「→」になる")
    func arrowSequence() {
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings())
        var marked = ""
        for key in "a->" {
            for action in session.handle(KeyEvent(.character(key)), context: InputContext()).actions {
                if case .setMarkedText(let text) = action { marked = text.text }
            }
        }
        #expect(marked == "あ→")
    }

    @Test("z と記号のキーで記号を入れる")
    func zSymbol() {
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings())
        var marked = ""
        for key in "z." {
            for action in session.handle(KeyEvent(.character(key)), context: InputContext()).actions {
                if case .setMarkedText(let text) = action { marked = text.text }
            }
        }
        #expect(marked == "…")
    }

    @Test("読みから引いた記号を，第 1 候補を変えずに候補へ足す")
    func supplement() {
        let converter = SupplementedConverter(FakeConverter(["やじるし": [("矢印", nil), ("やじるし", nil)]]), settings: FakeSettings(), calendar: FakeCalendar())
        let texts = converter.candidates(for: "やじるし").map(\.text)
        #expect(texts.first == "矢印")
        #expect(texts.contains("→"))
        #expect(texts.firstIndex(of: "→") == 2)
    }

    @Test("記号の変換を切ると記号を足さない")
    func symbolOff() {
        var settings = Settings()
        settings.symbolConversion = false
        let converter = SupplementedConverter(FakeConverter(["やじるし": [("矢印", nil)]]), settings: FakeSettings(settings), calendar: FakeCalendar())
        #expect(converter.candidates(for: "やじるし").map(\.text) == ["矢印"])
    }

    @Test("「きょう」「あした」「いま」を日付と時刻の候補にする")
    func dates() {
        let converter = SupplementedConverter(FakeConverter(["きょう": [("今日", nil)]]), settings: FakeSettings(), calendar: FakeCalendar())
        let today = converter.candidates(for: "きょう").map(\.text)
        #expect(today.first == "今日")
        #expect(today.contains("2026/10/26"))
        #expect(today.contains("10月26日(月)"))
        #expect(today.contains("令和8年10月26日"))
        #expect(converter.candidates(for: "あした").map(\.text).contains("2026-10-27"))
        #expect(converter.candidates(for: "いま").map(\.text).contains("14:05"))
        #expect(converter.candidates(for: "ことし").map(\.text).contains("令和8年"))
    }

    @Test("ユーザー辞書の語は読みが一致すれば先頭に置く")
    func userDictionary() {
        var settings = Settings()
        settings.userDictionary = [UserDictionaryEntry(reading: "えすきゅー", word: "s90")]
        let converter = SupplementedConverter(FakeConverter(["えすきゅー": [("SQ", nil)]]), settings: FakeSettings(settings), calendar: FakeCalendar())
        #expect(converter.candidates(for: "えすきゅー").map(\.text) == ["s90", "SQ"])
    }
}

@MainActor
@Suite("分岐図のキーと文節の長さ")
struct BranchMapControlTests {
    private func converter() -> FakeConverter {
        let converter = FakeConverter([
            "きょうはいい": [("今日はいい", nil)], "きょうは": [("今日は", nil)], "いい": [("良い", nil), ("いい", nil)],
        ])
        converter.words["きょうはいい"] = [
            Candidate.Word(text: "今日", readingCount: 3), Candidate.Word(text: "はいい", readingCount: 3, startsWithParticle: true),
        ]
        return converter
    }

    @Test("割り当てたキーで次の文節へ移る(既定の → の代わりに l)")
    func customBinding() {
        var settings = DefaultSettings.settings
        settings.conversionKeys.assign(KeyStroke(.character("l"), control: true), to: .nextSegment)
        let harness = Harness(converter: converter(), settings: settings)
        harness.type("kyouhaii")
        harness.press(.space)
        #expect(harness.lattice?.columns.firstIndex(where: \.isFocused) == 0)
        harness.press(.character("l"), .control)
        #expect(harness.lattice?.columns.firstIndex(where: \.isFocused) == 1)
    }

    @Test("R-08: 選んでいる候補に同音異義語があれば使い分けを添え，設定で切れる")
    func homophoneNote() {
        let converter = FakeConverter(["とった": [("撮った", nil), ("取った", nil)]])
        let harness = Harness(converter: converter)
        harness.type("totta")
        harness.press(.space)
        #expect(harness.lattice?.columns.first?.usageNote?.hasPrefix("撮る: ") == true)
        var off = DefaultSettings.settings
        off.homophoneNotes = false
        let quiet = Harness(converter: converter, settings: off)
        quiet.type("totta")
        quiet.press(.space)
        #expect(quiet.lattice?.columns.first?.usageNote == nil)
    }

    @Test("上の枝にあるひらがな・カタカナは，下の枝に重ねて出さない")
    func noDuplicateVariants() {
        let converter = FakeConverter(["らいぶ": [("ライブ", nil), ("らいぶ", nil), ("来部", nil)]])
        let harness = Harness(converter: converter)
        harness.type("raibu")
        harness.press(.space)
        let column = harness.lattice?.columns.first(where: \.isFocused)
        #expect(column?.alternatives == ["ライブ", "来部"])
        #expect(column?.variants.contains("らいぶ") == true)
    }

    @Test("足元に，文節を 1 文字短く・長くしたらどうなるかを出す．候補を選んでも文節の長さは変わらない")
    func resizePreview() {
        let harness = Harness(converter: converter())
        harness.type("kyouhaii")
        harness.press(.space)
        harness.press(.left)
        let column = harness.lattice?.columns.first(where: \.isFocused)
        #expect(column?.text == "今日は")
        #expect(column?.longer != nil)
        #expect(column?.shorter != nil)
        let count = harness.lattice?.columns.count
        harness.press(.down)
        harness.press(.down)
        #expect(harness.lattice?.columns.count == count)
    }
}

@MainActor
@Suite("増やした設定")
struct ExtraSettingsTests {
    @Test("IME を使わないアプリでは，日本語のモードでも英字のままアプリに渡す")
    func directProfile() {
        let harness = Harness(converter: FakeConverter(["か": [("蚊", nil)]]))
        harness.context = InputContext(profile: .direct)
        harness.press(.character("k"))
        #expect(harness.lastResult.handled == false)
        #expect(harness.marked.isEmpty)
    }

    @Test("Shift で英字を打ち始めたら，Space まで英字のまま入れる(設定)")
    func shiftStartsAlphabet() {
        var settings = DefaultSettings.settings
        settings.shiftStartsAlphabet = true
        let harness = Harness(settings: settings)
        harness.type("Python")
        #expect(harness.marked.text == "Python")
    }

    @Test("Shift で打った英字を全角にする(設定)")
    func fullwidthAlphabet() {
        var settings = DefaultSettings.settings
        settings.alphabetWidth = .fullwidth
        let harness = Harness(settings: settings)
        harness.type("A")
        #expect(harness.marked.text == "Ａ")
    }

    @Test("分岐図の候補の数を設定で変える")
    func branchCandidates() {
        var settings = DefaultSettings.settings
        settings.branchCandidatesPerPage = 3
        let converter = FakeConverter(["きしゃ": [("記者", nil), ("汽車", nil), ("帰社", nil), ("貴社", nil), ("喜捨", nil)]])
        let harness = Harness(converter: converter, settings: settings)
        harness.type("kisya")
        harness.press(.space)
        #expect(harness.lattice?.columns.first(where: \.isFocused)?.alternatives.count == 3)
    }

    @Test("ターミナルでコマンドを英字で入れる設定を切ると，行の頭も日本語にする")
    func terminalCommandsOff() {
        var settings = DefaultSettings.settings
        settings.terminalCommands = false
        let harness = Harness(converter: FakeConverter(["ls": [("ls", nil)]]), settings: settings)
        harness.context = InputContext(profile: .terminal)
        harness.type("ls")
        harness.press(.space)
        #expect(harness.committed.isEmpty)
    }
}

@MainActor
@Suite("日本語の打ち間違い")
struct ReadingCorrectionScenarioTests {
    private func typed(_ keys: String, corrections: [ReadingCorrection]) -> (InputSession, () -> (marked: String, note: String?)) {
        let converter = FakeConverter()
        converter.corrections[keys] = corrections
        let session = InputSession(converter: converter, lexicon: FakeLexicon(), settings: FakeSettings())
        var marked = ""
        var note: String?
        let record = { (actions: [ClientAction]) in
            for action in actions {
                if case .setMarkedText(let text) = action { marked = text.text }
                if case .showLattice(let panel) = action { note = panel.note }
            }
        }
        for key in keys { record(session.handle(KeyEvent(.character(key)), context: InputContext()).actions) }
        return (session, { (marked, note) })
    }

    @Test("Space で変換するとき，十分にもっともらしい読みに直し，Esc で打ったままに戻す")
    func correctAndUndo() {
        let (session, state) = typed("you", corrections: [
            ReadingCorrection(keys: "yoi", reading: "ヨイ", score: -5, cost: 2),
            ReadingCorrection(keys: "you", reading: "ヨウ", score: -9, cost: 0),
        ])
        #expect(state().marked == "よう")
        var marked = ""
        var note: String?
        for action in session.handle(KeyEvent(.space), context: InputContext()).actions {
            if case .setMarkedText(let text) = action { marked = text.text }
            if case .showLattice(let panel) = action { note = panel.note }
        }
        #expect(marked == "よい")
        #expect(note != nil)
        for action in session.handle(KeyEvent(.escape), context: InputContext()).actions {
            if case .setMarkedText(let text) = action { marked = text.text }
        }
        #expect(marked == "よう")
    }

    @Test("ライブ変換で打鍵が止まったら直して点線で見せ，案内を出す．続けて打ったキーは直した読みに続け，Esc で打ったままに戻す")
    func liveCorrection() {
        let converter = FakeConverter()
        converter.corrections["youdesu"] = [
            ReadingCorrection(keys: "yoidesu", reading: "ヨイデス", score: -5, cost: 2),
            ReadingCorrection(keys: "youdesu", reading: "ヨウデス", score: -9, cost: 0),
        ]
        let harness = Harness(converter: converter)
        harness.type("youdesu")
        #expect(harness.marked.text == "ようです")
        harness.settle()
        #expect(harness.marked.text == "よいです")
        #expect(harness.marked.segments.first?.style == .correction)
        #expect(harness.note?.contains("ようです") == true)
        harness.type("ne")
        #expect(harness.marked.text == "よいですね")
        harness.press(.escape)
        #expect(harness.marked.text == "ようですね")
        // 戻したキーのあいだは，止まっても直し直さない
        harness.settle()
        #expect(harness.marked.text == "ようですね")
    }

    @Test("R-02: 直したあとに分岐図を開くと，直した文節の 2 番目に打ったままの候補を出す")
    func typedAlternativeInLattice() {
        let converter = FakeConverter(["きょうはよいです": [("今日は良いです", nil)], "よいです": [("良いです", nil)], "ようです": [("様です", nil)]])
        converter.words["きょうはよいです"] = [
            Candidate.Word(text: "今日", readingCount: 3), Candidate.Word(text: "は", readingCount: 1, startsWithParticle: true, endsWithParticle: true),
            Candidate.Word(text: "良いです", readingCount: 4),
        ]
        converter.corrections["kyouhayoudesu"] = [
            ReadingCorrection(keys: "kyouhayoidesu", reading: "キョウハヨイデス", score: -5, cost: 2),
            ReadingCorrection(keys: "kyouhayoudesu", reading: "キョウハヨウデス", score: -9, cost: 0),
        ]
        // 自動では，打ち間違いを直した文節を最初に選ぶ
        var settings = DefaultSettings.settings
        settings.initialFocus = .automatic
        let harness = Harness(converter: converter, settings: settings)
        harness.type("kyouhayoudesu")
        harness.settle()
        harness.press(.space)
        let focused = harness.lattice?.columns.first(where: \.isFocused)
        #expect(focused?.text == "良いです")
        #expect(focused?.alternatives.prefix(3) == ["良いです", "様です", "ようです"])
    }

    /// 「youdesu」を「yoidesu」に直す変換器(差 4 で直す)
    private func correctingHarness(margin: Double = 4) -> Harness {
        let converter = FakeConverter()
        converter.corrections["youdesu"] = [
            ReadingCorrection(keys: "yoidesu", reading: "ヨイデス", score: -9 + margin, cost: 2),
            ReadingCorrection(keys: "youdesu", reading: "ヨウデス", score: -9, cost: 0),
        ]
        let harness = Harness(converter: converter)
        harness.type("youdesu")
        harness.settle()
        return harness
    }

    @Test("R-02: 直したあとの Enter は直した文を確定する")
    func commitCorrected() {
        let harness = correctingHarness()
        harness.press(.enter)
        #expect(harness.committed == "よいです")
    }

    @Test("R-02: 案内は見直した直後だけ出し，次のキーで消す．点線の下線は残る")
    func noteDisappearsOnNextKey() {
        let harness = correctingHarness()
        #expect(harness.note != nil)
        harness.type("n")
        #expect(harness.note == nil)
        #expect(harness.marked.segments.first?.style == .correction)
    }

    @Test("R-02: 直したあとに数字を打つと，直したものを受け入れたことにする(Esc で全部消える取りこぼしをしない)")
    func literalAcceptsCorrection() {
        let harness = correctingHarness()
        harness.type("1")
        harness.press(.escape)
        #expect(harness.marked.text.isEmpty)
        // 2 回目の Esc ではなく 1 回目で消えるのは，受け入れたあとの Esc がふつうの取り消しだから．読みは打ったままに戻らない
        #expect(harness.committed.isEmpty)
    }

    @Test("R-02: 直したあとに「'」を打っても，Esc で読みが全部消えない")
    func apostropheAfterCorrection() {
        let harness = correctingHarness()
        harness.type("n'")
        #expect(!harness.marked.segments.contains { $0.style == .correction })
        harness.press(.escape)
        #expect(harness.marked.text.isEmpty)
    }

    @Test("R-02: 直したあとの Backspace で直した部分まで消すと，そこからは直していない読みとして扱う")
    func backspaceIntoCorrection() {
        let harness = correctingHarness()
        harness.press(.backspace)
        #expect(!harness.marked.segments.contains { $0.style == .correction })
        harness.press(.escape)
        #expect(harness.marked.text.isEmpty)
    }

    @Test("R-02: Esc で「もしかして」を取り下げると，同じキーのあいだは示し直さない")
    func dismissSuggestion() {
        let harness = correctingHarness(margin: 2)
        #expect(harness.note?.contains("もしかして") == true)
        harness.press(.escape)
        #expect(harness.marked.text == "ようです")
        harness.settle()
        #expect(harness.note == nil)
    }

    @Test("R-07: ターミナルの行の頭では打ち間違いを見直さない")
    func noReviewAtTerminalLineStart() {
        let converter = FakeConverter()
        converter.corrections["youdesu"] = [ReadingCorrection(keys: "yoidesu", reading: "ヨイデス", score: -5, cost: 2)]
        let harness = Harness(converter: converter)
        harness.context = InputContext(profile: .terminal)
        harness.type("youdesu")
        harness.settle()
        #expect(harness.marked.text == "ようです")
    }

    @Test("R-02: 訂正を別のところで求めるときは，求め終わるまで見直さず(入力を待たせない)，受け取ったら直す")
    func providedCorrections() {
        struct NoService: TypoCorrecting {
            func corrections(forKeys keys: [String], leftContext: String?) async -> [String: [ReadingCorrection]] { [:] }
        }
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings(), typoService: NoService())
        var marked = ""
        let apply = { (actions: [ClientAction]) in for case .setMarkedText(let text) in actions { marked = text.text } }
        for key in "youdesu" { apply(session.handle(KeyEvent(.character(key)), context: InputContext()).actions) }
        apply(session.settle(context: InputContext()))
        let request = session.correctionRequest
        #expect(request?.keys.first == "youdesu")
        apply(session.review(context: InputContext()))
        #expect(marked == "ようです")
        session.provideCorrections(["youdesu": [
            ReadingCorrection(keys: "yoidesu", reading: "ヨイデス", score: -5, cost: 2),
            ReadingCorrection(keys: "youdesu", reading: "ヨウデス", score: -9, cost: 0),
        ]])
        #expect(session.correctionRequest == nil)
        apply(session.review(context: InputContext()))
        #expect(marked == "よいです")
    }

    @Test("差が中くらいなら直さずに「もしかして」と示し，Tab で直す")
    func suggestion() {
        let converter = FakeConverter()
        converter.corrections["youdesu"] = [
            ReadingCorrection(keys: "yoidesu", reading: "ヨイデス", score: -7, cost: 2),
            ReadingCorrection(keys: "youdesu", reading: "ヨウデス", score: -9, cost: 0),
        ]
        let harness = Harness(converter: converter)
        harness.type("youdesu")
        harness.settle()
        #expect(harness.marked.text == "ようです")
        #expect(harness.note?.contains("よいです") == true)
        harness.press(.tab)
        #expect(harness.marked.text == "よいです")
        harness.press(.escape)
        #expect(harness.marked.text == "ようです")
    }

    @Test("同じキーを続けて 2 回打った誤りは，1 回にした並びも見直して直す")
    func repeatedKey() {
        let converter = FakeConverter()
        converter.corrections["koonnnichiha"] = [ReadingCorrection(keys: "koonnnichiha", reading: "コオンニチハ", score: -12, cost: 0)]
        converter.corrections["konnnichiha"] = [ReadingCorrection(keys: "konnnichiha", reading: "コンニチハ", score: -4, cost: 0)]
        let harness = Harness(converter: converter)
        harness.type("koonnnichiha")
        harness.settle()
        #expect(harness.marked.text == "こんにちは")
    }

    @Test("差が小さければ直さない")
    func smallMargin() {
        let (session, _) = typed("you", corrections: [
            ReadingCorrection(keys: "yoi", reading: "ヨイ", score: -8, cost: 2),
            ReadingCorrection(keys: "you", reading: "ヨウ", score: -9, cost: 0),
        ])
        var marked = ""
        for action in session.handle(KeyEvent(.space), context: InputContext()).actions {
            if case .setMarkedText(let text) = action { marked = text.text }
        }
        #expect(marked == "よう")
    }
}

@MainActor
@Suite("ライブ変換の時機")
struct LiveConversionTimingTests {
    private func session() -> (InputSession, FakeConverter) {
        let converter = FakeConverter([
            "らい": [("雷", nil)],
            "らいぶ": [("ライブ", nil)],
            "きょうはらい": [("今日は雷", nil)],
        ])
        converter.trailingWords["雷"] = .init(readingCount: 2, textCount: 1)
        converter.trailingWords["今日は雷"] = .init(readingCount: 2, textCount: 1)
        return (InputSession(converter: converter, lexicon: FakeLexicon(), settings: FakeSettings()), converter)
    }

    private func marked(_ actions: [ClientAction]) -> String? {
        actions.compactMap { if case .setMarkedText(let text) = $0 { text.text } else { nil } }.last
    }

    @Test("打っている途中の短い語はかなのまま見せ，打鍵が止まったら変換して見せる")
    func holdsShortWord() {
        let (session, _) = session()
        var shown: String?
        for key in "kyouharai" { shown = marked(session.handle(KeyEvent(.character(key)), context: InputContext()).actions) ?? shown }
        #expect(shown == "今日はらい")
        #expect(session.awaitsSettle)
        #expect(marked(session.settle(context: InputContext())) == "今日は雷")
        #expect(!session.awaitsSettle)
    }

    @Test("読みが短いあいだは，打鍵が止まるまでかなのまま")
    func shortReading() {
        let (session, _) = session()
        var shown: String?
        for key in "rai" { shown = marked(session.handle(KeyEvent(.character(key)), context: InputContext()).actions) ?? shown }
        #expect(shown == "らい")
    }

    @Test("Enter では変換して確定する")
    func enterCommitsConversion() {
        let (session, _) = session()
        for key in "kyouharai" { _ = session.handle(KeyEvent(.character(key)), context: InputContext()) }
        let committed = session.handle(KeyEvent(.enter), context: InputContext()).actions.compactMap { if case .commit(let text) = $0 { text } else { nil } }
        #expect(committed == ["今日は雷"])
    }
}

@MainActor
@Suite("入力の設定")
struct InputSettingsScenarioTests {
    private func run(_ keys: [KeyEvent], settings: Settings, context: InputContext = InputContext()) -> (committed: String, marked: String, handled: Bool) {
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings(settings))
        var committed = "", marked = "", handled = false
        for key in keys {
            let result = session.handle(key, context: context)
            handled = result.handled
            for action in result.actions {
                if case .commit(let text) = action { committed += text }
                if case .setMarkedText(let text) = action { marked = text.text }
            }
        }
        return (committed, marked, handled)
    }

    private func keys(_ text: String) -> [KeyEvent] { text.map { KeyEvent(.character($0)) } }

    @Test("空白は既定で半角(アプリに任せる)．全角の設定なら全角，Shift+Space で逆")
    func spaceWidth() {
        var settings = Settings()
        #expect(run([KeyEvent(.space)], settings: settings).handled == false)
        #expect(run([KeyEvent(.space, modifiers: .shift)], settings: settings).committed == "\u{3000}")
        settings.spaceWidth = .fullwidth
        #expect(run([KeyEvent(.space)], settings: settings).committed == "\u{3000}")
        #expect(run([KeyEvent(.space, modifiers: .shift)], settings: settings).handled == false)
    }

    @Test("数字を全角にする設定")
    func numberWidth() {
        var settings = Settings()
        settings.numberWidth = .fullwidth
        #expect(run(keys("3"), settings: settings).marked == "３")
    }

    @Test("句読点を打ったら確定する設定")
    func punctuationCommits() {
        var settings = Settings()
        settings.punctuationCommits = true
        #expect(run(keys("ka,"), settings: settings).committed == "か、")
    }

    @Test("番号キーで候補を選ばない設定")
    func numberKeySelection() {
        var settings = Settings()
        settings.numberKeySelection = false
        settings.candidatePresentation = .list
        let session = InputSession(converter: FakeConverter(["きしゃ": [("記者", nil), ("汽車", nil)]]), lexicon: FakeLexicon(), settings: FakeSettings(settings))
        for key in keys("kisha") { _ = session.handle(key, context: InputContext()) }
        _ = session.handle(KeyEvent(.space), context: InputContext())
        let result = session.handle(KeyEvent(.character("2")), context: InputContext())
        // 番号では選ばず，選んでいた候補を確定して数字を打ち始める
        let committed = result.actions.compactMap { if case .commit(let text) = $0 { text } else { nil } }
        #expect(committed == ["記者"])
    }

    @Test("モードの表示を切る設定")
    func modeIndicator() {
        var settings = Settings()
        settings.showsModeIndicator = false
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings(settings))
        let actions = session.handle(KeyEvent(.eisu), context: InputContext()).actions
        #expect(!actions.contains(.showModeIndicator(.direct)))
    }
}

@MainActor
@Suite("入力方式")
struct InputStyleScenarioTests {
    private func session(_ style: InputStyle, converter: FakeConverter = FakeConverter()) -> InputSession {
        var settings = Settings()
        settings.inputStyle = style
        return InputSession(converter: converter, lexicon: FakeLexicon(), settings: FakeSettings(settings))
    }

    private func actions(_ session: InputSession, _ events: [KeyEvent]) -> (committed: String, marked: String, panel: CandidatePanel?, handled: Bool) {
        var committed = "", marked = "", panel: CandidatePanel?, handled = false
        for event in events {
            let result = session.handle(event, context: InputContext())
            handled = result.handled
            for action in result.actions {
                switch action {
                case .commit(let text): committed += text
                case .setMarkedText(let text): marked = text.text
                case .showCandidates(let value): panel = value
                case .hideCandidates: panel = nil
                default: break
                }
            }
        }
        return (committed, marked, panel, handled)
    }

    @Test("かな入力: キーの刻印からかなを入れ，濁点を合わせる")
    func kana() {
        // 「t」は か，「@」は 濁点，「e」は い
        let events = [KeyEvent(.character("t"), keyLabel: "t"), KeyEvent(.character("@"), keyLabel: "@"), KeyEvent(.character("e"), keyLabel: "e")]
        #expect(actions(session(.kana), events).marked == "がい")
    }

    @Test("EN 入力: 英字のまま見せ，ローマ字として読めれば日本語の候補を添え，Tab で日本語にする")
    func englishTab() {
        let converter = FakeConverter(["こんにちは": [("こんにちは", nil)]])
        let session = session(.english, converter: converter)
        let typed = actions(session, "konnnitiha".map { KeyEvent(.character($0)) })
        #expect(typed.marked == "konnnitiha")
        #expect(typed.panel?.entries.first?.text == "こんにちは")
        // Tab では確定せず分岐図を開き，Enter で確定する
        let opened = actions(session, [KeyEvent(.tab)])
        #expect(opened.committed.isEmpty)
        #expect(opened.marked == "こんにちは")
        #expect(actions(session, [KeyEvent(.enter)]).committed == "こんにちは")
    }

    @Test("EN 入力: Tab で開いた分岐図で Esc を押すと英字に戻る")
    func englishTabEscape() {
        let converter = FakeConverter(["こんにちは": [("こんにちは", nil)]])
        let session = session(.english, converter: converter)
        _ = actions(session, "konnnitiha".map { KeyEvent(.character($0)) })
        _ = actions(session, [KeyEvent(.tab)])
        #expect(actions(session, [KeyEvent(.escape)]).marked == "konnnitiha")
    }

    @Test("EN 入力: 語の途中の「-」は伸ばし棒として読み，英字のまま確定すれば「-」のまま")
    func englishLongVowel() {
        let converter = FakeConverter(["らーめん": [("ラーメン", nil)]])
        let session = session(.english, converter: converter)
        let typed = actions(session, "ra-men".map { KeyEvent(.character($0)) })
        #expect(typed.marked == "ra-men")
        #expect(typed.panel?.entries.first?.text == "ラーメン")
        #expect(actions(session, [KeyEvent(.space)]).committed == "ra-men")
    }

    @Test("EN 入力: Space は英字のまま確定してアプリに渡す")
    func englishSpace() {
        let session = session(.english)
        _ = actions(session, "hello".map { KeyEvent(.character($0)) })
        let result = actions(session, [KeyEvent(.space)])
        #expect(result.committed == "hello")
        #expect(result.handled == false)
    }

    @Test("EN 入力: ローマ字として読めない英単語には候補を出さない")
    func englishNoSuggestion() {
        #expect(actions(session(.english), "string".map { KeyEvent(.character($0)) }).panel == nil)
    }
}

@MainActor
@Suite("ターミナルでのコマンドの入力(R-07)")
struct TerminalScenarioTests {
    private let terminal = InputContext(profile: .terminal)

    private func type(_ session: InputSession, _ text: String) -> (committed: String, passed: String, marked: String) {
        var committed = "", passed = "", marked = ""
        for character in text {
            let event = character == " " ? KeyEvent(.space) : KeyEvent(.character(character))
            let result = session.handle(event, context: terminal)
            for action in result.actions {
                if case .commit(let value) = action { committed += value }
                if case .setMarkedText(let value) = action { marked = value.text }
            }
            if !result.handled { passed.append(character) }
        }
        return (committed, passed, marked)
    }

    private func makeSession() -> InputSession {
        InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings())
    }

    @Test("行の頭でコマンドの名前を打って Space を押すと英字で確定し，その行の残りは英字のまま流す")
    func command() {
        let session = makeSession()
        let result = type(session, "git status")
        #expect(result.committed == "git ")
        #expect(result.passed == "status")
    }

    @Test("英字入力: コマンドの行でも英字を組み立て，Tab で日本語にする")
    func englishTabInCommandLine() {
        var settings = Settings()
        settings.inputStyle = .english
        let session = InputSession(converter: FakeConverter(["こんにちは": [("こんにちは", nil)]]), lexicon: FakeLexicon(), settings: FakeSettings(settings))
        _ = type(session, "echo konnnitiha")
        var committed = ""
        let result = session.handle(KeyEvent(.tab), context: terminal)
        #expect(result.handled)
        let enter = session.handle(KeyEvent(.enter), context: terminal)
        for action in enter.actions { if case .commit(let value) = action { committed += value } }
        #expect(committed == "こんにちは")
    }

    @Test("英字入力: 日本語の候補が無いときの Tab は，英字を確定してターミナルに渡す(補完を妨げない)")
    func englishTabCompletion() {
        var settings = Settings()
        settings.inputStyle = .english
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings(settings))
        _ = type(session, "cd Docu")
        var committed = ""
        let result = session.handle(KeyEvent(.tab), context: terminal)
        for action in result.actions { if case .commit(let value) = action { committed += value } }
        #expect(!result.handled)
        #expect(committed == "Docu")
    }

    @Test("引用符の中は日本語を打て，閉じる引用符で確定する")
    func quoted() {
        let session = makeSession()
        let result = type(session, "git commit -m \"nihongo\"")
        #expect(result.committed == "git にほんご")
        #expect(result.passed.hasSuffix("\""))
    }

    @Test("コマンドの名前で始まらない行は，ふつうに日本語を打てる")
    func text() {
        let session = makeSession()
        let result = type(session, "kyouha")
        #expect(result.marked == "きょうは")
        #expect(result.passed.isEmpty)
    }

    @Test("Enter で行が終わると，次の行はまた行の頭から")
    func newLine() {
        let session = makeSession()
        _ = type(session, "ls ")
        _ = session.handle(KeyEvent(.enter), context: terminal)
        #expect(type(session, "aiueo").marked == "あいうえお")
    }
}

@MainActor
private final class RecordingUsage: UsageRecording {
    var events: [UsageEvent] = []
    func record(_ event: UsageEvent) { events.append(event) }
}

@MainActor
@Suite("使い方の記録")
struct UsageScenarioTests {
    @Test("ライブ変換のまま確定，候補を開いて選び直して確定，を記録する")
    func records() {
        let usage = RecordingUsage()
        let converter = FakeConverter(["あめ": [("雨", nil)]], clauses: ["あめ": [("雨", 2), ("飴", 2)]])
        let session = InputSession(converter: converter, lexicon: FakeLexicon(), settings: FakeSettings(), usage: usage)
        for key in "ame" { _ = session.handle(KeyEvent(.character(key)), context: InputContext()) }
        _ = session.handle(KeyEvent(.enter), context: InputContext())
        for key in "ame" { _ = session.handle(KeyEvent(.character(key)), context: InputContext()) }
        _ = session.handle(KeyEvent(.space), context: InputContext())
        _ = session.handle(KeyEvent(.down), context: InputContext())
        _ = session.handle(KeyEvent(.enter), context: InputContext())
        #expect(usage.events == [
            .committed(changedSegments: 0, viaConversion: false),
            .conversionOpened,
            .committed(changedSegments: 1, viaConversion: true),
        ])
    }
}

@MainActor
@Suite("Escape で英数に戻す(R-06)")
struct EscapeToDirectTests {
    @Test("設定を入れると，組み立てていないときの Escape で英数に切り替え，Escape はアプリに渡す")
    func switches() {
        var settings = Settings()
        settings.escapeSwitchesToDirect = true
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings(settings))
        let result = session.handle(KeyEvent(.escape), context: InputContext())
        #expect(result.handled == false)
        #expect(result.actions.contains(.selectMode(.direct)))
        #expect(session.mode == .direct)
    }

    @Test("既定では Escape で英数に切り替えない")
    func defaultOff() {
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings())
        _ = session.handle(KeyEvent(.escape), context: InputContext())
        #expect(session.mode == .japanese)
    }
}

@MainActor
@Suite("入力方式の切り替え")
struct InputStyleSwitchTests {
    @Test("Option+かな で入力方式を順に切り替える")
    func cycles() {
        var settings = Settings()
        settings.inputStyle = .english
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings(settings))
        let actions = session.handle(KeyEvent(.kana, modifiers: .option), context: InputContext()).actions
        #expect(actions.contains(.selectInputStyle(.romaji)))
    }
}

@MainActor
@Suite("レビューで見つけた不具合の再発防止")
struct ReviewRegressionTests {
    private func session(_ settings: Settings = Settings(), converter: FakeConverter = FakeConverter()) -> (InputSession, FakeSettings) {
        let store = FakeSettings(settings)
        return (InputSession(converter: converter, lexicon: FakeLexicon(), settings: store), store)
    }

    private func marked(_ actions: [ClientAction]) -> String? {
        actions.compactMap { if case .setMarkedText(let text) = $0 { text.text } else { nil } }.last
    }

    private func committed(_ actions: [ClientAction]) -> String {
        actions.compactMap { if case .commit(let text) = $0 { text } else { nil } }.joined()
    }

    private func english() -> Settings {
        var settings = Settings()
        settings.inputStyle = .english
        return settings
    }

    @Test("EN 入力では打鍵が止まっても英字を消さない")
    func englishSettle() {
        let (session, _) = session(english())
        for key in "hello" { _ = session.handle(KeyEvent(.character(key)), context: InputContext()) }
        #expect(!session.awaitsSettle)
        #expect(session.settle(context: InputContext()).isEmpty)
        #expect(committed(session.handle(KeyEvent(.enter), context: InputContext()).actions) == "hello")
    }

    @Test("EN 入力の Escape: 英数にする設定なら，打っている途中でも 1 回で英字を確定して英数にし，Escape もアプリに渡す")
    func englishEscape() {
        var settings = english()
        settings.escapeSwitchesToDirect = true
        let (session, _) = session(settings)
        for key in "vim" { _ = session.handle(KeyEvent(.character(key)), context: InputContext()) }
        let first = session.handle(KeyEvent(.escape), context: InputContext())
        #expect(committed(first.actions) == "vim")
        #expect(first.handled == false)
        #expect(session.mode == .direct)
    }

    @Test("EN 入力の Escape: 設定が無ければ英字を確定して Escape をアプリに渡し，日本語のまま")
    func englishEscapeWithoutSetting() {
        let (session, _) = session(english())
        for key in "vim" { _ = session.handle(KeyEvent(.character(key)), context: InputContext()) }
        let result = session.handle(KeyEvent(.escape), context: InputContext())
        #expect(committed(result.actions) == "vim")
        #expect(result.handled == false)
        #expect(session.mode == .japanese)
    }

    @Test("ターミナルで読みを組み立てている途中の Ctrl+C は行を終えない(シェルに届かないため)")
    func terminalControlCWhileComposing() {
        let (session, _) = session()
        let terminal = InputContext(profile: .terminal)
        for key in "git" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
        _ = session.handle(KeyEvent(.space), context: terminal)
        for key in "commit -m \"" { _ = session.handle(key == " " ? KeyEvent(.space) : KeyEvent(.character(key)), context: terminal) }
        for key in "aiu" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
        _ = session.handle(KeyEvent(.character("c"), modifiers: .control), context: terminal)
        _ = session.handle(KeyEvent(.escape), context: terminal)
        _ = session.handle(KeyEvent(.escape), context: terminal)
        // まだ引用符の中なので，閉じる引用符はアプリに渡り，コマンドの行に戻る
        #expect(session.handle(KeyEvent(.character("\"")), context: terminal).handled == false)
        #expect(session.handle(KeyEvent(.character("x")), context: terminal).handled == false)
    }

    @Test("ターミナルで組み立てずに流した空白と記号も行の長さに数える")
    func terminalCountsPassedKeys() {
        let (session, _) = session()
        let terminal = InputContext(profile: .terminal)
        for key in "aiu" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
        _ = session.handle(KeyEvent(.enter), context: terminal)
        _ = session.handle(KeyEvent(.space), context: terminal)
        for key in "eo" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
        _ = session.handle(KeyEvent(.enter), context: terminal)
        // 画面の上は「あいう えお」の 6 文字．5 回消してもまだ行の途中なので，ls はコマンドにならない
        for _ in 0..<5 { _ = session.handle(KeyEvent(.backspace), context: terminal) }
        for key in "ls" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
        #expect(committed(session.handle(KeyEvent(.space), context: terminal).actions) != "ls ")
    }

    @Test("EN 入力の Enter で行が終わり，次の行の頭のコマンドを見分ける")
    func terminalEnglishEnter() {
        let (session, _) = session(english())
        let terminal = InputContext(profile: .terminal)
        for key in "hello" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
        // 英字を確定して Enter をアプリに渡す
        #expect(session.handle(KeyEvent(.enter), context: terminal).handled == false)
    }

    @Test("かな入力: 選べる数を超える番号キーはかなにする")
    func kanaNumberOutOfRange() {
        var settings = Settings()
        settings.inputStyle = .kana
        settings.candidatePresentation = .list
        let (session, _) = session(settings, converter: FakeConverter(["た": [("田", nil), ("た", nil)]]))
        _ = session.handle(KeyEvent(.character("q"), keyLabel: "q"), context: InputContext())
        _ = session.handle(KeyEvent(.space), context: InputContext())
        let result = session.handle(KeyEvent(.character("9"), keyLabel: "9"), context: InputContext())
        #expect(committed(result.actions) == "田")
        #expect(marked(result.actions) == "よ")
    }

    @Test("EN 入力の途中で Control の組み合わせを押すと，英字を確定してからアプリに渡す")
    func englishControl() {
        let (session, _) = session(english())
        for key in "abc" { _ = session.handle(KeyEvent(.character(key)), context: InputContext()) }
        let result = session.handle(KeyEvent(.character("a"), modifiers: .control), context: InputContext())
        #expect(committed(result.actions) == "abc")
        #expect(result.handled == false)
    }

    @Test("組み立てている途中に入力方式が変わったら，前の方式の文字を確定する")
    func styleChangedWhileComposing() {
        let (session, store) = session()
        for key in "ka" { _ = session.handle(KeyEvent(.character(key)), context: InputContext()) }
        store.current.inputStyle = .english
        // 次のキー(ここでは Backspace)は確定だけに使い，確定した文字に効かせない
        let result = session.handle(KeyEvent(.backspace), context: InputContext())
        #expect(committed(result.actions) == "か")
        #expect(result.handled)
        #expect(marked(session.handle(KeyEvent(.character("x")), context: InputContext()).actions) == "x")
    }

    @Test("ターミナルの Ctrl+C で行が終わり，次の行は日本語を打てる")
    func terminalControlC() {
        let (session, _) = session()
        let terminal = InputContext(profile: .terminal)
        for key in "git" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
        _ = session.handle(KeyEvent(.space), context: terminal)
        _ = session.handle(KeyEvent(.character("c"), modifiers: .control), context: terminal)
        var shown: String?
        for key in "aiu" { shown = marked(session.handle(KeyEvent(.character(key)), context: terminal).actions) ?? shown }
        #expect(shown == "あいう")
    }

    @Test("ターミナルで英数に切り替えたり履歴を呼んだりすると，行が終わる")
    func terminalLineEnds() {
        let terminal = InputContext(profile: .terminal)
        for reset in [KeyEvent(.eisu), KeyEvent(.up)] {
            let (session, _) = session()
            for key in "ls" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
            _ = session.handle(KeyEvent(.space), context: terminal)
            _ = session.handle(reset, context: terminal)
            if reset.key == .eisu { _ = session.handle(KeyEvent(.kana), context: terminal) }
            var shown: String?
            for key in "ka" { shown = marked(session.handle(KeyEvent(.character(key)), context: terminal).actions) ?? shown }
            #expect(shown == "か", "\(reset.key)")
        }
    }

    @Test("かな入力: Shift のかな，¥ キーの長音，一覧での番号キー")
    func kanaKeys() {
        var settings = Settings()
        settings.inputStyle = .kana
        settings.candidatePresentation = .list
        let (session, _) = session(settings, converter: FakeConverter(["ぁー": [("ァー", nil), ("ぁー", nil)]]))
        _ = session.handle(KeyEvent(.character("#"), modifiers: .shift, keyLabel: "3"), context: InputContext())
        let shown = marked(session.handle(KeyEvent(.yen), context: InputContext()).actions)
        #expect(shown == "ぁー")
        _ = session.handle(KeyEvent(.space), context: InputContext())
        let result = session.handle(KeyEvent(.character("2"), keyLabel: "2"), context: InputContext())
        #expect(committed(result.actions) == "ぁー")
    }

    @Test("分岐図で触って元に戻した文節は，選び直しに数えない")
    func usageRevert() {
        final class Recorder: UsageRecording {
            var events: [UsageEvent] = []
            func record(_ event: UsageEvent) { events.append(event) }
        }
        let recorder = Recorder()
        let converter = FakeConverter(["あめ": [("雨", nil)]], clauses: ["あめ": [("雨", 2), ("飴", 2)]])
        let session = InputSession(converter: converter, lexicon: FakeLexicon(), settings: FakeSettings(), usage: recorder)
        for key in "ame" { _ = session.handle(KeyEvent(.character(key)), context: InputContext()) }
        _ = session.handle(KeyEvent(.space), context: InputContext())
        _ = session.handle(KeyEvent(.down), context: InputContext())
        _ = session.handle(KeyEvent(.up), context: InputContext())
        _ = session.handle(KeyEvent(.enter), context: InputContext())
        #expect(recorder.events.last == .committed(changedSegments: 0, viaConversion: true))
    }
}

@MainActor
@Suite("F6〜F10 と利用者のローマ字")
struct FunctionKeyAndRomajiTests {
    private func marked(_ actions: [ClientAction]) -> String? {
        actions.compactMap { if case .setMarkedText(let text) = $0 { text.text } else { nil } }.last
    }

    @Test("F7 でカタカナ，F8 で半角カタカナ，F10 で半角英数にする")
    func functionKeys() {
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings())
        for key in "tokyo" { _ = session.handle(KeyEvent(.character(key)), context: InputContext()) }
        #expect(marked(session.handle(KeyEvent(.function(7)), context: InputContext()).actions) == "トキョ")
        #expect(marked(session.handle(KeyEvent(.function(8)), context: InputContext()).actions) == "ﾄｷｮ")
        #expect(marked(session.handle(KeyEvent(.function(10)), context: InputContext()).actions) == "tokyo")
    }

    @Test("組み立てていないときの F キーはアプリに渡す")
    func passThrough() {
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings())
        #expect(session.handle(KeyEvent(.function(7)), context: InputContext()).handled == false)
    }

    @Test("利用者が足した綴りで読みを組み立てる")
    func customRomaji() {
        var settings = Settings()
        settings.customRomaji = [RomajiRule(keys: "wyi", kana: "ゐ"), RomajiRule(keys: "INVALID", kana: "x")]
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings(settings))
        var shown: String?
        for key in "wyika" { shown = marked(session.handle(KeyEvent(.character(key)), context: InputContext()).actions) ?? shown }
        #expect(shown == "ゐか")
    }
}

@MainActor
@Suite("3 回目のレビューで見つけた不具合の再発防止")
struct ThirdReviewRegressionTests {
    private func committed(_ actions: [ClientAction]) -> String {
        actions.compactMap { if case .commit(let text) = $0 { text } else { nil } }.joined()
    }

    private func marked(_ actions: [ClientAction]) -> String? {
        actions.compactMap { if case .setMarkedText(let text) = $0 { text.text } else { nil } }.last
    }

    @Test("かな入力: 組み立てていないとき・組み立て中の数字の段のキーはかなにする(落ちない)")
    func kanaNumberRow() {
        var settings = Settings()
        settings.inputStyle = .kana
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings(settings))
        _ = session.handle(KeyEvent(.character("1"), keyLabel: "1"), context: InputContext())
        let result = session.handle(KeyEvent(.character("3"), keyLabel: "3"), context: InputContext())
        #expect(marked(result.actions) == "ぬあ")
    }

    @Test("入力方式を変えた直後の文字のキーは，前の方式の文字を確定してから新しい方式で打つ")
    func characterAfterStyleChange() {
        let store = FakeSettings()
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: store)
        for key in "ka" { _ = session.handle(KeyEvent(.character(key)), context: InputContext()) }
        store.current.inputStyle = .english
        let result = session.handle(KeyEvent(.character("x")), context: InputContext())
        #expect(committed(result.actions) == "か")
        #expect(marked(result.actions) == "x")
    }

    @Test("ターミナル: EN 入力で確定した英字も行の長さに数え，行の途中のコマンドの名前をコマンドにしない")
    func englishCommitCounted() {
        let store = FakeSettings()
        store.current.inputStyle = .english
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: store)
        let terminal = InputContext(profile: .terminal)
        for key in "hello" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
        _ = session.handle(KeyEvent(.space), context: terminal)
        store.current.inputStyle = .romaji
        for key in "ls" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
        #expect(committed(session.handle(KeyEvent(.space), context: terminal).actions) != "ls ")
    }

    @Test("ターミナル: EN 入力の Enter で行が終わり，次の行の頭の ls はコマンドになる")
    func englishEnterEndsLine() {
        let store = FakeSettings()
        store.current.inputStyle = .english
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: store)
        let terminal = InputContext(profile: .terminal)
        for key in "hello" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
        _ = session.handle(KeyEvent(.enter), context: terminal)
        store.current.inputStyle = .romaji
        for key in "ls" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
        #expect(committed(session.handle(KeyEvent(.space), context: terminal).actions) == "ls ")
    }

    @Test("ログに出す表示は入力した文字を含めない")
    func redacted() {
        let actions: [ClientAction] = [.commit("秘密"), .setMarkedText(MarkedText([.init("秘密", style: .reading)]))]
        #expect(!String(describing: actions).contains("秘密"))
        #expect(!String(reflecting: KeyResult(handled: true, actions: actions)).contains("秘密"))
    }
}

@MainActor
@Suite("4 回目のレビューで見つけた不具合の再発防止")
struct FourthReviewRegressionTests {
    private let terminal = InputContext(profile: .terminal)

    private func committed(_ actions: [ClientAction]) -> String {
        actions.compactMap { if case .commit(let text) = $0 { text } else { nil } }.joined()
    }

    private func isCommandAfter(_ interrupt: (InputSession) -> Void) -> Bool {
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings())
        for key in "ka" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
        interrupt(session)
        for key in "ls" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
        return committed(session.handle(KeyEvent(.space), context: terminal).actions) == "ls "
    }

    @Test("ターミナル: Command・Option のキーや入力欄の切り替えで確定した読みも行に数える")
    func commitsOutsideNormalPath() {
        #expect(!isCommandAfter { _ = $0.handle(KeyEvent(.character("v"), modifiers: .command), context: terminal) })
        #expect(!isCommandAfter { _ = $0.handle(KeyEvent(.character("å"), modifiers: .option), context: terminal) })
        #expect(!isCommandAfter { _ = $0.deactivate() })
    }

    @Test("入力方式を変えた直後の ¥ キーは確定してから入れ，英数キーは英数にする")
    func yenAndEisuAfterStyleChange() {
        let store = FakeSettings()
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: store)
        for key in "ka" { _ = session.handle(KeyEvent(.character(key)), context: InputContext()) }
        store.current.inputStyle = .english
        let yen = session.handle(KeyEvent(.yen), context: InputContext())
        #expect(committed(yen.actions) == "か\\")
        for key in "ka" { _ = session.handle(KeyEvent(.character(key)), context: InputContext()) }
        store.current.inputStyle = .romaji
        _ = session.handle(KeyEvent(.eisu), context: InputContext())
        #expect(session.mode == .direct)
    }

    @Test("ログに出す表示は，入力位置の前の文字列や文節の中身を含めない")
    func redacted() {
        #expect(!String(describing: InputContext(precedingText: "秘密")).contains("秘密"))
        #expect(!String(describing: MarkedText.Segment("秘密", style: .reading)).contains("秘密"))
        #expect(!String(describing: CandidatePanel.Entry(text: "秘密", annotation: nil)).contains("秘密"))
        #expect(!String(describing: LatticePanel.Column(text: "秘密", isFocused: false, isUncertain: false)).contains("秘密"))
        let segment = SegmentLattice.Segment(readingStart: 0, readingLength: 2, candidates: [Candidate(text: "秘密", readingCount: 2, origin: .combined)], isConfident: true)
        #expect(!String(describing: segment).contains("秘密"))
        #expect(!String(describing: ReadingCorrection(keys: "himitsu", reading: "ヒミツ", score: 0, cost: 0)).contains("ヒミツ"))
        // debugDescription(String(reflecting:))でも中身を出さない
        var composition = Composition()
        for key in "himitsu" { composition.insertRomaji(key) }
        let values: [Any] = [
            InputContext(precedingText: "秘密"), MarkedText.Segment("秘密", style: .reading), segment,
            ReadingCorrection(keys: "himitsu", reading: "ヒミツ", score: 0, cost: 0), RomajiRule(keys: "hm", kana: "秘密"),
        ] + composition.tails()
        for value in values {
            let shown = String(reflecting: value)
            #expect(!shown.contains("秘密") && !shown.contains("ヒミツ") && !shown.contains("himitsu"), "\(type(of: value))")
        }
    }

    @Test("入力欄を離れる処理を 2 回呼んでも，確定した読みのある行はコマンドの行にしない")
    func deactivateTwice() {
        #expect(!isCommandAfter { session in
            _ = session.deactivate()
            _ = session.deactivate()
        })
    }

    @Test("ターミナル: Cmd+Backspace で行を消したら行の頭に戻り，Cmd+V で貼り付けたら文の行にする")
    func commandBackspaceAndPaste() {
        let afterClear = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings())
        for key in "ls" { _ = afterClear.handle(KeyEvent(.character(key)), context: terminal) }
        _ = afterClear.handle(KeyEvent(.space), context: terminal)
        _ = afterClear.handle(KeyEvent(.backspace, modifiers: .command), context: terminal)
        #expect(afterClear.handle(KeyEvent(.character("a")), context: terminal).handled)
        let afterPaste = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings())
        _ = afterPaste.handle(KeyEvent(.character("v"), modifiers: .command), context: terminal)
        for key in "ls" { _ = afterPaste.handle(KeyEvent(.character(key)), context: terminal) }
        #expect(committed(afterPaste.handle(KeyEvent(.space), context: terminal).actions) != "ls ")
    }

    @Test("ターミナル: Command 付きのキーは行に数えない(Cmd+K のあとも行の長さが変わらない)")
    func commandKeyNotCounted() {
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings())
        for key in "ls" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
        _ = session.handle(KeyEvent(.space), context: terminal)
        _ = session.handle(KeyEvent(.character("k"), modifiers: .command), context: terminal)
        _ = session.handle(KeyEvent(.character("\""), modifiers: [.command, .shift]), context: terminal)
        for _ in 0..<3 { _ = session.handle(KeyEvent(.backspace), context: terminal) }
        // 行は空なので行の頭に戻り，次の a は組み立てる
        #expect(session.handle(KeyEvent(.character("a")), context: terminal).handled)
    }
}

@MainActor
@Suite("ターミナルの行が分からなくなるとき")
struct TerminalUnknownLineTests {
    private let terminal = InputContext(profile: .terminal)

    private func commandSession() -> InputSession {
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings())
        for key in "ls" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
        _ = session.handle(KeyEvent(.space), context: terminal)
        return session
    }

    private func passes(_ session: InputSession) -> Bool {
        !session.handle(KeyEvent(.character("a")), context: terminal).handled
    }

    @Test("コマンドの行で Option+文字を押すと，英字を流さない文の行になる")
    func optionInCommandLine() {
        let session = commandSession()
        _ = session.handle(KeyEvent(.character("ƒ"), modifiers: .option), context: terminal)
        #expect(!passes(session))
    }

    @Test("コマンドの行で入力欄を離れると，英字を流さない文の行になる")
    func leaveCommandLine() {
        let session = commandSession()
        _ = session.deactivate()
        #expect(!passes(session))
    }

    @Test("何も打っていない行で入力欄を 2 回離れても，ls と Space でコマンドの行に入れる")
    func leaveEmptyLineTwice() {
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings())
        _ = session.deactivate()
        _ = session.deactivate()
        for key in "ls" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
        let actions = session.handle(KeyEvent(.space), context: terminal).actions
        #expect(actions.contains(.commit("ls ")))
    }

    @Test("コマンドの行で Cmd+V を押しても，英字を流し続ける")
    func pasteInCommandLine() {
        let session = commandSession()
        _ = session.handle(KeyEvent(.character("v"), modifiers: .command), context: terminal)
        #expect(passes(session))
    }

    @Test("ログに出す表示は，入力した文字を持つほかの型でも中身を含めない")
    func redactedMore() {
        var composition = Composition()
        for key in "himitsu" { composition.insertRomaji(key) }
        var settings = Settings()
        settings.userDictionary = [UserDictionaryEntry(reading: "ひみつ", word: "秘密")]
        let candidate = Candidate(text: "秘密", readingCount: 3, origin: .combined)
        let values: [Any] = [
            ClientAction.commit("秘密"),
            CandidatePanel(variants: [], selectedVariant: nil, entries: [.init(text: "秘密", annotation: nil)], selectedEntry: nil,
                           focus: .candidate, position: 1, total: 1, note: nil),
            LatticePanel(columns: [.init(text: "秘密", isFocused: true, isUncertain: false)]),
            candidate, KeyEvent(.character("h")), settings, UserDictionaryEntry(reading: "ひみつ", word: "秘密"),
            RomajiTable.standard(adding: [RomajiRule(keys: "hm", kana: "秘密")]),
        ]
        for value in values {
            let shown = String(reflecting: value)
            #expect(!shown.contains("秘密") && !shown.contains("ひみつ"), "\(type(of: value))")
        }
    }

    @Test("メニューで英数にすると行が終わり，日本語に戻すと行の頭からコマンドを見分ける")
    func setModeEndsLine() {
        let session = commandSession()
        _ = session.setMode(.direct)
        _ = session.setMode(.japanese)
        for key in "git" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
        #expect(session.handle(KeyEvent(.space), context: terminal).actions.contains(.commit("git ")))
    }

    @Test("英数で行の頭から打ってから日本語に戻すと，文の行のまま")
    func directTypingThenJapanese() {
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings())
        _ = session.setMode(.direct)
        for key in "ls" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
        _ = session.setMode(.japanese)
        for key in "git" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
        #expect(!session.handle(KeyEvent(.space), context: terminal).actions.contains(.commit("git ")))
    }

    @Test("行の頭の空白や「(」「\\」(¥ キーを含む)のあとのコマンドの名前は，コマンドとして見分ける")
    func commandAfterLeadingSymbols() {
        for prefix in [KeyEvent(.space), KeyEvent(.character("(")), KeyEvent(.character("\\")), KeyEvent(.yen)] {
            let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings())
            _ = session.handle(prefix, context: terminal)
            for key in "git" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
            #expect(session.handle(KeyEvent(.space), context: terminal).actions.contains(.commit("git ")), "\(prefix.key)")
        }
    }

    @Test("行の頭の @・*・引用符・` のあとは，コマンドの名前でも日本語の文として打てる(「@claude これ見て」「`git rebase` のやり方」)")
    func textAfterAtSign() {
        for prefix in ["@", "*", "\"", "'", "`"] as [Character] {
            let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings())
            _ = session.handle(KeyEvent(.character(prefix)), context: terminal)
            for key in "claude" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
            #expect(!session.handle(KeyEvent(.space), context: terminal).actions.contains(.commit("claude ")), "\(prefix)")
        }
    }

    @Test("何も入れていない行の頭の Tab と Shift+Tab のあとも，コマンドの名前を見分ける")
    func tabAtEmptyLineStart() {
        for tab in [KeyEvent(.tab), KeyEvent(.tab, modifiers: .shift)] {
            let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings())
            _ = session.handle(tab, context: terminal)
            for key in "git" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
            #expect(session.handle(KeyEvent(.space), context: terminal).actions.contains(.commit("git ")), "\(tab.modifiers)")
        }
    }

    @Test("行の頭の記号のあとで Tab の補完をしたら，何が入ったか分からないのでコマンドの名前を見分けない")
    func tabCompletionAfterPrefix() {
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings())
        _ = session.handle(KeyEvent(.character("(")), context: terminal)
        _ = session.handle(KeyEvent(.tab), context: terminal)
        for key in "ls" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
        #expect(!session.handle(KeyEvent(.space), context: terminal).actions.contains(.commit("ls ")))
    }

    @Test("行の頭の記号のあとの Shift+Tab は補完ではないので，続くコマンドの名前を見分ける")
    func shiftTabAfterPrefix() {
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings())
        _ = session.handle(KeyEvent(.character("(")), context: terminal)
        _ = session.handle(KeyEvent(.tab, modifiers: .shift), context: terminal)
        for key in "git" { _ = session.handle(KeyEvent(.character(key)), context: terminal) }
        #expect(session.handle(KeyEvent(.space), context: terminal).actions.contains(.commit("git ")))
    }
}
