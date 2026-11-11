import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

/// 変換中の操作(R-17)．文節だけの字種，直前の変更の取り消し，読みに戻す・読みに戻して打ち続ける，ページ送り・先頭と末尾の文節，ATOK 風のひな形
@MainActor
@Suite("変換中の取り消しと文節の操作(R-17)")
struct ConversionEditScenarioTests {
    /// 「きょうはいい」を「今日は」「いい」の 2 つの文節に分ける変換器
    private func twoSegments() -> FakeConverter {
        let converter = FakeConverter([
            "きょうはいい": [("今日はいい", nil)], "きょうは": [("今日は", nil), ("京は", nil)], "いい": [("良い", nil), ("いい", nil)],
            "かな": [("仮名", nil)],
        ], clauses: ["きょうはいい": [("今日は", 4), ("京は", 4)], "いい": [("良い", 2), ("いい", 2)]])
        converter.words["きょうはいい"] = [
            Candidate.Word(text: "今日", readingCount: 3), Candidate.Word(text: "はいい", readingCount: 3, startsWithParticle: true),
        ]
        return converter
    }

    /// 最初に先頭の文節を選ぶ設定(どの文節を選ぶかをテストで決めるため)
    private func settings(_ preset: KeymapPreset = .standard) -> Settings {
        var settings = DefaultSettings.settings
        settings.keymap = preset.keymap
        settings.initialFocus = .start
        return settings
    }

    /// 「きょうはいい」を変換したところ(先頭の文節を選んでいる)
    private func converted(_ preset: KeymapPreset = .standard) -> Harness {
        let harness = Harness(converter: twoSegments(), settings: settings(preset))
        harness.type("kyouhaii")
        harness.press(.space)
        return harness
    }

    private func focus(_ harness: Harness) -> Int? {
        harness.lattice?.columns.firstIndex(where: \.isFocused)
    }

    // MARK: 文節だけの字種

    @Test("R-17: 変換中の F7 は選んでいる文節だけをカタカナにし，ほかの文節の候補は変えない．入力中の F7 は全文をカタカナにする")
    func segmentKatakana() {
        let harness = converted()
        let columns = harness.lattice?.columns.map(\.text) ?? []
        #expect(columns.count == 2)
        harness.press(.right)
        harness.press(.function(7))
        #expect(harness.lattice?.columns.map(\.text) == [columns[0], "イイ"])
        #expect(focus(harness) == 1)
        harness.press(.function(6))
        #expect(harness.lattice?.columns.map(\.text) == [columns[0], "いい"])
        harness.press(.enter)
        #expect(harness.committed == columns[0] + "いい")

        let composing = Harness(converter: twoSegments(), settings: settings())
        composing.type("kyouhaii")
        composing.press(.function(7))
        #expect(composing.marked.text == "キョウハイイ")
    }

    @Test("R-17: 文全体の一覧では，文節だけの字種のキーも全文を変える")
    func segmentKatakanaInList() {
        var list = settings()
        list.candidatePresentation = .list
        let harness = Harness(converter: twoSegments(), settings: list)
        harness.type("kana")
        harness.press(.space)
        #expect(harness.panel != nil)
        harness.press(.function(7))
        #expect(harness.marked.text == "カナ")
    }

    // MARK: 直前の変更の取り消し

    @Test("R-17: Esc で直前の候補の選択を取り消し，続けて押すと全文を読みに戻し，さらに押すと読みを消す")
    func undoCandidateThenReading() {
        let harness = converted()
        let original = harness.marked.text
        harness.press(.space)
        #expect(harness.marked.text != original)
        harness.press(.escape)
        #expect(harness.marked.text == original)
        #expect(harness.lattice != nil)
        harness.press(.escape)
        #expect(harness.lattice == nil)
        #expect(harness.marked.text == "きょうはいい")
        harness.press(.escape)
        #expect(harness.marked.isEmpty)
        #expect(harness.committed.isEmpty)
    }

    @Test("R-17: 同じ文節で続けて候補を送ったときは 1 回の Esc で送る前に戻す．文節を移るとまとまりは切れる")
    func undoMergesCandidateRun() {
        let harness = converted()
        let original = harness.lattice?.columns.map(\.text) ?? []
        harness.press(.right)
        harness.press(.space)
        harness.press(.space)
        harness.press(.space)
        let changedSecond = harness.lattice?.columns.map(\.text) ?? []
        harness.press(.left)
        harness.press(.space)
        #expect(harness.lattice?.columns.map(\.text) != changedSecond)
        harness.press(.escape)
        #expect(harness.lattice?.columns.map(\.text) == changedSecond)
        // 取り消すと，変える前に選んでいた文節に戻る
        #expect(focus(harness) == 0)
        harness.press(.escape)
        #expect(harness.lattice?.columns.map(\.text) == original)
        #expect(focus(harness) == 1)
    }

    @Test("R-17: Esc で文節の区切りの変更を取り消す")
    func undoResize() {
        let harness = converted()
        let original = harness.lattice?.columns.map(\.text) ?? []
        harness.press(.left, .shift)
        harness.press(.left, .shift)
        #expect(harness.lattice?.columns.map(\.text) != original)
        harness.press(.escape)
        #expect(harness.lattice?.columns.map(\.text) == original)
        harness.press(.function(7))
        harness.press(.function(7))
        harness.press(.escape)
        #expect(harness.lattice?.columns.map(\.text) == original)
    }

