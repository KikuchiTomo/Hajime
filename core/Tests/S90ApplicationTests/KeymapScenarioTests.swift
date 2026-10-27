import S90Application
import S90Domain
import S90TestSupport
import Testing

/// キー設定の表(R-17)のコマンドを，キーの列から確かめる
@MainActor
@Suite("キー設定の表で動かす(R-17)")
struct KeymapScenarioTests {
    /// 「きょうはいい」を「今日」「はいい」の 2 つの文節に分ける変換器
    private func twoSegments() -> FakeConverter {
        let converter = FakeConverter([
            "きょうはいい": [("今日はいい", nil)], "きょうは": [("今日は", nil), ("京は", nil)], "いい": [("良い", nil), ("いい", nil)],
        ], clauses: ["きょうはいい": [("今日は", 4), ("京は", 4)], "いい": [("良い", 2), ("いい", 2)]])
        converter.words["きょうはいい"] = [
            Candidate.Word(text: "今日", readingCount: 3), Candidate.Word(text: "はいい", readingCount: 3, startsWithParticle: true),
        ]
        return converter
    }

    private func settings(_ preset: KeymapPreset = .standard, adding rows: [KeymapEntry] = []) -> Settings {
        var settings = DefaultSettings.settings
        settings.keymap = preset.keymap
        settings.keymap.entries += rows
        return settings
    }

    @Test("R-17: 変換中に ⌃7 を全角カタカナに割り当てると，⌃7 でカタカナにする")
    func controlSevenToKatakana() {
        let harness = Harness(converter: FakeConverter(["かな": [("仮名", nil)]]),
                              settings: settings(adding: [KeymapEntry(.converting, KeyStroke(.character("7"), control: true), .toKatakana)]))
        harness.type("kana")
        harness.press(.space)
        #expect(harness.lattice != nil)
        harness.press(.character("7"), .control)
        #expect(harness.marked.text == "カナ")
        // 入力中には割り当てていないので，⌃7 では何もしない(読みが入力先に混ざらないように捨てる)
        let composing = Harness(converter: FakeConverter(["かな": [("仮名", nil)]]),
                                settings: settings(adding: [KeymapEntry(.converting, KeyStroke(.character("7"), control: true), .toKatakana)]))
        composing.type("kana")
        composing.press(.character("7"), .control)
        #expect(composing.lastResult.handled)
        #expect(composing.marked.text == "かな")
    }

    @Test("R-17: 入力文字なしで ⇧Space は設定と逆の幅の空白，⌃⇧Space は全角空白")
    func spaces() {
        let harness = Harness(settings: settings(.windows))
        harness.press(.space, .shift)
        #expect(harness.committed == "\u{3000}")
        harness.press(.space)
        #expect(!harness.lastResult.handled)
        var halfwidthFirst = settings(.windows)
        halfwidthFirst.spaceWidth = .fullwidth
        let full = Harness(settings: halfwidthFirst)
        full.context = InputContext(profile: .programming)
        full.press(.space, [.control, .shift])
        // 全角空白を入れるコマンドは，プログラミング用のアプリでも全角にする
        #expect(full.committed == "\u{3000}")
    }

    @Test("R-17: 組み立て中に空白を入れるコマンドは，確定してから空白を入れる")
    func spaceWhileComposing() {
        let harness = Harness(converter: FakeConverter(["かな": [("仮名", nil)]]), settings: settings(.windows))
        harness.type("kana")
        harness.press(.space, [.control, .shift])
        #expect(harness.committed == "仮名\u{3000}")
        #expect(harness.marked.isEmpty)
    }

    @Test("R-17: ⌘ の組み合わせも割り当てられ，割り当てていない ⌘ はアプリに渡す")
    func commandKey() {
        let harness = Harness(converter: FakeConverter(["かな": [("仮名", nil)]]),
                              settings: settings(adding: [KeymapEntry(.composing, KeyStroke(.character("k"), command: true), .toKatakana)]))
        harness.type("kana")
        harness.press(.character("k"), .command)
        #expect(harness.lastResult.handled)
        #expect(harness.marked.text == "カナ")
        harness.press(.character("c"), .command)
        #expect(!harness.lastResult.handled)
        #expect(harness.committed == "カナ")
    }

    @Test("R-17: Enter の行を消すと，入力中の Enter は何もせず，入力文字なしではアプリに渡す")
    func removedEnter() {
        var settings = settings()
        settings.keymap.entries.removeAll { $0.stroke == KeyStroke(.enter) }
        settings.keymap.entries.append(KeymapEntry(.composing, KeyStroke(.character("m"), control: true), .commit))
        let harness = Harness(converter: FakeConverter(["かな": [("仮名", nil)]]), settings: settings)
        harness.type("kana")
        harness.press(.enter)
        #expect(harness.lastResult.handled)
        #expect(harness.committed.isEmpty)
        harness.press(.character("m"), .control)
        #expect(harness.committed == "仮名")
        harness.press(.enter)
        #expect(!harness.lastResult.handled)
    }

