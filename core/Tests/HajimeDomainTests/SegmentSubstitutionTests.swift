import HajimeDomain
import Testing

@Suite("文節を 1 か所だけ替えた文")
struct SegmentSubstitutionTests {
    private func segment(_ start: Int, _ texts: [String], length: Int, gap: Double) -> SegmentLattice.Segment {
        SegmentLattice.Segment(readingStart: start, readingLength: length,
                               candidates: texts.enumerated().map { Candidate(text: $1, readingCount: length, origin: .engine(id: start * 10 + $0)) },
                               isConfident: false, confidenceGap: gap)
    }

    @Test("候補の順位ごとに，迷う文節から 1 か所だけ替えた文を並べる")
    func ordersByUncertainty() {
        let lattice = SegmentLattice(segments: [
            segment(0, ["Pythonで", "パイソンで", "パイ損で"], length: 5, gap: 2),
            segment(5, ["プログラムを"], length: 6, gap: .infinity),
            segment(11, ["加工", "書こう", "下降"], length: 3, gap: 0.5),
        ])
        let sentences = SegmentSubstitution.sentences(from: lattice, perSegment: 2).map(\.text)
        #expect(sentences == ["Pythonでプログラムを書こう", "パイソンでプログラムを加工", "Pythonでプログラムを下降", "パイ損でプログラムを加工"])
    }

    @Test("替えた文を確定すると，文節ごとのエンジンの候補を学ぶ")
    func learnsParts() {
        let lattice = SegmentLattice(segments: [segment(0, ["手紙を"], length: 4, gap: .infinity), segment(4, ["加工", "書こう"], length: 3, gap: 0)])
        let sentence = SegmentSubstitution.sentences(from: lattice, perSegment: 1).first
        #expect(sentence?.text == "手紙を書こう")
        #expect(sentence?.readingCount == 7)
        #expect(sentence?.learnedParts.map(\.text) == ["手紙を", "書こう"])
    }

    @Test("文節が 1 つなら作らない")
    func singleSegment() {
        let lattice = SegmentLattice(segments: [segment(0, ["加工", "書こう"], length: 3, gap: 0)])
        #expect(SegmentSubstitution.sentences(from: lattice, perSegment: 2).isEmpty)
    }

    @Test("文全体の候補の 2 番目から，替えた文と交互に並べ，同じ字は先のものだけ残す")
    func interleaves() {
        func candidates(_ texts: [String]) -> [Candidate] { texts.map { Candidate(text: $0, readingCount: 3, origin: .combined) } }
        let merged = SegmentSubstitution.interleave(candidates(["A", "B", "C", "D"]), with: candidates(["X", "B", "Y"]))
        #expect(merged.map(\.text) == ["A", "X", "B", "C", "Y", "D"])
    }
}
