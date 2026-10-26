import S90Domain
import Testing

@Suite("直した語句の位置")
struct CorrectedSpanTests {
    @Test("直す前と後の読みの違う部分", arguments: [
        ("きょうのてんきはようですね", "きょうのてんきはよいですね", 9..<10),
        // 文字を消した直しは，消した位置の次の 1 文字
        ("こおんにちは", "こんにちは", 1..<2),
        // 文字を足した直し
        ("こにちは", "こんにちは", 1..<2),
        // 末尾の文字を消した直しは，前の 1 文字
        ("ですねえ", "ですね", 2..<3),
    ])
    func changedRange(typed: String, corrected: String, expected: Range<Int>) {
        #expect(CorrectedSpan.changedRange(from: typed, to: corrected) == expected)
    }

    @Test("読みが同じなら違う部分は無い")
    func sameReading() {
        #expect(CorrectedSpan.changedRange(from: "よい", to: "よい") == nil)
    }

    private let sentence = Candidate(text: "今日の天気は良いですね", readingCount: 13, origin: .engine(id: 0), words: [
        .init(text: "今日", readingCount: 3), .init(text: "の", readingCount: 1), .init(text: "天気", readingCount: 3),
        .init(text: "は", readingCount: 1), .init(text: "良い", readingCount: 2), .init(text: "です", readingCount: 2),
        .init(text: "ね", readingCount: 1),
    ])

    @Test("候補の語の並びで，直した部分にかかる語だけを分ける")
    func piecesByWords() {
        let pieces = CorrectedSpan.pieces(of: sentence, reading: "きょうのてんきはよいですね", changed: 9..<10)
        #expect(pieces == [.init("今日の天気は", isCorrected: false), .init("良い", isCorrected: true), .init("ですね", isCorrected: false)])
        #expect(CorrectedSpan.textRange(of: pieces) == 6..<8)
    }

    @Test("語の並びが読みと合わなければ，候補全体を 1 つにする")
    func fallbackToWhole() {
        var broken = sentence
        broken.words.removeLast()
        #expect(CorrectedSpan.pieces(of: broken, reading: "きょうのてんきはよいですね", changed: 9..<10) == [.init("今日の天気は良いですね", isCorrected: true)])
        broken.words = []
        #expect(CorrectedSpan.pieces(of: broken, reading: "きょうのてんきはよいですね", changed: 9..<10) == [.init("今日の天気は良いですね", isCorrected: true)])
    }

    @Test("候補が読みの一部だけを変換し，直した部分にかからなければ印を付けない")
    func partialCandidate() {
        let head = Candidate(text: "今日の", readingCount: 4, origin: .engine(id: 1), words: [.init(text: "今日", readingCount: 3), .init(text: "の", readingCount: 1)])
        let pieces = CorrectedSpan.pieces(of: head, reading: "きょうのてんきはよいですね", changed: 9..<10)
        #expect(pieces == [.init("今日の", isCorrected: false)])
        #expect(CorrectedSpan.textRange(of: pieces) == nil)
    }

    @Test("見せる文字の末尾が候補と違う(打っている途中の語をかなのまま見せる)ときは，違う部分から後ろを 1 つにまとめる")
    func aligningToShown() {
        let pieces: [CorrectedSpan.Piece] = [.init("今日の天気は", isCorrected: false), .init("良い", isCorrected: true), .init("です根", isCorrected: false)]
        #expect(CorrectedSpan.aligning(pieces, to: "今日の天気は良いですね")
            == [.init("今日の天気は", isCorrected: false), .init("良い", isCorrected: true), .init("ですね", isCorrected: false)])
        let tail: [CorrectedSpan.Piece] = [.init("今日は", isCorrected: false), .init("雷", isCorrected: true)]
        #expect(CorrectedSpan.aligning(tail, to: "今日はらい") == [.init("今日は", isCorrected: false), .init("らい", isCorrected: true)])
    }
}
