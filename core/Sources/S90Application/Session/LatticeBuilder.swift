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

    /// 語の並びで文節に分ける．区切りは Zenzai を使わない変換の語の並びから決め(Zenzai が書き換えた候補は語の区切りを持たないことがある)，
    /// 文節ごとに見せる文字は，ライブ変換で見えている文(sentence)と合うものを選ぶ．文節が 1 つにしかならなければ nil
    private func clauseSegments(of reading: String, sentence: Candidate?) -> [SegmentLattice.Segment]? {
        let fromSentence = sentence.map { ClauseSplitter.clauses(of: $0.words) } ?? []
        let clauses: [ClauseSplitter.Clause]
        if fromSentence.count > 1, fromSentence.reduce(0, { $0 + $1.readingCount }) == reading.count,
            fromSentence.map(\.text).joined() == sentence?.text {
            clauses = fromSentence
        } else {
            let lengths = ClauseSplitter.clauses(of: converter.segmentationWords(for: reading))
            guard lengths.count > 1, lengths.reduce(0, { $0 + $1.readingCount }) == reading.count else { return nil }
            clauses = align(lengths.map(\.readingCount), reading: reading, sentence: sentence?.text ?? reading)
        }
        var position = 0
        return clauses.map { clause in
            let rest = String(reading.dropFirst(position))
            defer { position += clause.readingCount }
            return makeSegment(start: position, length: clause.readingCount, rest: rest, preferred: clause.text.isEmpty ? nil : clause.text)
        }
    }

    /// 読みの長さの並びに，文(sentence)の文字を先頭から割り当てる．
    /// 各文節の候補のうち文の続きと一致するもの，または文の続きがその読みのかなそのものなら，それを見せる文字にする．
    /// 合うものが無くなったら，そこから後ろは文節ごとの第 1 候補にする(text を空にする)
    private func align(_ lengths: [Int], reading: String, sentence: String) -> [ClauseSplitter.Clause] {
        var rest = Substring(sentence)
        var position = 0
        var aligned = true
        return lengths.map { length in
            let slice = String(reading.dropFirst(position).prefix(length))
            position += length
            guard aligned else { return ClauseSplitter.Clause(text: "", readingCount: length) }
            let options = converter.candidates(for: slice).filter { $0.readingCount == length }.map(\.text) + [slice, KanaWidth.katakana(from: slice)]
            // 長いものから試す(「天気ですね」と「天気」のように前の部分が重なるとき)
            if let match = options.sorted(by: { $0.count > $1.count }).first(where: { rest.hasPrefix($0) }) {
                rest = rest.dropFirst(match.count)
                return ClauseSplitter.Clause(text: match, readingCount: length)
            }
            aligned = false
            return ClauseSplitter.Clause(text: "", readingCount: length)
        }
    }

    /// 注目している文節の 3 番目に，文節の長さを変えた候補(次の文節とつなげたもの，短く区切ったもの)を入れる．
    /// Shift+←→ を知らなくても，候補を選ぶのと同じ操作で区切りを直せるようにするため．ほかの文節からは取り除く
    func withResizeOptions(_ lattice: SegmentLattice, reading: String) -> SegmentLattice {
        var result = lattice
        for index in result.segments.indices {
            result.segments[index].candidates.removeAll { if case .resized = $0.origin { true } else { false } }
            if case .candidate(let choice) = result.segments[index].choice, choice >= result.segments[index].candidates.count {
                result.segments[index].choice = .candidate(0)
            }
        }
        let index = result.focusedIndex
        let segment = result.segments[index]
        let rest = String(reading.dropFirst(segment.readingStart))
        var options: [Candidate] = []
        if index + 1 < result.segments.count {
            let length = segment.readingLength + result.segments[index + 1].readingLength
            options.append(resizedCandidate(rest: rest, length: length))
        }
        let inner = ClauseSplitter.clauses(of: converter.segmentationWords(for: String(rest.prefix(segment.readingLength))))
        if inner.count > 1, let first = inner.first, first.readingCount < segment.readingLength {
            options.append(resizedCandidate(rest: rest, length: first.readingCount))
        }
        let position = min(2, segment.candidates.count)
        result.segments[index].candidates.insert(contentsOf: options.filter { option in
            !segment.candidates.contains { $0.text == option.text }
        }, at: position)
        if case .candidate(let choice) = segment.choice, choice >= position {
            result.segments[index].choice = .candidate(choice + options.count)
        }
        return result
    }

    private func resizedCandidate(rest: String, length: Int) -> Candidate {
        let slice = String(rest.prefix(length))
        let text = converter.candidates(for: slice).first { $0.readingCount == length }?.text ?? slice
        return Candidate(text: text, readingCount: length, origin: .resized(length))
    }

    /// 打ち間違いを直したとき，直した部分を含む文節の 2 番目に，打ったままの読みの候補を入れる．
    /// 打ち間違いと決めつけず，分岐図の中で直した文と打ったままの文のどちらも選べるようにするため．
    /// 直した部分が複数の文節にまたがるときは，それらを 1 つの文節にまとめてから入れる
    func addingTyped(_ lattice: SegmentLattice, typedReading: String, reading: String) -> SegmentLattice {
        let typed = Array(typedReading), corrected = Array(reading)
        let prefix = zip(typed, corrected).prefix { $0 == $1 }.count
        let suffix = zip(typed.reversed(), corrected.reversed()).prefix { $0 == $1 }.count
        let common = min(suffix, min(typed.count, corrected.count) - prefix)
        let changedEnd = max(corrected.count - common, prefix + 1)
        guard let first = lattice.segments.firstIndex(where: { $0.readingStart + $0.readingLength > prefix }),
            let last = lattice.segments.lastIndex(where: { $0.readingStart < changedEnd }) else { return lattice }
        var result = lattice
        if last > first {
            let end = lattice.segments[last].readingStart + lattice.segments[last].readingLength
            result = resize(result, segmentAt: first, to: end - lattice.segments[first].readingStart, reading: reading)
        }
        var segment = result.segments[first]
        let start = segment.readingStart, length = segment.readingLength
        // 文節の読みの，直した部分を打ったままの読みに置き換える
        let typedEnd = start + length + typed.count - corrected.count
        guard start <= prefix, typedEnd > start, typedEnd <= typed.count else { return lattice }
        let typedSlice = String(typed[start..<typedEnd])
        var additions = converter.candidates(for: typedSlice).filter { $0.readingCount == typedSlice.count }.prefix(2)
            .map { Candidate(text: $0.text, readingCount: length, origin: .asTyped) }
        additions.append(Candidate(text: typedSlice, readingCount: length, origin: .asTyped))
        for (offset, candidate) in additions.enumerated() where !segment.candidates.contains(where: { $0.text == candidate.text }) {
            segment.candidates.insert(candidate, at: min(1 + offset, segment.candidates.count))
        }
        segment.isConfident = false
        result.segments[first] = segment
        result.focusedIndex = first
        return result
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
        // 上の枝(ひらがな・カタカナ・半角カタカナ)にあるものは，下の枝に重ねて出さない．第 1 候補(幹)は残す
        let variants = Self.variants(of: slice).map(\.text)
        candidates = candidates.enumerated().filter { $0.offset == 0 || !variants.contains($0.element.text) }.map(\.element)
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
