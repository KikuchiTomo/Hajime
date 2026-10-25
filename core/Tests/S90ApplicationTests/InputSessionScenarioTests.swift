import S90Application
import S90Domain
import S90TestSupport
import Testing

/// キーの列を流し込み，画面への操作を確かめる．要件(R-xx)の受け入れ条件はここで確かめる
@MainActor
private final class Harness {
    let converter: FakeConverter
    let lexicon: FakeLexicon
    let settings: FakeSettings
    let session: InputSession
    var context = InputContext()
    private(set) var committed = ""
    private(set) var marked = MarkedText.empty
    private(set) var panel: CandidatePanel?
    private(set) var lattice: LatticePanel?
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

    func press(_ key: KeyEvent.Key, _ modifiers: KeyEvent.Modifiers = []) {
        lastResult = session.handle(KeyEvent(key, modifiers: modifiers), context: context)
        for action in lastResult.actions {
            switch action {
            case .commit(let text): committed += text
            case .setMarkedText(let text): marked = text
            case .showCandidates(let value): panel = value
            case .showLattice(let value): lattice = value
            case .hideCandidates:
                panel = nil
                lattice = nil
            case .showModeIndicator, .selectMode: break
            }
        }
    }
}

@Suite("入力の流れ")
@MainActor
struct InputSessionScenarioTests {
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
        let harness = Harness(converter: FakeConverter(["きしゃ": [("記者", nil), ("汽車", nil), ("帰社", nil)]]))
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
        let harness = Harness(converter: converter)
        harness.type("kyouhaame")
        harness.press(.space)
        harness.press(.enter)
        #expect(harness.committed == "今日は雨")
        #expect(converter.committed.count == 2)
    }

    @Test("R-03: 候補の先頭で上キーを押すと種類の行に移り，左右で選ぶ")
    func variantRow() {
        let harness = Harness(converter: FakeConverter(["とうきょう": [("東京", nil)]]))
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

    @Test("R-02: 補正したときは，候補一覧の 2 番目に打ったままの文字列を出す")
    func correctionCandidates() {
        let harness = Harness(lexicon: FakeLexicon(words: ["python"]))
        harness.type("python")
        harness.press(.down)
        #expect(harness.panel?.entries.prefix(2).map(\.text) == ["python", "pyてょn"])
        #expect(harness.panel?.entries[1].annotation == "入力のまま")
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

    // MARK: - 文節格子

    private func latticeConverter() -> FakeConverter {
        FakeConverter(
            ["きょうはあめ": [("今日は雨", nil)], "あめ": [("雨", nil)], "きょう": [("今日", nil)], "はあめ": [("は雨", nil)]],
            clauses: [
                "きょうはあめ": [("今日は", 4), ("京は", 4)],
                "あめ": [("雨", 2), ("飴", 2)],
                "はあめ": [("は雨", 3)],
            ]
        )
    }

    @Test("文節が 2 つ以上あれば，Space で文節格子を出す")
    func latticeAppears() {
        let harness = Harness(converter: latticeConverter())
        harness.type("kyouhaame")
        harness.press(.space)
        #expect(harness.panel == nil)
        #expect(harness.lattice?.columns.map(\.text) == ["今日は", "雨"])
        #expect(harness.lattice?.columns.first?.isFocused == true)
        #expect(harness.marked.segments.map(\.style) == [.focused, .converted])
    }

    @Test("文節格子: →で文節を移り，↓で候補を変え，Enter で全体を確定する")
    func latticeNavigation() {
        let converter = latticeConverter()
        let harness = Harness(converter: converter)
        harness.type("kyouhaame")
        harness.press(.space)
        harness.press(.right)
        harness.press(.down)
        #expect(harness.marked.text == "今日は飴")
        harness.press(.enter)
        #expect(harness.committed == "今日は飴")
        #expect(converter.committed.count == 2)
    }

    @Test("文節格子: 番号で選ぶと次の文節に進み，最後の文節で確定する")
    func latticeNumbers() {
        let harness = Harness(converter: latticeConverter())
        harness.type("kyouhaame")
        harness.press(.space)
        harness.type("2")
        #expect(harness.lattice?.columns[1].isFocused == true)
        harness.type("1")
        #expect(harness.committed == "京は雨")
    }

    @Test("文節格子: Shift+← で文節を縮め，後ろを分け直す")
    func latticeResize() {
        let harness = Harness(converter: latticeConverter())
        harness.type("kyouhaame")
        harness.press(.space)
        harness.press(.left, .shift)
        #expect(harness.lattice?.columns.map(\.text) == ["今日", "は雨"])
    }

    @Test("確信度の高い文節は，注目していなければ候補の列を畳む")
    func latticeConfidence() {
        let harness = Harness(converter: latticeConverter())
        harness.type("kyouhaame")
        harness.press(.space)
        // 「あめ」は雨と飴の点数の差が十分あるので畳む(Fake の点数は 1 つ下がるごとに 3)
        #expect(harness.lattice?.columns[1].showsAlternatives == false)
        #expect(harness.lattice?.columns[0].showsAlternatives == true)
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
