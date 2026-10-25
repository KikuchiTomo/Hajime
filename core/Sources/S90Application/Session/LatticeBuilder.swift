import S90Domain

/// 読みを文節に分け，文節ごとの候補を集めて文節格子を作る．
///
/// 区切りは，読み全体の第 1 候補(ライブ変換で見えている文)を先頭から切る位置に合わせる．
/// 切る位置は，その文と食い違わない文節の候補のうちいちばん短いもの．
/// 格子の 1 段目がライブ変換の表示と同じになり，見比べる手間が出ないため．
@MainActor
struct LatticeBuilder {
    let converter: any KanaKanjiConverting

    func build(reading: String) -> SegmentLattice {
        let sentence = converter.candidates(for: reading).first { $0.readingCount == reading.count }?.text
        return SegmentLattice(segments: segments(of: reading, from: 0, sentence: sentence))
    }

    /// index の文節の長さを length に変え，それより後ろを分け直す(Shift+←→)
    func resize(_ lattice: SegmentLattice, segmentAt index: Int, to length: Int, reading: String) -> SegmentLattice {
        let segment = lattice.segments[index]
        let available = reading.count - segment.readingStart
        let length = min(max(length, 1), available)
        guard length != segment.readingLength else { return lattice }
        let rest = String(reading.dropFirst(segment.readingStart))
        var segments = Array(lattice.segments.prefix(index))
        segments.append(makeSegment(start: segment.readingStart, length: length, rest: rest, preferred: nil))
        // 区切りを変えた後ろは，その読みだけで求め直す
        segments += self.segments(of: reading, from: segment.readingStart + length, sentence: nil)
        return SegmentLattice(segments: segments, focusedIndex: index)
    }

    /// - Parameter sentence: 読み全体の第 1 候補のうち，start より後ろに当たる文字列．
    ///   これを先頭から文節に切っていくので，格子の 1 段目はライブ変換の表示と同じになる
    private func segments(of reading: String, from start: Int, sentence: String?) -> [SegmentLattice.Segment] {
        var result: [SegmentLattice.Segment] = []
        var position = start
        var sentence = sentence
        while position < reading.count {
            let rest = String(reading.dropFirst(position))
            let expected = sentence ?? converter.candidates(for: rest).first { $0.readingCount == rest.count }?.text
            let clause = converter.clauseCandidates(for: rest)
                .filter { $0.readingCount < rest.count && expected?.hasPrefix($0.text) == true }
                .min { $0.readingCount < $1.readingCount }
            let length = clause?.readingCount ?? rest.count
            result.append(makeSegment(start: position, length: length, rest: rest, preferred: clause?.text ?? expected))
            position += length
            sentence = clause.flatMap { clause in expected.map { String($0.dropFirst(clause.text.count)) } }
        }
        return result
    }

    /// rest の先頭 length 文字を 1 つの文節とし，同じ長さの候補を集める．preferred があれば先頭に置く
    private func makeSegment(start: Int, length: Int, rest: String, preferred: String?) -> SegmentLattice.Segment {
        let slice = String(rest.prefix(length))
        var candidates: [Candidate] = []
        func append(_ candidate: Candidate) {
            if !candidates.contains(where: { $0.text == candidate.text }) { candidates.append(candidate) }
        }
        let pool = converter.clauseCandidates(for: rest).filter { $0.readingCount == length }
            + converter.candidates(for: slice).filter { $0.readingCount == length }
        if let preferred {
            // 文全体の候補の一部はこの文節の候補に無いことがある．そのときも先頭に置く
            append(pool.first { $0.text == preferred } ?? Candidate(text: preferred, readingCount: length, origin: .sentencePart))
        }
        pool.forEach(append)
        // ひらがなとカタカナは，エンジンが出さなくても選べるようにする
        append(Candidate(text: slice, readingCount: length, origin: .variant(.hiragana)))
        append(Candidate(text: KanaWidth.katakana(from: slice), readingCount: length, origin: .variant(.katakana)))
        let engineCandidates = candidates.filter { if case .engine = $0.origin { true } else { false } }
        let confident = SegmentLattice.isConfident(best: engineCandidates.first, second: engineCandidates.dropFirst().first)
        return SegmentLattice.Segment(readingStart: start, readingLength: length, candidates: candidates, isConfident: confident)
    }
}
