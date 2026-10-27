@testable import S90Domain
import Testing

@Suite("かなの単位の訂正(言い違い・書き違い)")
struct KanaEditSearchTests {
    @Test("語にならなかった部分のかなだけを変え，綴りの近い字への置き換え・抜け・余分・入れ替えを作る")
    func edits() {
        let edits = KanaEditSearch.edits(of: "なんてゆったの", in: [3..<5])
        let readings = Set(edits.map(\.reading))
        #expect(readings.contains("なんていったの"))  // ゆ yu → い i
        #expect(readings.contains("なんてゆうったの") || readings.contains("なんてゆいったの"))  // 抜け
        #expect(edits.allSatisfy { $0.reading.hasPrefix("なん") && $0.reading.hasSuffix("の") })  // 範囲の外は変えない
        // 綴りが遠い字には置き換えない(ゆ yu → ば ba は 2 字違い，ゆ → ぎゃ gya は 3 字違い)
        #expect(!readings.contains("なんてぎゃったの"))
        #expect(Set(KanaEditSearch.edits(of: "ふいんき", in: [0..<4]).map(\.reading)).contains("ふんいき"))  // 入れ替え
    }

    @Test("音が変わらない書き分けは手間を小さくする")
    func samePronunciation() {
        let edit = KanaEditSearch.edits(of: "みずらい", in: [0..<4]).first { $0.reading == "みづらい" }
        #expect(edit?.cost == KanaEditSearch.Costs().samePronunciation)
    }

    @Test("直したあとも変えたところが語にならない候補は採らない．採った候補はキーの並びにして言語モデルで採点する")
    func corrections() {
        let corrections = KanaEditSearch.corrections(
            of: "なんてゆったの", in: [3..<5],
            plausibility: { $0 == "なんていったの" ? 0 : -10 },
            unconverted: { $0 == "なんていったの" ? [] : [0..<$0.count] },
            languageModel: { $0.map { $0 == "nannteittano" ? -1 : -9 } }
        )
        #expect(corrections.map(\.keys) == ["nannteittano"])
        #expect(corrections.first?.reading == "ナンテイッタノ")
    }
}