    @Test("R-17: 一部確定は先頭の文節だけを確定し，残りの変換を続ける")
    func commitFirstSegment() {
        let harness = Harness(converter: twoSegments(), settings: settings(.windows))
        harness.type("kyouhaii")
        harness.press(.space)
        let columns = harness.lattice?.columns.map(\.text) ?? []
        #expect(columns.count == 2)
        harness.press(.down, .control)
        #expect(harness.committed == columns.first)
        #expect(harness.lattice?.columns.map(\.text) == Array(columns.dropFirst()))
        harness.press(.enter)
        #expect(harness.committed == columns.joined())
    }

    @Test("再変換で先頭の文節だけを確定したあとに Esc を押しても，元の文字を重ねて入れない")
    func reconversionAfterCommittingFirstSegment() {
        let harness = Harness(converter: twoSegments(), settings: settings(.windows))
        _ = harness.session.reconvert("今日はいい", reading: "きょうはいい", context: InputContext())
        harness.press(.down, .control)
        #expect(harness.committed == "今日は")
        // 残りの文節の変換をやめる．元の文字(今日はいい)を重ねて入れない
        harness.press(.escape)
        #expect(harness.committed == "今日は")
    }

    @Test("R-17: 先頭・末尾の文節と，候補の先頭・末尾・ページ")
    func segmentAndCandidateJumps() {
        let harness = Harness(converter: twoSegments(), settings: settings(.windows, adding: [
            KeymapEntry(.converting, KeyStroke(.end, control: true), .lastCandidate),
            KeymapEntry(.converting, KeyStroke(.home, control: true), .firstCandidate),
        ]))
        harness.type("kyouhaii")
        harness.press(.space)
        harness.press(.end)
        #expect(harness.lattice?.columns.firstIndex(where: \.isFocused) == 1)
        harness.press(.home)
        #expect(harness.lattice?.columns.firstIndex(where: \.isFocused) == 0)
        let first = harness.marked.text
        #expect((harness.lattice?.columns.first?.alternatives.count ?? 0) >= 2)
        harness.press(.end, .control)
        #expect(harness.marked.text != first)
        harness.press(.home, .control)
        #expect(harness.marked.text == first)
        harness.press(.pageDown)
        // 候補が 1 ページに収まるときは先頭のページのまま
        #expect(harness.marked.text == first)
    }

    @Test("R-17: Vim 風では変換中に l・h で文節を移り，j で候補を送り，Esc で読みに戻る．入力中の h・j・k・l は文字のまま")
    func vimPreset() {
        let harness = Harness(converter: twoSegments(), settings: settings(.vim))
        harness.type("kyouhaii")
        #expect(harness.lattice == nil)
        harness.press(.space)
        #expect(harness.lattice?.columns.firstIndex(where: \.isFocused) == 0)
        harness.press(.character("l"))
        #expect(harness.lattice?.columns.firstIndex(where: \.isFocused) == 1)
        harness.press(.character("h"))
        #expect(harness.lattice?.columns.firstIndex(where: \.isFocused) == 0)
        let first = harness.marked.text
        harness.press(.character("j"))
        #expect(harness.marked.text != first)
        harness.press(.character("k"))
        #expect(harness.marked.text == first)
        harness.press(.escape)
        #expect(harness.lattice == nil)
        #expect(harness.committed.isEmpty)
        // 入力中の h は読みに足す
        harness.press(.character("h"))
        #expect(harness.lattice == nil)
        #expect(harness.committed.isEmpty)
    }

    @Test("R-17: Vim 風でも，入力文字なしの Esc は英数に切り替えて Esc をアプリに渡す(設定)")
    func vimEscapeInIdle() {
        var vim = settings(.vim)
        vim.escapeSwitchesToDirect = true
        let harness = Harness(settings: vim)
        harness.press(.escape)
        #expect(!harness.lastResult.handled)
        #expect(harness.session.mode == .direct)
    }

    @Test("R-17: 一覧でも候補のページを送る")
    func listPages() {
        var list = settings(.windows)
        list.candidatePresentation = .list
        list.listCandidatesPerPage = 3
        let candidates: [(text: String, readingCount: Int?)] = ["一", "二", "三", "四", "五"].map { ($0, nil) }
        let harness = Harness(converter: FakeConverter(["かず": candidates]), settings: list)
        harness.type("kazu")
        harness.press(.space)
        harness.press(.pageDown)
        #expect(harness.panel?.position == 4)
        harness.press(.pageDown)
        #expect(harness.panel?.position == 1)
        harness.press(.pageUp)
        #expect(harness.panel?.position == 4)
    }

    @Test("R-17: 無変換でかなの種類を順に変える")
    func switchKanaType() {
        let harness = Harness(converter: FakeConverter(["かな": [("仮名", nil)]]), settings: settings(.windows))
        harness.type("kana")
        harness.press(.muhenkan)
        #expect(harness.marked.text == "カナ")
        harness.press(.muhenkan)
        #expect(harness.marked.text == "ｶﾅ")
        harness.press(.muhenkan)
        #expect(harness.marked.text == "かな")
    }

