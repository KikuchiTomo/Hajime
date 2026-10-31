import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

@Suite("英単語にしない文字数")
@MainActor
struct EnglishSkipLengthScenarioTests {
    private func harness(change: (inout Settings) -> Void = { _ in }) -> Harness {
        var settings = DefaultSettings.settings
        settings.inputStyle = .englishAuto
        change(&settings)
        return Harness(converter: FakeConverter(["まけ": [("負け", nil)]]), lexicon: FakeLexicon(words: ["make"]), settings: settings)
    }

    @Test("R-02: 英字入力(自動)でも，ローマ字として読んだかなが英単語にしない文字数以下の語は日本語にする")
    func keepsShortReadingJapanese() {
        let harness = harness()
        harness.type("make")
        harness.settle()
        #expect(harness.marked.text != "make")
    }

    @Test("R-02: 前が英語なら，短い読みの語も前の語で見分けて英語にする")
    func followsEnglishContext() {
        let harness = harness()
        harness.context = InputContext(precedingText: "Let's ")
        harness.type("make")
        harness.settle()
        #expect(harness.marked.text == "make")
    }

    @Test("R-02: 英単語にしない文字数を 0 にすると，短い読みの語も英語にする")
    func convertsShortWordWhenOff() {
        let harness = harness { $0.englishSkipLength = 0 }
        harness.type("make")
        harness.settle()
        #expect(harness.marked.text == "make")
    }

    @Test("R-02: 利用者が「いつも英語」にした語は，短い読みでも英語にする")
    func keepsUserEnglishWord() {
        let harness = harness { $0.wordLanguage.englishWords = ["make"] }
        harness.type("make")
        harness.settle()
        #expect(harness.marked.text == "make")
    }
}
