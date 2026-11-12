import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

/// 分岐図で文節の長さを変える(⇧← ⇧→)と，すぐ後ろの文節だけを分け直す
@Suite("文節の長さを変えたときの分け直し")
@MainActor
struct ResizeScenarioTests {
    /// 「海の｜色は｜青く｜光る」の 4 文節に分かれる変換器
    private func converter() -> FakeConverter {
        let converter = FakeConverter([
            "うみのいろはあおくひかる": [("海の色は青く光る", nil)],
            "ひかる": [("光る", nil)],
        ])
        let particle = { (text: String) in Candidate.Word(text: text, readingCount: 1, startsWithParticle: true, endsWithParticle: true) }
        converter.candidateWords["海の色は青く光る"] = [
            Candidate.Word(text: "海", readingCount: 2), particle("の"), Candidate.Word(text: "色", readingCount: 2), particle("は"),
            Candidate.Word(text: "青く", readingCount: 3), Candidate.Word(text: "光る", readingCount: 3),
        ]
        return converter
    }

    @Test("文節を長くすると，すぐには後ろの 2 文節分だけを変換し直して出し，残りの読みは打鍵の合間に分け直す")
    func resegmentsNearbyFirst() {
        var settings = DefaultSettings.settings
        settings.initialFocus = .start
        let harness = Harness(converter: converter(), settings: settings)
        harness.type("uminoirohaaokuhikaru")
        harness.press(.space)
        #expect(harness.lattice?.columns.map(\.text) == ["海の", "色は", "青く", "光る"])
        harness.runsFollowUps = false
        let before = harness.converter.requests.count
        harness.press(.right, .shift)
        let immediate = harness.converter.requests.dropFirst(before).map(\.reading)
        #expect(immediate.contains("ろはあおく"))
        #expect(!immediate.contains("ろはあおくひかる"))
        #expect(harness.lattice?.columns.last?.text == "光る")
        // 打鍵の合間に，残りの読み全体で分け直す(すぐに分け直していたときと同じ結果になる)
        let beforeFollowUps = harness.converter.requests.count
        harness.followUp()
        #expect(harness.converter.requests.dropFirst(beforeFollowUps).map(\.reading).contains("ろはあおくひかる"))
        #expect(harness.lattice?.columns.first?.isFocused == true)
    }

    @Test("長さを変えた文節から動いたあとは，残りを分け直さない(選んでいる文節の外が急に変わらないように)")
    func skipsRestAfterMoving() {
        var settings = DefaultSettings.settings
        settings.initialFocus = .start
        let harness = Harness(converter: converter(), settings: settings)
        harness.type("uminoirohaaokuhikaru")
        harness.press(.space)
        harness.runsFollowUps = false
        harness.press(.right, .shift)
        harness.press(.right)
        let before = harness.converter.requests.count
        harness.followUp()
        #expect(!harness.converter.requests.dropFirst(before).map(\.reading).contains("ろはあおくひかる"))
    }
}
