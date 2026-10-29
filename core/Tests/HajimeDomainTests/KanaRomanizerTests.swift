@testable import HajimeDomain
import Testing

@Suite("かなをローマ字のキーに直す")
struct KanaRomanizerTests {
    @Test("打てば同じ読みになるキーの並びにする．ん は nn，っ は次の子音を重ねる")
    func roundTrip() {
        #expect(KanaRomanizer.keys(for: "なんていったの") == "nannteittano")
        #expect(KanaRomanizer.keys(for: "きょうはいいてんきですね") == "kyouhaiitennkidesune")
        for reading in ["ふんいき", "がっこう", "まっちゃ", "あっ", "こーひー", "じゅんび", "ちぇっく", "でぃすく", "ゔぁいおりん", "おんな", "ほんや"] {
            let keys = KanaRomanizer.keys(for: reading)
            #expect(keys != nil, "\(reading)")
            var composition = Composition()
            for key in keys ?? "" { composition.insertRomaji(key) }
            #expect(composition.conversionReading == reading)
        }
    }

    @Test("ローマ字で打てない字があれば nil")
    func unknown() {
        #expect(KanaRomanizer.keys(for: "漢字") == nil)
    }
}
