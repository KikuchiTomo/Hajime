import S90Domain
import Testing

@Suite("文節を区切る位置")
struct SegmentSplitterTests {
    private func word(_ text: String, _ count: Int) -> Candidate.Word {
        Candidate.Word(text: text, readingCount: count)
    }

    // 語の並びは s90-playground --words で見た本物の変換器の結果
    @Test("区切れる位置は 1 文字ごとではなく，意味のある切れ目だけ", arguments: [
        ("問題がある", "もんだいがある", [("問題がある", 7)], [4, 5], ["問題", "が", "ある"]),
        ("一度ログアウトして", "いちどろぐあうとして", [("一度", 3), ("ログアウト", 5), ("し", 1), ("て", 1)], [3, 8], ["一度", "ログアウト", "して"]),
        ("それは問題があると思う", "それはもんだいがあるとおもう", [("それ", 2), ("は問題", 5), ("があると思う", 7)], [2, 3, 7, 8, 11],
         ["それ", "は", "問題", "が", "あると", "思う"]),
        ("書いて", "かいて", [("書いて", 3)], [], ["書いて"]),
    ])
    func meaningfulBoundaries(shown: String, reading: String, words: [(String, Int)], positions: [Int], pieces: [String]) {
        let split = SegmentSplitter.split(shown: shown, reading: reading, words: words.map { word($0.0, $0.1) })
        #expect(split.positions == positions)
        #expect(split.pieces == pieces)
    }

    @Test("英字や漢字は前後の仮名で読みを受け持つ(「Swift｜で｜書く」「問題｜が｜或る」)")
    func alignsAroundKana() {
        let swift = SegmentSplitter.split(shown: "Swiftで書く", reading: "すいふとでかく", words: [word("スイフト", 4), word("で", 1), word("書く", 2)])
        #expect(swift.positions == [4, 5])
        #expect(swift.pieces == ["Swift", "で", "書く"])
        let other = SegmentSplitter.split(shown: "問題が或る", reading: "もんだいがある", words: [word("問題がある", 7)])
        #expect(other.pieces == ["問題", "が", "或る"])
    }

    @Test("見えている字と読みを突き合わせられなければ，語の並びの切れ目で読みを分ける")
    func fallsBackToWords() {
        // 見えている仮名(「の」)が読みに無い
        let split = SegmentSplitter.split(shown: "東京の", reading: "とうきょうと", words: [word("東京", 5), word("と", 1)])
        #expect(split.positions == [5])
        #expect(split.pieces == ["とうきょう", "と"])
    }

    @Test("区切れる位置は 9 個まで．あとは最後にまとめる")
    func atMostNine() {
        let shown = String(repeating: "亜が", count: 10)
        let split = SegmentSplitter.split(shown: shown, reading: String(repeating: "あが", count: 10), words: [])
        #expect(split.positions.count == 9)
        #expect(split.pieces.count == 10)
        #expect(split.pieces.joined() == shown)
    }
}
