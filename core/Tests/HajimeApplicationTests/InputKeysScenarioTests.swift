import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

@MainActor
@Suite("？と！で確定・テンキーの Enter で計算・英字の大文字と小文字(入力の流れ)")
struct InputKeysScenarioTests {
    private func harness(_ table: [String: [(text: String, readingCount: Int?)]] = [:], _ change: (inout Settings) -> Void = { _ in }) -> Harness {
        var settings = DefaultSettings.settings
        settings.liveConversionSkipLength = 0
        change(&settings)
        return Harness(converter: FakeConverter(table), settings: settings,
                       wrap: { SupplementedConverter($0, settings: $1, calendar: FakeCalendar()) })
    }

    // MARK: ？と！で確定(R-01)

    @Test("R-01: 「？と！で確定」をオンにすると，？ と ！ まで確定する", arguments: [("nani?", "なに？"), ("yatta!", "やった！")])
    func questionExclamationCommits(keys: String, committed: String) {
        let harness = harness { $0.questionExclamationCommits = true }
        harness.type(keys)
        #expect(harness.committed == committed)
        #expect(harness.marked.isEmpty)
    }

    @Test("R-01: 既定(オフ)では ？ と ！ で確定しない．句読点で確定とは別の設定")
    func questionExclamationDefault() {
        let off = harness()
        off.type("nani?")
        #expect(off.committed.isEmpty)
        #expect(off.marked.text == "なに？")

        let onlyMarks = harness { $0.questionExclamationCommits = true }
        onlyMarks.type("sou.")
        #expect(onlyMarks.committed.isEmpty)
        #expect(onlyMarks.marked.text == "そう。")
    }

    // MARK: テンキーの Enter で計算(R-08)

    private func typeKeypad(_ keys: String, into harness: Harness) {
        for key in keys { harness.press(.character(key), isKeypad: true) }
    }

    @Test("R-08: オンにすると，テンキーの式は確定せずに読みに入り，テンキーの Enter で計算の結果を第 1 候補にして変換する")
    func keypadCalculation() {
        let harness = harness { $0.keypadCalculation = true }
        typeKeypad("12*3", into: harness)
        #expect(harness.committed.isEmpty)
        #expect(harness.marked.text == "12*3")
        harness.press(.enter, isKeypad: true)
        #expect(harness.committed.isEmpty)
        #expect(harness.marked.text == "36")
        harness.press(.enter)
        #expect(harness.committed == "36")
    }

    @Test("R-08: 式でなければ，テンキーの Enter はふつうの Enter で確定する")
    func keypadEnterWithoutExpression() {
        let harness = harness { $0.keypadCalculation = true }
        typeKeypad("120", into: harness)
        harness.press(.enter, isKeypad: true)
        #expect(harness.committed == "120")
    }

    @Test("R-08: 「計算」がオフなら，テンキーの Enter で計算しない")
    func keypadEnterWithoutCalculation() {
        let harness = harness {
            $0.keypadCalculation = true
            $0.calculation = false
        }
        typeKeypad("1+2", into: harness)
        harness.press(.enter, isKeypad: true)
        #expect(harness.committed == "1+2")
    }

    @Test("R-08: 既定(オフ)では，テンキーの数字と記号はこれまでどおり半角のまま確定する")
    func keypadCalculationDefault() {
        let harness = harness()
        typeKeypad("1+2", into: harness)
        #expect(harness.committed == "1+2")
        #expect(harness.marked.isEmpty)
    }

    // MARK: 英字の大文字と小文字(R-03)

    @Test("R-03: 半角英数のキーを続けて押すと，入力どおり → 大文字 → 先頭だけ大文字 と変え，小文字と同じ見た目の段は飛ばす")
    func cyclesLetterCase() {
        let harness = harness()
        harness.type("python")
        var shown: [String] = []
        for _ in 0..<4 {
            harness.press(.function(10))
            shown.append(harness.marked.text)
        }
        #expect(shown == ["python", "PYTHON", "Python", "python"])
        harness.press(.function(10))
        harness.press(.enter)
        #expect(harness.committed == "PYTHON")
    }

    @Test("R-03: 全角英数でも大文字と小文字を変える")
    func cyclesFullwidthLetterCase() {
        let harness = harness()
        harness.type("abc")
        harness.press(.function(9))
        #expect(harness.marked.text == "ａｂｃ")
        harness.press(.function(9))
        #expect(harness.marked.text == "ＡＢＣ")
    }

    @Test("R-03: 設定をオフにすると，続けて押しても入力どおりのまま")
    func letterCaseCycleOff() {
        let harness = harness { $0.cyclesLetterCase = false }
        harness.type("python")
        harness.press(.function(10))
        harness.press(.function(10))
        #expect(harness.marked.text == "python")
    }

    @Test("R-03: ほかの字種に移ってから英数に戻すと，入力どおりから始める")
    func letterCaseResetsAfterOtherVariant() {
        let harness = harness()
        harness.type("python")
        harness.press(.function(10))
        harness.press(.function(10))
        #expect(harness.marked.text == "PYTHON")
        harness.press(.function(7))
        harness.press(.function(10))
        #expect(harness.marked.text == "python")
    }
}
