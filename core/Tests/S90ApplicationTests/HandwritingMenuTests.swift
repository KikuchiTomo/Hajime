import S90Application
import S90Domain
import S90TestSupport
import Testing

@MainActor
@Suite("入力メニューの手書き入力")
struct HandwritingMenuTests {
    @Test("使う設定のときだけ，組み立て中の文字を確定して窓を開く")
    func opensFromMenu() {
        var settings = DefaultSettings.settings
        settings.handwriting = true
        let harness = Harness(converter: FakeConverter(["かな": [("仮名", nil)]]), settings: settings)
        harness.type("kana")
        let actions = harness.session.openHandwriting()
        #expect(actions.last == .showHandwriting)
        #expect(actions.contains { if case .commit = $0 { true } else { false } })
        var off = DefaultSettings.settings
        off.handwriting = false
        #expect(Harness(converter: FakeConverter(), settings: off).session.openHandwriting().isEmpty)
    }
}
