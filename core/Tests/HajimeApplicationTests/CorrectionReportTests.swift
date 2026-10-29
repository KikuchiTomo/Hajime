import HajimeApplication
import HajimeDomain
import Testing

@Suite("打ち間違いの見直しの記録")
struct CorrectionReportTests {
    private let corrections = [
        "arigatpu": [
            ReadingCorrection(keys: "arigatou", reading: "アリガトウ", score: -1, cost: 1),
            ReadingCorrection(keys: "arigatpu", reading: "アリガtプ", score: -9, cost: 0),
        ],
    ]

    @Test("補正の下線を出したら「直した」，数と時間だけを書き，打った文字・読み・候補は書かない")
    func corrected() {
        let actions: [ClientAction] = [.setMarkedText(MarkedText([.init("ありが", style: .converted), .init("とう", style: .correction)]))]
        let line = CorrectionReport.outcome("見直し", corrections: corrections, actions: actions, milliseconds: 120)
        #expect(line == "見直し: 直した．並び 1 件・候補 2 件・120 ms")
        for secret in ["arigat", "アリガ", "ありが", "とう"] {
            #expect(!line.contains(secret))
        }
    }

    @Test("「もしかして」を出したら「示した」，どちらも無ければ「直さない」")
    func suggestedOrNot() {
        let suggestion: [ClientAction] = [.showNote(Note(tone: .suggestion, title: "もしかして", subject: "ありがとう"))]
        #expect(CorrectionReport.outcome("変換後の補正", corrections: corrections, actions: suggestion, milliseconds: 5).hasPrefix("変換後の補正: 示した"))
        #expect(CorrectionReport.outcome("見直し", corrections: [:], actions: [], milliseconds: 0) == "見直し: 直さない．並び 0 件・候補 0 件・0 ms")
    }
}
