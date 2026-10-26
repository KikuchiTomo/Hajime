@testable import S90Domain
import Testing

@Suite("校正支援(R-08)")
struct ProofreadingTests {
    @Test("ら抜き言葉に本来の形を添え，仮定の形(見れば)と正しい形(見られる)には添えない", arguments: [
        ("朝早く起きれない", "「起きれない」はら抜き言葉です。「起きられない」が本来の形です。"),
        ("明日は来れますか", "「来れます」はら抜き言葉です。「来られます」が本来の形です。"),
        ("映画が見れた", "「見れた」はら抜き言葉です。「見られた」が本来の形です。"),
    ])
    func raNuki(text: String, expected: String) {
        #expect(Proofreading.note(for: text) == expected)
    }

    @Test("正しい文には何も添えない", arguments: ["見れば分かる", "映画が見られる", "朝早く起きられない", "今日は雨です", "手紙を書かせていただきます"])
    func correct(text: String) {
        #expect(Proofreading.note(for: text) == nil)
    }

    @Test("さ入れ言葉・二重敬語・重言に本来の形を添える")
    func others() {
        #expect(Proofreading.note(for: "読まさせていただきます") == "「読まさせ」はさ入れ言葉です。「読ませ」が本来の形です。")
        #expect(Proofreading.note(for: "社長がおっしゃられた") == "「おっしゃられ」は二重敬語です。「おっしゃ」で足ります。")
        #expect(Proofreading.note(for: "一番最初に着いた") == "「一番最初」は重言です。「最初」で足ります。")
    }
}
