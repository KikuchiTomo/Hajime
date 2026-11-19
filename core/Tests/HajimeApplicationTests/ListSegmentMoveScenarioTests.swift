import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

/// 文節を移るキー
struct SegmentMoveStroke: Sendable {
    let name: String
    let key: KeyEvent.Key
    var modifiers: KeyEvent.Modifiers = []
}

/// プリセットごとの，次の文節へ移るキーと前の文節へ移るキー
struct SegmentMoveKeys: Sendable, CustomTestStringConvertible {
    let preset: KeymapPreset
    let next: SegmentMoveStroke
    let previous: SegmentMoveStroke
    var testDescription: String { "\(preset.rawValue): \(next.name) / \(previous.name)" }
}


extension SegmentMoveKeys {
    private static let right = SegmentMoveStroke(name: "→", key: .right)
    private static let left = SegmentMoveStroke(name: "←", key: .left)

    private static func control(_ character: Character) -> SegmentMoveStroke {
        SegmentMoveStroke(name: "Ctrl \(character)", key: .character(character), modifiers: .control)
    }

    static let all: [SegmentMoveKeys] = [
        SegmentMoveKeys(preset: .standard, next: right, previous: left),
        SegmentMoveKeys(preset: .standard, next: SegmentMoveStroke(name: "Tab", key: .tab), previous: SegmentMoveStroke(name: "Shift Tab", key: .tab, modifiers: .shift)),
        SegmentMoveKeys(preset: .windows, next: right, previous: left),
        SegmentMoveKeys(preset: .windows, next: control("d"), previous: control("s")),
        SegmentMoveKeys(preset: .mac, next: right, previous: left),
        SegmentMoveKeys(preset: .mac, next: control("f"), previous: control("b")),
        SegmentMoveKeys(preset: .emacs, next: control("f"), previous: control("b")),
        SegmentMoveKeys(preset: .vim, next: SegmentMoveStroke(name: "l", key: .character("l")), previous: SegmentMoveStroke(name: "h", key: .character("h"))),
        SegmentMoveKeys(preset: .atok, next: SegmentMoveStroke(name: "Shift →", key: .right, modifiers: .shift),
             previous: SegmentMoveStroke(name: "Shift ←", key: .left, modifiers: .shift)),
    ]
}

/// 一覧(文節ごとの一覧・文全体の一覧)でも，キー設定の表の文節を移るキーで文節を移る．分岐図と同じ操作にする
@Suite("一覧で文節を移る")
@MainActor
struct ListSegmentMoveScenarioTests {
    /// 「きょうはいい」を「今日は」「いい」の 2 つの文節に分ける変換器
    private func converter() -> FakeConverter {
        let converter = FakeConverter([
            "きょうはいい": [("今日はいい", nil), ("京はいい", nil)], "きょうは": [("今日は", nil), ("京は", nil)], "いい": [("良い", nil), ("いい", nil)],
        ], clauses: ["きょうはいい": [("今日は", 4), ("京は", 4)], "いい": [("良い", 2), ("いい", 2)]])
        converter.words["きょうはいい"] = [
            Candidate.Word(text: "今日", readingCount: 3), Candidate.Word(text: "はいい", readingCount: 3, startsWithParticle: true),
        ]
        return converter
    }

    /// macOS と同じに，先の枝の丸と矢印キーで木をたどる操作を有効にして確かめる
    private func harness(_ presentation: CandidatePresentation, preset: KeymapPreset = .standard, converter: FakeConverter? = nil) -> Harness {
        var settings = DefaultSettings.settings
        settings.candidatePresentation = presentation
        settings.keymap = preset.keymap
        settings.initialFocus = .start
        return Harness(converter: converter ?? self.converter(), settings: settings, branchStations: true)
    }

    private func focusedIndex(_ harness: Harness) -> Int? {
        harness.marked.segments.firstIndex { $0.style == .focused }
    }

    @Test("どのプリセットでも，文節を移るキーで次・前の文節へ移り，移った文節の候補を一覧に出す",
          arguments: [CandidatePresentation.segmentList, .list], SegmentMoveKeys.all)
    func movesBetweenSegments(presentation: CandidatePresentation, keys: SegmentMoveKeys) {
        let harness = harness(presentation, preset: keys.preset)
        harness.type("kyouhaii")
        harness.press(.space)
        harness.press(keys.next.key, keys.next.modifiers)
        #expect(harness.lattice == nil)
        #expect(harness.marked.segments.map(\.text) == ["今日は", "いい"])
        #expect(focusedIndex(harness) == 1)
        let shown = Set(harness.panel?.entries.map(\.text) ?? [])
        #expect(shown.isSuperset(of: ["良い", "いい"]))
        harness.press(keys.previous.key, keys.previous.modifiers)
        #expect(focusedIndex(harness) == 0)
        #expect(harness.panel?.entries.prefix(2).map(\.text) == ["今日は", "京は"])
    }

    @Test("文全体の一覧で文節へ移ったあと，その文節の候補を選んで確定する")
    func commitsAfterMoving() {
        let harness = harness(.list)
        harness.type("kyouhaii")
        harness.press(.space)
        #expect(harness.marked.segments.count == 1)
        // ← は端で止まる．最初の文節の候補を出す
        harness.press(.left)
        #expect(focusedIndex(harness) == 0)
        harness.press(.character("2"))
        #expect(harness.marked.segments.first?.text == "京は")
        harness.press(.enter)
        #expect(harness.committed.hasPrefix("京は"))
    }

    @Test("文全体の一覧で文節へ移ったあと，取り消しのキーで文全体の一覧に戻る")
    func undoReturnsToWholeList() {
        let harness = harness(.list)
        harness.type("kyouhaii")
        harness.press(.space)
        let whole = harness.panel?.entries.map(\.text)
        harness.press(.tab)
        #expect(harness.marked.segments.count == 2)
        harness.press(.escape)
        #expect(harness.marked.segments.count == 1)
        #expect(harness.panel?.entries.map(\.text) == whole)
    }

    @Test("文全体の一覧の種類の行では，← → は字種を移り，Tab は文節へ移る")
    func variantRow() {
        let harness = harness(.list)
        harness.type("kyouhaii")
        harness.press(.space)
        harness.press(.up)
        #expect(harness.panel?.focus == .variants)
        let selected = harness.panel?.selectedVariant
        harness.press(.right)
        #expect(harness.panel?.focus == .variants)
        #expect(harness.panel?.selectedVariant != selected)
        #expect(harness.marked.segments.count == 1)
        harness.press(.tab)
        #expect(harness.panel?.focus != .variants)
        #expect(harness.marked.segments.count == 2)
    }

    @Test("文節が 1 つの文は，文節を移るキーを押しても文全体の一覧のまま")
    func singleSegmentStays() {
        let harness = harness(.list, converter: FakeConverter(["かな": [("仮名", nil), ("かな", nil)]]))
        harness.type("kana")
        harness.press(.space)
        let whole = harness.panel?.entries.map(\.text)
        harness.press(.right)
        #expect(harness.lastResult.handled)
        #expect(harness.panel?.entries.map(\.text) == whole)
        harness.press(.enter)
        #expect(harness.committed == "仮名")
    }
}
