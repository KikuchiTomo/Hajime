import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

/// 読みを決めて返す(OS の機能の代わり)
@MainActor
private final class FakeTranscriber: ReadingTranscribing {
    let table: [String: String]
    init(_ table: [String: String]) { self.table = table }
    func reading(of text: String) -> String? { table[text] }
}

@Suite("再変換")
@MainActor
struct ReconversionScenarioTests {
    @Test("入力文字なしで再変換のキーを押すと，入力先の選んでいる文字を求める．組み立て中は効かない")
    func requestsSelection() {
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings())
        #expect(session.handle(KeyEvent(.henkan), context: InputContext()).actions == [.requestReconversion])
        #expect(session.handle(KeyEvent(.character("r"), modifiers: [.control, .shift]), context: InputContext()).actions == [.requestReconversion])
        _ = session.handle(KeyEvent(.character("k")), context: InputContext())
        #expect(!session.handle(KeyEvent(.henkan), context: InputContext()).actions.contains(.requestReconversion))
    }

    @Test("選んでいる文字を読みに戻して変換し，選び直して確定する．Esc で元の文字に戻す")
    func reconvert() {
        let converter = FakeConverter(["へんかん": [("変換", nil), ("返還", nil)]])
        var settings = DefaultSettings.settings
        settings.candidatePresentation = .list
        let harness = Harness(converter: converter, settings: settings)
        let actions = harness.session.reconvert("変換", transcriber: FakeTranscriber(["変換": "へんかん"]), context: InputContext())
        #expect(actions.contains { if case .showCandidates = $0 { true } else { false } })
        harness.click(.entry(1))
        #expect(harness.committed == "返還")

        let other = Harness(converter: converter, settings: settings)
        _ = other.session.reconvert("変換", reading: "へんかん", context: InputContext())
        other.press(.escape)
        #expect(other.committed == "変換")
    }

    @Test("読みが求められない・かなでない・長すぎる・空のときは何もしない")
    func rejects() {
        let session = InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: FakeSettings())
        #expect(session.reconvert("変換", transcriber: FakeTranscriber([:]), context: InputContext()).isEmpty)
        #expect(session.reconvert("abc", reading: "abc", context: InputContext()).isEmpty)
        #expect(session.reconvert("", reading: "", context: InputContext()).isEmpty)
        let long = String(repeating: "あ", count: DefaultSettings.maximumReconversionLength + 1)
        #expect(session.reconvert(long, reading: long, context: InputContext()).isEmpty)
        #expect(!session.isComposing)
    }
}