    @Test("R-17: 全文を全角英数にした変換も Esc で分岐図に戻す")
    func undoWholeVariant() {
        let harness = converted()
        let original = harness.lattice?.columns.map(\.text) ?? []
        harness.press(.function(9))
        #expect(harness.marked.text == "ｋｙｏｕｈａｉｉ")
        harness.press(.escape)
        #expect(harness.marked.text == original.joined())
        #expect(harness.lattice?.columns.map(\.text) == original)
    }

    @Test("R-17: 取り消せるのは決めた段の数まで．それより前の変更は戻さずに読みに戻す")
    func undoDepth() {
        let harness = converted()
        // 文節を移りながら候補を変え，段の数より 2 つ多く変更する
        for step in 0..<(DefaultSettings.conversionUndoDepth + 2) {
            harness.press(step.isMultiple(of: 2) ? .right : .left)
            harness.press(.space)
        }
        for _ in 0..<DefaultSettings.conversionUndoDepth {
            harness.press(.escape)
            #expect(harness.lattice != nil)
        }
        harness.press(.escape)
        #expect(harness.lattice == nil)
        #expect(harness.marked.text == "きょうはいい")
    }

    @Test("R-17: 候補を送って戻したときは，取り消す段を残さない")
    func undoSkipsReturnedRun() {
        let harness = converted()
        harness.press(.down)
        harness.press(.up)
        harness.press(.escape)
        #expect(harness.lattice == nil)
        #expect(harness.marked.text == "きょうはいい")
    }

    // MARK: 読みに戻す

    @Test("R-17: Backspace で全文を読みに戻すと，ライブ変換がオンでも読みのまま見せ，Enter で読みのまま確定する")
    func backToReadingHoldsReading() {
        let harness = Harness(converter: twoSegments(), settings: settings())
        harness.settings.current.liveConversionSkipLength = 0
        harness.type("kana")
        harness.settle()
        #expect(harness.marked.text == "仮名")
        harness.press(.space)
        harness.press(.backspace)
        #expect(harness.lattice == nil)
        harness.settle()
        #expect(harness.marked.text == "かな")
        harness.press(.enter)
        #expect(harness.committed == "かな")
    }

    @Test("R-17: 読みのまま見せていても，打ち足すとライブ変換で見せる")
    func backToReadingThenType() {
        let harness = Harness(converter: twoSegments(), settings: settings())
        harness.settings.current.liveConversionSkipLength = 0
        harness.type("ka")
        harness.press(.space)
        harness.press(.backspace)
        #expect(harness.marked.text == "か")
        harness.type("na")
        harness.settle()
        #expect(harness.marked.text == "仮名")
    }

    @Test("R-17: Delete で読みに戻すと，打っている途中と同じに見せ，Enter で見せている変換を確定する")
    func resumeEditing() {
        let harness = Harness(converter: twoSegments(), settings: settings())
        harness.settings.current.liveConversionSkipLength = 0
        harness.type("kana")
        harness.press(.space)
        harness.press(.delete)
        #expect(harness.lattice == nil)
        harness.settle()
        #expect(harness.marked.text == "仮名")
        harness.press(.enter)
        #expect(harness.committed == "仮名")
    }

    // MARK: ページ送りと先頭・末尾の文節

    @Test("R-17: 標準の表では Home・End で先頭・末尾の文節へ移り，PageDown・PageUp で候補のページを送る")
    func homeEndAndPages() {
        let harness = converted()
        harness.press(.end)
        #expect(focus(harness) == 1)
        harness.press(.home)
        #expect(focus(harness) == 0)
        harness.press(.pageDown)
        #expect(harness.lastResult.handled)
        #expect(harness.lattice != nil)
        harness.press(.pageUp)
        #expect(harness.lastResult.handled)
    }

    // MARK: ATOK 風

    @Test("R-17: ATOK 風では ⇧→ で次の文節，⌃← で先頭の文節，→ で文節を長くし，↓ で先頭の文節だけ確定する")
    func atokPreset() {
        let harness = converted(.atok)
        let columns = harness.lattice?.columns.map(\.text) ?? []
        #expect(columns.count == 2)
        harness.press(.right, .shift)
        #expect(focus(harness) == 1)
        harness.press(.left, .control)
        #expect(focus(harness) == 0)
        harness.press(.right)
        #expect(harness.lattice?.columns.first?.text != columns[0])
        harness.press(.left)
        #expect(harness.lattice?.columns.first?.text == columns[0])
        harness.press(.down)
        #expect(harness.committed == columns[0])
        harness.press(.character("i"), .control)
        #expect(harness.marked.text == "イイ")
        harness.press(.enter)
        #expect(harness.committed == columns[0] + "イイ")
    }

    @Test("R-17: ATOK 風の入力中の ⌃U・⌃I・⌃P で字種を変え，Esc で読みを消す")
    func atokComposing() {
        let harness = Harness(converter: twoSegments(), settings: settings(.atok))
        harness.type("kana")
        harness.press(.character("i"), .control)
        #expect(harness.marked.text == "カナ")
        harness.press(.character("u"), .control)
        #expect(harness.marked.text == "かな")
        harness.press(.character("p"), .control)
        #expect(harness.marked.text == "ｋａｎａ")
        harness.press(.escape)
        harness.press(.escape)
        #expect(harness.marked.isEmpty)
    }
}
