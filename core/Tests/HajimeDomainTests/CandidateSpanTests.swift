import HajimeDomain
import Testing

@Suite("候補から読みの範囲の字を切り出す")
struct CandidateSpanTests {
    private func candidate(_ words: [(String, Int)]) -> Candidate {
        Candidate(text: words.map(\.0).joined(), readingCount: words.reduce(0) { $0 + $1.1 }, origin: .combined,
                  words: words.map { Candidate.Word(text: $0.0, readingCount: $0.1) })
    }

    @Test("語の切れ目が範囲の端にあれば，その間の語をつなぐ")
    func wordBoundaries() {
        let sentence = candidate([("手紙", 3), ("を", 1), ("書こう", 3)])
        #expect(CandidateSpan.text(of: sentence, in: 4..<7, reading: "てがみをかこう") == "書こう")
        #expect(CandidateSpan.text(of: sentence, in: 0..<4, reading: "てがみをかこう") == "手紙を")
    }

    @Test("端が語の途中でも，外の部分がかなのまま付いていれば切る．付いていなければ切れない")
    func splitsKanaEdge() {
        let joined = candidate([("を書こう", 4)])
        #expect(CandidateSpan.text(of: joined, in: 1..<4, reading: "をかこう") == "書こう")
        let kanji = candidate([("手紙", 3)])
        #expect(CandidateSpan.text(of: kanji, in: 1..<3, reading: "てがみ") == nil)
    }

    @Test("語の並びが読み全体を覆わなければ切り出さない")
    func incompleteWords() {
        let partial = candidate([("手紙", 3)])
        #expect(CandidateSpan.text(of: partial, in: 0..<3, reading: "てがみを") == nil)
    }

    @Test("かなが読みのその位置にあり，漢字などが読みの 1 文字以上に当たれば，読みと食い違わない")
    func consistency() {
        #expect(CandidateSpan.isConsistent("書こう", with: "かこう"))
        #expect(CandidateSpan.isConsistent("プログラムを書こう", with: "ぷろぐらむをかこう"))
        #expect(CandidateSpan.isConsistent("Pythonで", with: "ぱいそんで"))
        #expect(CandidateSpan.isConsistent("三ヶ月", with: "さんかげつ"))
        #expect(!CandidateSpan.isConsistent("書く", with: "かこう"))
        #expect(!CandidateSpan.isConsistent("プログラムを書く", with: "ぷろぐらむをかこう"))
        #expect(!CandidateSpan.isConsistent("かく", with: "かこう"))
    }
}
