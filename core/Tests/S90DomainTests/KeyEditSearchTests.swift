@testable import S90Domain
import Testing

@Suite("1 か所の打ち間違いを全部試す訂正(R-02)")
struct KeyEditSearchTests {
    @Test("取り違え・打ち忘れ・余分な 1 打・入れ替えの並びを作り，かなにならない綴りと元と同じ読みは除く")
    func edits() {
        let readings = Set(KeyEditSearch.edits(of: "mizurai").map(\.reading))
        #expect(readings.contains("みづらい"))  // z → d
        #expect(readings.contains("みずあらい"))  // 打ち忘れ
        #expect(readings.contains("みずらい") == false)
        #expect(KeyEditSearch.edits(of: "mizurai").allSatisfy { !$0.reading.contains(where: { $0.isASCII && $0.isLetter }) })
        #expect(Set(KeyEditSearch.edits(of: "hte").map(\.reading)).contains("て"))  // 入れ替え
    }

    @Test("音が同じ書き誤り(ず/づ・は/わ・え/へ・お/を・長音)は手間を小さくする")
    func samePronunciation() {
        let costs = KeyEditSearch.Costs()
        func cost(_ keys: String, _ reading: String) -> Double? { KeyEditSearch.edits(of: keys).first { $0.reading == reading }?.cost }
        #expect(cost("mizurai", "みづらい") == costs.samePronunciation)
        #expect(cost("konnnitiwa", "こんにちは") == costs.samePronunciation)
        #expect(cost("ekieikimasu", "えきへいきます") == costs.samePronunciation)
        #expect(cost("touri", "とおり") == costs.samePronunciation)
        #expect(cost("mizurai", "みずたい") == costs.neighborSubstitution)  // 音が変わる取り違えは隣のキーの手間
        #expect(KeyEditSearch.pronunciation(of: "とうり") == KeyEditSearch.pronunciation(of: "とおり"))
        #expect(KeyEditSearch.pronunciation(of: "みず") != KeyEditSearch.pronunciation(of: "みぞ"))
    }

    @Test("前に見直した部分は探し直さず，変わったところの少し前から探す")
    func searchStart() {
        #expect(KeyEditSearch.searchStart(keys: "kyouhaiitenki", previous: nil) == 0)
        #expect(KeyEditSearch.searchStart(keys: "kyouhaiitenki", previous: "kyouhaii") == 8 - DefaultSettings.keyEditOverlap)
        #expect(KeyEditSearch.edits(of: "abcde", from: 3).allSatisfy { $0.keys.hasPrefix("abc") })
    }

    @Test("候補は言語モデルの点数から手間を引いて並べ，打ったままの並びも入れる．言語モデルが使えなければ空")
    func corrections() {
        let list = KeyEditSearch.corrections(of: "mizurai", limit: 4, plausibility: { $0 == "みづらい" ? 0 : -10 },
                                             languageModel: { keys in keys.map { $0 == "midurai" ? -10 : -12 } })
        #expect(list.first?.isUnchanged == true)
        #expect(list.contains { $0.keys == "midurai" })
        #expect(KeyEditSearch.corrections(of: "mizurai", plausibility: { _ in 0 }, languageModel: { $0.map { _ in nil } }).isEmpty)
    }

    @Test("打ったままの並びを言語モデルが読めなくても(かなにならない英字が残る)，訂正の候補は返す")
    func unscorableTyped() {
        let list = KeyEditSearch.corrections(of: "gakusri", limit: 4, plausibility: { $0 == "がくせい" ? 0 : -20 },
                                             languageModel: { $0.map { $0 == "gakusri" ? nil : -10 } })
        #expect(!list.isEmpty && !list.contains(where: \.isUnchanged))
    }

    @Test("2 つの候補の並びを合わせ，同じキーは点数の高い方を残す")
    func merge() {
        let a = ReadingCorrection(keys: "a", reading: "ア", score: -3, cost: 1)
        let b = ReadingCorrection(keys: "a", reading: "ア", score: -2, cost: 1)
        let c = ReadingCorrection(keys: "i", reading: "イ", score: -5, cost: 1)
        #expect(KeyEditSearch.merge([a, c], [b]) == [b, c])
    }

    @Test("変換のもっともらしさが大きく上がる訂正は，言語モデルの差が小さくても示す")
    func plausibilityHelpsDecision() {
        let typed = ReadingCorrection(keys: "mizurai", reading: "ミズライ", score: -15.8, cost: 0)
        var fixed = ReadingCorrection(keys: "midurai", reading: "ミヅライ", score: -13.9 - 1, cost: 1)
        #expect(ReadingCorrectionRule(level: .standard).decision(among: [typed, fixed], reading: "みずらい") == nil)
        fixed.plausibilityGain = 24
        #expect(ReadingCorrectionRule(level: .standard).decision(among: [typed, fixed], reading: "みずらい") != nil)
    }
}