    @Test("R-17: 学習を使わずに変換すると，入力を終えるまで学習を使わない")
    func convertWithoutLearning() {
        let converter = FakeConverter(["かな": [("仮名", nil)]])
        let harness = Harness(converter: converter, settings: settings(.windows))
        harness.type("kana")
        harness.press(.function(2))
        #expect(converter.learningSuspended)
        #expect(harness.lattice != nil)
        harness.press(.enter)
        #expect(harness.committed == "仮名")
        #expect(!converter.learningSuspended)
        // 学習を使わなかった確定は，最後の学習の取り消しの対象にしない
        #expect(!converter.forgetLastCommit())
    }

    @Test("R-17: 選んでいる候補を学習から消し，足元に知らせる")
    func forgetCandidate() {
        let converter = FakeConverter(["かな": [("仮名", nil), ("假名", nil)]])
        let harness = Harness(converter: converter, settings: settings(.windows))
        harness.type("kana")
        harness.press(.space)
        harness.press(.down)
        harness.press(.delete, .control)
        #expect(converter.forgotten.map(\.text) == ["假名"])
        #expect(harness.lattice?.note == "学習から削除しました")
        harness.press(.down)
        #expect(harness.lattice?.note == nil)
    }

    @Test("標準のキー設定でも，変換中の ⌃⌫ で選んでいる候補を学習から消せる")
    func forgetCandidateInStandard() {
        let converter = FakeConverter(["かな": [("仮名", nil), ("假名", nil)]])
        let harness = Harness(converter: converter)
        harness.type("kana")
        harness.press(.space)
        harness.press(.down)
        harness.press(.backspace, .control)
        #expect(converter.forgotten.map(\.text) == ["假名"])
        #expect(harness.lattice?.note == "学習から削除しました")
    }

    @Test("R-17: 入力文字なしで最後の学習を取り消し，次のキーで案内を消す")
    func forgetLastCommit() {
        let converter = FakeConverter(["かな": [("仮名", nil)]])
        let harness = Harness(converter: converter, settings: settings(adding: [
            KeymapEntry(.idle, KeyStroke(.backspace, control: true), .forgetLastCommit),
        ]))
        harness.type("kana")
        harness.press(.space)
        harness.press(.enter)
        harness.press(.backspace, .control)
        #expect(converter.forgotten.map(\.text) == ["仮名"])
        #expect(harness.note == "最後の学習を取り消しました")
        harness.press(.left)
        #expect(harness.note == nil)
        #expect(!harness.lastResult.handled)
        // 取り消すものが無ければ何もしない
        harness.press(.backspace, .control)
        #expect(harness.note == nil)
    }

    @Test("R-17: 取り消して英数にすると，読みを捨てて英数にする")
    func cancelAndDirectMode() {
        let harness = Harness(converter: FakeConverter(["かな": [("仮名", nil)]]),
                              settings: settings(adding: [KeymapEntry(.anywhere, KeyStroke(.escape, shift: true), .cancelAndDirectMode)]))
        harness.type("kana")
        harness.press(.escape, .shift)
        #expect(harness.committed.isEmpty)
        #expect(harness.marked.isEmpty)
        #expect(harness.session.mode == .direct)
    }

    @Test("R-17: 好きなキーを日本語と英数の切り替えにできる(かなキーの無いキーボード)")
    func customModeKey() {
        let harness = Harness(converter: FakeConverter(["かな": [("仮名", nil)]]),
                              settings: settings(adding: [KeymapEntry(.anywhere, KeyStroke(.space, control: true), .toggleMode)]))
        harness.type("kana")
        harness.press(.space, .control)
        #expect(harness.committed == "仮名")
        #expect(harness.session.mode == .direct)
        harness.press(.space, .control)
        #expect(harness.session.mode == .japanese)
    }

    @Test("R-17: 案内のキーは表で割り当てたキーにする")
    func notesFollowKeymap() {
        var keymap = settings()
        keymap.keymap.entries.removeAll { $0.command == .nextCandidate && $0.state == .converting }
        keymap.keymap.entries.append(KeymapEntry(.converting, KeyStroke(.character("n"), control: true), .nextCandidate))
        keymap.candidatePresentation = .list
        let harness = Harness(lexicon: FakeLexicon(words: ["python"]), settings: keymap)
        harness.type("python")
        harness.press(.down)
        #expect(harness.panel?.note == "⌃N 入力のままに戻す")
    }

    @Test("R-17: 英字入力では，読みを組み立てていないとき表の入力中・入力文字なしの行を使わない")
    func englishInputKeepsEnglishBehavior() {
        var english = settings()
        english.inputStyle = .english
        let harness = Harness(settings: english)
        harness.press(.space, .shift)
        // 英字入力では ⇧Space も英語の入力と同じにアプリに渡す
        #expect(!harness.lastResult.handled)
        harness.press(.eisu)
        #expect(harness.session.mode == .direct)
    }
}
