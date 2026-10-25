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
            case .hideCandidates: panel = nil
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
}
