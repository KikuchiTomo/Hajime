import HajimeDomain
import Testing

@Suite("検証木の点数で候補を並べ替える")
struct CandidateRerankingTests {
    private static func engine(_ text: String, _ readingCount: Int = 4, id: Int = 0) -> Candidate {
        Candidate(text: text, readingCount: readingCount, origin: .engine(id: id))
    }

    private static func symbol(_ text: String) -> Candidate {
        Candidate(text: text, readingCount: 4, origin: .symbol)
    }

    @Test("第 1 候補は点数が低くても変えない")
    func keepsFirst() {
        let candidates = [Self.engine("一"), Self.engine("二"), Self.engine("三")]
        let scores = ["一": -9.0, "二": -1.0, "三": -0.5]
        let result = CandidateReranking.reranked(candidates, adding: [], readingCount: 4) { scores[$0] }
        #expect(result.map(\.text) == ["一", "三", "二"])
    }

    @Test("足す候補を点数の順に混ぜ，同じ表記は重ねない．増えたぶんは並べ替える候補の最後の位置の後ろに入れる")
    func mergesAdditions() {
        let candidates = [Self.engine("一"), Self.engine("二"), Self.engine("部", 2)]
        let additions = [Self.engine("二", id: 5), Self.engine("四", id: 6), Self.engine("五", id: 7)]
        let scores = ["二": -3.0, "四": -1.0, "五": -2.0]
        let result = CandidateReranking.reranked(candidates, adding: additions, readingCount: 4) { scores[$0] }
        #expect(result.map(\.text) == ["一", "四", "五", "二", "部"])
        // 重なった表記は今の候補(先に出ていたもの)を残す
        #expect(result[3].origin == .engine(id: 0))
    }

    @Test("エンジン以外の候補と読みの一部の候補は元の位置に残す")
    func keepsOtherCandidatesInPlace() {
        let candidates = [Self.engine("一"), Self.engine("二"), Self.symbol("→"), Self.engine("三"), Self.engine("部", 2), Self.engine("四")]
        let scores = ["二": -3.0, "三": -1.0, "四": -2.0]
        let result = CandidateReranking.reranked(candidates, adding: [], readingCount: 4) { scores[$0] }
        #expect(result.map(\.text) == ["一", "三", "→", "四", "部", "二"])
    }

    @Test("点数の無い候補は点数のある候補のあとに元の順で置く")
    func placesUnscoredLast() {
        let candidates = [Self.engine("一"), Self.engine("二"), Self.engine("三"), Self.engine("四")]
        let scores = ["四": -1.0]
        let result = CandidateReranking.reranked(candidates, adding: [Self.engine("短", 3)], readingCount: 4) { scores[$0] }
        #expect(result.map(\.text) == ["一", "四", "二", "三"])
    }

    @Test("点数が同じなら元の順を保つ")
    func stableForTies() {
        let candidates = [Self.engine("一"), Self.engine("二"), Self.engine("三")]
        let result = CandidateReranking.reranked(candidates, adding: [], readingCount: 4) { _ in -1.0 }
        #expect(result.map(\.text) == ["一", "二", "三"])
    }

    @Test("採点する表記は第 1 候補とエンジン以外の候補を除き，今の候補のあとに足す候補を並べる")
    func textsToScore() {
        let candidates = [Self.engine("一"), Self.engine("二"), Self.symbol("→"), Self.engine("部", 2)]
        let additions = [Self.engine("一"), Self.engine("四"), Self.engine("二"), Self.symbol("←")]
        #expect(CandidateReranking.textsToScore(candidates, adding: additions, readingCount: 4) == ["二", "四"])
    }

    @Test("並べ替える候補が無ければ足す候補を第 1 候補の後ろに入れる．候補が無ければ空")
    func edges() {
        let result = CandidateReranking.reranked([Self.engine("一"), Self.symbol("→")], adding: [Self.engine("二")], readingCount: 4) { _ in 0 }
        #expect(result.map(\.text) == ["一", "二", "→"])
        #expect(CandidateReranking.reranked([], adding: [Self.engine("一")], readingCount: 4) { _ in 0 }.isEmpty)
    }
}
