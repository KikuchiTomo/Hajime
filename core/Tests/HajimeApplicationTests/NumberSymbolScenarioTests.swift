import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

@MainActor
@Suite("数字と英字に続く記号(R-28)")
struct NumberSymbolScenarioTests {
    private func harness(_ change: (inout Settings) -> Void = { _ in }) -> Harness {
        var settings = DefaultSettings.settings
        change(&settings)
        return Harness(settings: settings)
    }

    @Test("R-28: 数字のあとの「.」「,」はピリオドとカンマ．数字のないところは句読点のまま", arguments: [
        ("3.14", "3.14"), ("1,000", "1,000"), ("1.5.", "1.5."), ("a.", "あ。"), ("ra,3", "ら、3"), (".5", "。5"),
    ])
    func separatorsAfterDigits(keys: String, reading: String) {
        let harness = harness()
        harness.type(keys)
        #expect(harness.marked.text == reading)
    }

    @Test("R-28: 数字が全角なら，ピリオドとカンマも全角")
    func fullwidthSeparators() {
        let harness = harness { $0.numberWidth = .fullwidth }
        harness.type("3.14,1")
        #expect(harness.marked.text == "３．１４，１")
    }

    @Test("R-28: 英数字のあとの「-」はハイフン．かなのあとは長音のまま", arguments: [
        ("3-4", "3-4"), ("A-1", "A-1"), ("100-0001", "100-0001"), ("ra-", "らー"), ("ba-jonn", "ばーじょん"), ("A-ka", "A-か"),
    ])
    func hyphenAfterAlphanumerics(keys: String, reading: String) {
        let harness = harness()
        harness.type(keys)
        #expect(harness.marked.text == reading)
    }

    @Test("R-28: 全角の数字のあとの「-」は全角のハイフン")
    func fullwidthHyphen() {
        let harness = harness { $0.numberWidth = .fullwidth }
        harness.type("3-4")
        #expect(harness.marked.text == "３－４")
    }

    @Test("R-28: 読みの先頭の「-」は，数字が続けば符号にし，ほかの文字が続けば長音のまま", arguments: [
        ("-3", "-3"), ("-", "ー"), ("--", "ーー"), ("->", "→"), ("-a", "ーあ"), ("-12.5", "-12.5"),
    ])
    func leadingHyphen(keys: String, reading: String) {
        let harness = harness()
        harness.type(keys)
        #expect(harness.marked.text == reading)
    }

    @Test("R-28: 設定をオフにすると，今までどおり句読点と長音にする")
    func settingsOff() {
        let harness = harness {
            $0.numberSeparators = false
            $0.alphanumericHyphen = false
        }
        harness.type("3.14,-3-4")
        #expect(harness.marked.text == "3。14、ー3ー4")
        let leading = self.harness { $0.alphanumericHyphen = false }
        leading.type("-3")
        #expect(leading.marked.text == "ー3")
    }

    @Test("R-28: 「句読点で確定」がオンでも，数字のあとのピリオドとカンマでは確定しない")
    func separatorsDoNotCommit() {
        let harness = harness {
            $0.punctuationCommits = true
            $0.punctuation = .commaPeriod
        }
        harness.type("3.14")
        #expect(harness.committed.isEmpty)
        #expect(harness.marked.text == "3.14")
        harness.type("ra.")
        #expect(harness.committed == "3.14ら．")
    }

    @Test("R-28: 小数の式も計算できる")
    func decimalCalculation() {
        let harness = Harness(converter: FakeConverter(), settings: DefaultSettings.settings,
                              wrap: { SupplementedConverter($0, settings: $1, calendar: FakeCalendar()) })
        harness.settings.current.liveConversionSkipLength = 0
        harness.type("1.5*2=")
        harness.settle()
        #expect(harness.marked.text == "3")
    }
}
