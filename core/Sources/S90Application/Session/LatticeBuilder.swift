import S90Domain

/// 読みを文節に分け，文節ごとの候補を集めて文節格子を作る．
///
/// 区切りは，読み全体の第 1 候補(ライブ変換で見えている文)の語の並びから決める(ClauseSplitter)．
/// 格子の 1 段目がライブ変換の表示と同じになり，見比べる手間が出ないため．
/// 語の並びが分からないときは，その文と食い違わない文節の候補のうちいちばん短いもので切る
@MainActor
struct LatticeBuilder {
    let converter: any KanaKanjiConverting
    /// 上の枝(字種)を作るときに，読みに残った英字(英語と判定した語)をかなにするローマ字の表
    var romajiTable: RomajiTable = .standard

    func build(reading: String, focus: InitialFocus = .automatic) -> SegmentLattice {
        let sentence = converter.candidates(for: reading).first { $0.readingCount == reading.count }
        var lattice = SegmentLattice(segments: clauseSegments(of: reading, sentence: sentence)
            ?? segments(of: reading, from: 0, sentence: sentence?.text))
        lattice.focusedIndex = lattice.initialFocus(focus)
        return lattice
    }

    /// 語の並びで文節に分ける．区切りは Zenzai を使わない変換の語の並びから決め(Zenzai が書き換えた候補は語の区切りを持たないことがある)，
    /// 文節ごとに見せる文字は，ライブ変換で見えている文(sentence)と合うものを選ぶ．文節が 1 つにしかならなければ nil
    private func clauseSegments(of reading: String, sentence: Candidate?) -> [SegmentLattice.Segment]? {
        clauseSegmentMakers(of: reading, sentence: sentence)?.map { $0() }
    }

    /// 文節ごとに，その文節を作る手順．文節が 1 つにしかならなければ nil
    private func clauseSegmentMakers(of reading: String, sentence: Candidate?) -> [() -> SegmentLattice.Segment]? {
        let fromSentence = sentence.map { ClauseSplitter.clauses(of: $0.words) } ?? []
        let clauses: [ClauseSplitter.Clause]
        // Zenzai が書き換えた文の語の並びは，語の途中で切れていることがある(てんきですね → 天｜気ですね)．
        // 字だけで語の途中と分かる区切りがあれば使わず，Zenzai を使わない変換の語の並びで分ける
        let cutsWord = zip(fromSentence, fromSentence.dropFirst()).contains { SegmentSplitter.cutsWord(before: $0.text, after: $1.text) }
        if fromSentence.count > 1, !cutsWord, fromSentence.reduce(0, { $0 + $1.readingCount }) == reading.count,
            fromSentence.map(\.text).joined() == sentence?.text {
            clauses = fromSentence
        } else {
            let lengths = ClauseSplitter.clauses(of: converter.segmentationWords(for: reading))
            guard lengths.count > 1, lengths.reduce(0, { $0 + $1.readingCount }) == reading.count else { return nil }
            clauses = align(lengths.map(\.readingCount), reading: reading, sentence: sentence?.text ?? reading)
        }
        var position = 0
        return clauses.map { clause in
            let start = position
            position += clause.readingCount
            return { [self] in
                makeSegment(start: start, length: clause.readingCount, rest: String(reading.dropFirst(start)),
                            preferred: clause.text.isEmpty ? nil : clause.text)
            }
        }
    }

