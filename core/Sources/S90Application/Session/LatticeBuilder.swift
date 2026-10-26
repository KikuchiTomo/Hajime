import S90Domain

/// 読みを文節に分け，文節ごとの候補を集めて文節格子を作る．
///
/// 区切りは，読み全体の第 1 候補(ライブ変換で見えている文)の語の並びから決める(ClauseSplitter)．
/// 格子の 1 段目がライブ変換の表示と同じになり，見比べる手間が出ないため．
/// 語の並びが分からないときは，その文と食い違わない文節の候補のうちいちばん短いもので切る
@MainActor
struct LatticeBuilder {
    let converter: any KanaKanjiConverting

    func build(reading: String) -> SegmentLattice {
        let sentence = converter.candidates(for: reading).first { $0.readingCount == reading.count }
        var lattice = SegmentLattice(segments: clauseSegments(of: reading, sentence: sentence)
            ?? segments(of: reading, from: 0, sentence: sentence?.text))
        lattice.focusedIndex = lattice.initialFocus
        return lattice
    }

    /// 第 1 候補の語の並びで文節に分ける．語の読みの長さの合計が読みと合わなければ nil
    private func clauseSegments(of reading: String, sentence: Candidate?) -> [SegmentLattice.Segment]? {
        guard let sentence else { return nil }
        let clauses = ClauseSplitter.clauses(of: sentence.words)
        guard clauses.count > 1, clauses.reduce(0, { $0 + $1.readingCount }) == reading.count,
            clauses.map(\.text).joined() == sentence.text else { return nil }
        var position = 0
        return clauses.map { clause in
            let rest = String(reading.dropFirst(position))
            defer { position += clause.readingCount }
            return makeSegment(start: position, length: clause.readingCount, rest: rest, preferred: clause.text)
        }
    }

    /// index の文節の長さを length に変え，それより後ろを分け直す(Shift+←→)．
    /// 分け直したあとも読みの範囲が同じ文節は，利用者が選び直したものを残す(人が決めた文節は書き換えない)
    func resize(_ lattice: SegmentLattice, segmentAt index: Int, to length: Int, reading: String) -> SegmentLattice {
        let segment = lattice.segments[index]
        let available = reading.count - segment.readingStart
        let length = min(max(length, 1), available)
        guard length != segment.readingLength else { return lattice }
        let rest = String(reading.dropFirst(segment.readingStart))
        var segments = Array(lattice.segments.prefix(index))
        segments.append(makeSegment(start: segment.readingStart, length: length, rest: rest, preferred: nil))
        // 区切りを変えた後ろは，その読みだけで求め直す
        let decided = lattice.segments.dropFirst(index + 1).filter(\.isDecided)
        segments += self.segments(of: reading, from: segment.readingStart + length, sentence: nil).map { rebuilt in
            decided.first { $0.readingStart == rebuilt.readingStart && $0.readingLength == rebuilt.readingLength } ?? rebuilt
        }
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
        if candidates.isEmpty {
            append(Candidate(text: slice, readingCount: length, origin: .variant(.hiragana)))
        }
        let engineCandidates = candidates.filter(\.isFromEngine)
        let confident = SegmentLattice.isConfident(best: engineCandidates.first, second: engineCandidates.dropFirst().first)
        return SegmentLattice.Segment(readingStart: start, readingLength: length, candidates: candidates,
                                      variants: Self.variants(of: slice), isConfident: confident)
    }

    /// 上の枝に出す字種．エンジンが出さなくても選べるようにする
    static func variants(of slice: String) -> [Candidate] {
        let katakana = KanaWidth.katakana(from: slice)
        return [
            Candidate(text: slice, readingCount: slice.count, origin: .variant(.hiragana)),
            Candidate(text: katakana, readingCount: slice.count, origin: .variant(.katakana)),
            Candidate(text: KanaWidth.halfwidthKatakana(from: katakana), readingCount: slice.count, origin: .variant(.halfwidthKatakana)),
        ]
    }
}