    /// build が文節ごとに求める候補を，1 文節ずつ前もって求める手順．変換器が読みごとに候補をためるので，あとの build が速くなる．
    /// 打鍵が止まったあいだに 1 つずつ動かし，次のキーが来たらやめる(長い文で Space から分岐図が出るまでを短くする)
    func warmingSteps(reading: String) -> [@MainActor () -> Void] {
        let sentence = converter.candidates(for: reading).first { $0.readingCount == reading.count }
        return (clauseSegmentMakers(of: reading, sentence: sentence) ?? []).map { make in { _ = make() } }
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

    /// 注目している文節の長さを 1 文字短く・長くしたら，その文節が何になるか(分岐図の足元に「⇧← 入れ　⇧→ 入れると」と見せる)．
    /// 押す前に結果が分かれば，文節の長さを試しに変えて戻す手間が要らない
    /// 分岐図を出すたびに求めるので，長さを変えた文節だけを作る(後ろの文節は作り直さない．resize と同じ 1 段目になる)
    func resizePreview(_ lattice: SegmentLattice, reading: String) -> (shorter: String?, longer: String?) {
        (resizedText(lattice, reading: reading, longer: false), resizedText(lattice, reading: reading, longer: true))
    }

    /// 注目している文節を 1 文字短く(longer が false)・長くしたときの文節の字．そうできなければ nil
    func resizedText(_ lattice: SegmentLattice, reading: String, longer: Bool) -> String? {
        let segment = lattice.focused
        let length = segment.readingLength + (longer ? 1 : -1)
        guard length >= 1, segment.readingStart + length <= reading.count else { return nil }
        return makeSegment(start: segment.readingStart, length: length, rest: String(reading.dropFirst(segment.readingStart)), preferred: nil).selected.text
    }

    /// 注目している文節の終わりを，前(grow が false)か次(true)の語の切れ目に動かす．
    /// 語の切れ目は Zenzai を使わない変換の語の並び(segmentationWords)から求める．切れ目が無ければ 1 文字動かす
    func resizeToWord(_ lattice: SegmentLattice, grow: Bool, reading: String) -> SegmentLattice {
        let segment = lattice.focused
        let end = segment.readingStart + segment.readingLength
        let boundaries = wordBoundaries(of: reading)
        let target = grow
            ? boundaries.first { $0 > end } ?? min(end + 1, reading.count)
            : boundaries.last { $0 > segment.readingStart && $0 < end } ?? max(end - 1, segment.readingStart + 1)
        return resize(lattice, segmentAt: lattice.focusedIndex, to: target - segment.readingStart, reading: reading)
    }

    /// 語の切れ目の位置(読みの先頭からの文字数)．語の並びが読み全体を覆わなければ空
    func wordBoundaries(of reading: String) -> [Int] {
        let words = converter.segmentationWords(for: reading)
        var position = 0
        let boundaries = words.map { word -> Int in
            position += word.readingCount
            return position
        }
        return position == reading.count ? boundaries : []
    }

    /// 打ち間違いを直したとき，直した部分を含む文節の 2 番目に，打ったままの読みの候補を入れる．
    /// 打ち間違いと決めつけず，分岐図の中で直した文と打ったままの文のどちらも選べるようにするため．
    /// 直した部分が複数の文節にまたがるときは，それらを 1 つの文節にまとめてから入れる
    func addingTyped(_ lattice: SegmentLattice, typedReading: String, reading: String) -> SegmentLattice {
        addingAlternatives(lattice, otherReading: typedReading, reading: reading, origin: .asTyped)
    }

    /// 打ち間違いを「もしかして」と示しているとき，直した部分を含む文節の 2 番目に，直した読みの候補を入れる．
    /// 文全体を直さず，その文節だけ直す・直さないを選べるようにするため
    func addingCorrection(_ lattice: SegmentLattice, correctedReading: String, reading: String) -> SegmentLattice {
        addingAlternatives(lattice, otherReading: correctedReading, reading: reading, origin: .correction)
    }

    /// 読みの一部が違う別の読み(otherReading)の候補を，違う部分を含む文節に入れる．違う部分が複数の文節にまたがるときは 1 つにまとめる
    private func addingAlternatives(_ lattice: SegmentLattice, otherReading: String, reading: String, origin: CandidateOrigin) -> SegmentLattice {
        let typed = Array(otherReading), corrected = Array(reading)
        guard let changed = CorrectedSpan.changedRange(from: otherReading, to: reading) else { return lattice }
        let prefix = changed.lowerBound, changedEnd = changed.upperBound
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
            .map { Candidate(text: $0.text, readingCount: length, origin: origin) }
        additions.append(Candidate(text: typedSlice, readingCount: length, origin: origin))
        for (offset, candidate) in additions.enumerated() where !segment.candidates.contains(where: { $0.text == candidate.text }) {
            segment.candidates.insert(candidate, at: min(1 + offset, segment.candidates.count))
        }
        segment.isConfident = false
        segment.confidenceGap = -.infinity
        result.segments[first] = segment
        return result
    }

    /// index の文節の読みを slice に替える(その場で打ち直す)．ほかの文節は選んだ候補ごと残し，後ろの文節は位置だけずらす．
    /// slice はその読みだけで文節に分ける(長く打ち直せば 2 つ以上の文節になる)．slice が空なら文節を消す．
    /// 注目は打ち直した文節の先頭(消したときは次の文節)に置く
    func replacing(_ lattice: SegmentLattice, segmentAt index: Int, with slice: String) -> SegmentLattice {
        let old = lattice.segments[index]
        let delta = slice.count - old.readingLength
        var replaced: [SegmentLattice.Segment] = []
        if !slice.isEmpty {
            let sentence = converter.candidates(for: slice).first { $0.readingCount == slice.count }
            replaced = (clauseSegments(of: slice, sentence: sentence) ?? segments(of: slice, from: 0, sentence: sentence?.text)).map { segment in
                var segment = segment
                segment.readingStart += old.readingStart
                return segment
            }
        }
        let after = lattice.segments.dropFirst(index + 1).map { segment in
            var segment = segment
            segment.readingStart += delta
            return segment
        }
        let segments = Array(lattice.segments.prefix(index)) + replaced + after
        return SegmentLattice(segments: segments, focusedIndex: min(index, max(segments.count - 1, 0)))
    }

    /// 利用者が入れた区切り(読みの先頭からの文字数)で，必ず文節を分ける
    func splitting(_ lattice: SegmentLattice, at boundaries: [Int], reading: String) -> SegmentLattice {
        var result = lattice
        for boundary in boundaries.sorted() where boundary > 0 && boundary < reading.count {
            guard let index = result.segments.firstIndex(where: { $0.readingStart < boundary && boundary < $0.readingStart + $0.readingLength }) else { continue }
            result = resize(result, segmentAt: index, to: boundary - result.segments[index].readingStart, reading: reading)
        }
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
        segments += following(reading, from: segment.readingStart + length).map { rebuilt in
            decided.first { $0.readingStart == rebuilt.readingStart && $0.readingLength == rebuilt.readingLength } ?? rebuilt
        }
        return SegmentLattice(segments: segments, focusedIndex: index)
    }

    /// start より後ろの読みを文節に分ける．build と同じく，その読みの第 1 候補の語の並びで区切る(clauseSegments)．
    /// 語の並びで区切れなければ，文節の候補で区切る(segments)
    private func following(_ reading: String, from start: Int) -> [SegmentLattice.Segment] {
        let rest = String(reading.dropFirst(start))
        guard !rest.isEmpty else { return [] }
        let sentence = converter.candidates(for: rest).first { $0.readingCount == rest.count }
        guard let clauses = clauseSegments(of: rest, sentence: sentence) else {
            return segments(of: reading, from: start, sentence: sentence?.text)
        }
        return clauses.map { clause in
            var clause = clause
            clause.readingStart += start
            return clause
        }
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
            // 英数字の並び(「python」)の途中では切らない．エンジンの文節は英字 1 文字ずつのことがある
            let latin = rest.prefix(while: Composition.isAlphanumeric).count
            let clause = converter.clauseCandidates(for: rest)
                .filter { $0.readingCount < rest.count && $0.readingCount >= latin && expected?.hasPrefix($0.text) == true }
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
        // 候補はこの文節の読みだけを，ライブ変換と別の変換の状態で Zenzai を使わずに求める(segmentCandidates)．
        // 後ろの読み全体を文節ごとにライブ変換と同じ状態で変換し直していたときは，文節ごとに状態を捨てて変換し直すので，
        // 長い文ほど Space で分岐図が出るまでが延びた(85 キーの文で 0.36 秒)．1 段目は preferred(見えている文)が受け持つ
        let pool = converter.segmentCandidates(for: slice).filter { $0.readingCount == length }
        if let preferred {
            // 文全体の候補の一部はこの文節の候補に無いことがある．そのときも先頭に置く
            append(pool.first { $0.text == preferred } ?? Candidate(text: preferred, readingCount: length, origin: .sentencePart))
        }
        // 文節の先頭の語の候補に，残り(助詞・助動詞など)をつないだものも候補にする．
        // エンジンの文節全体の候補だけでは先頭の語を選び直せないことがある(ごくでしょうが → 語句でしょうが が無い)．
        // 先頭の語の候補の順(エンジンがその語をどれだけ確からしいとみたか)に先に並べ，そのあとに文節全体の候補を並べる．
        // 文節全体の候補の順は，先頭の語の読みを別の語に読み替えたもの(ごく → 石)が上に来ることがあるため
        headWordAlternatives(of: slice).forEach(append)
        pool.forEach(append)
        if candidates.isEmpty {
            append(Candidate(text: slice, readingCount: length, origin: .variant(.hiragana)))
        }
        // 上の枝(ひらがな・カタカナ・半角カタカナ)にあるものは，下の枝に重ねて出さない．第 1 候補(幹)は残す
        let variantTexts = variants(of: slice).map(\.text)
        candidates = candidates.enumerated().filter { $0.offset == 0 || !variantTexts.contains($0.element.text) }.map(\.element)
        let engineCandidates = candidates.filter(\.isFromEngine)
        let best = engineCandidates.first, second = engineCandidates.dropFirst().first
        let confident = SegmentLattice.isConfident(best: best, second: second)
        let gap = best.flatMap { best in second.map { best.score - $0.score } } ?? .infinity
        return SegmentLattice.Segment(readingStart: start, readingLength: length, candidates: candidates,
                                      variants: variants(of: slice), isConfident: confident, confidenceGap: gap)
    }

    /// 文節の先頭の語を別の候補に変え，残りの部分はそのままつないだ候補(ごくでしょうが → 語句でしょうが・極でしょうが)．
    /// 語の区切りは Zenzai を使わない変換の語の並び(segmentationWords)から求める．語が 1 つなら作らない
    private func headWordAlternatives(of slice: String) -> [Candidate] {
        let words = converter.segmentationWords(for: slice)
        guard words.count > 1, let head = words.first, words.reduce(0, { $0 + $1.readingCount }) == slice.count else { return [] }
        let tail = words.dropFirst().map(\.text).joined()
        let headReading = String(slice.prefix(head.readingCount))
        // 先頭の語だけを文脈なしで Zenzai にかけると，ふだんの語が下がる(ごく → 語句 が見えなくなる)ので，辞書の変換の順を使う
        return converter.dictionaryCandidates(for: headReading)
            .filter { $0.readingCount == head.readingCount }
            .prefix(DefaultSettings.headWordAlternativeCount)
            .map { Candidate(text: $0.text + tail, readingCount: slice.count, origin: .combined) }
    }

    /// 上の枝に出す字種．エンジンが出さなくても選べるようにする
    /// 上の枝(ひらがな・カタカナ・半角カタカナ)．英語と判定して英字のまま読みに入れた語(「no」)は，
    /// ローマ字としてかなにしてから作る(上の枝で「の」「ノ」に直せるように)
    func variants(of slice: String) -> [Candidate] {
        let hiragana = Self.kana(of: slice, table: romajiTable)
        let katakana = KanaWidth.katakana(from: hiragana)
        return [
            Candidate(text: hiragana, readingCount: slice.count, origin: .variant(.hiragana)),
            Candidate(text: katakana, readingCount: slice.count, origin: .variant(.katakana)),
            Candidate(text: KanaWidth.halfwidthKatakana(from: katakana), readingCount: slice.count, origin: .variant(.halfwidthKatakana)),
        ]
    }

    /// 英小文字の並びを，ローマ字としてかなにする．かなにしきれない並び(ローマ字として読めない)は英字のまま残す．
    /// 大文字を含む並び(Shift で打った「API」)は打ったとおりの英字なので変えない
    static func kana(of text: String, table: RomajiTable) -> String {
        var result = ""
        var run = ""
        func flush() {
            guard !run.isEmpty else { return }
            var composition = Composition(table: table)
            run.forEach { composition.insertRomaji($0) }
            let kana = composition.conversionReading
            result += kana.contains(where: \.isASCII) ? run : kana
            run = ""
        }
        for (index, character) in text.enumerated() {
            if character.isASCII, character.isLetter {
                run.append(character)
                let isLast = index == text.count - 1
                let next = isLast ? nil : text[text.index(text.startIndex, offsetBy: index + 1)]
                guard next.map({ $0.isASCII && $0.isLetter }) != true else { continue }
                if run.contains(where: \.isUppercase) { result += run; run = "" } else { flush() }
            } else {
                result.append(character)
            }
        }
        flush()
        return result
    }
}
