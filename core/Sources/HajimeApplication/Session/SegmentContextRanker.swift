import HajimeDomain

/// 文節の候補を，前後の語とのつながりで並べ替える．
///
/// 文節の候補はその文節の読みだけで求めるので，前後に何があるかを知らない(「を」のあとの「かこう」でも「加工」が先に来る)．
/// そこで，次の 2 つの変換で文節の読みの範囲がどの字になったかを取り出し，出た順に文節の候補の先頭へ集める．
/// 1. 読み全体の候補(ライブ変換で見えている文と同じ変換)．文全体のつながりで決まる
/// 2. 文節の前後 1 語ずつを含めた読みの変換(Zenzai を使わない)．文全体の候補には同じ文節の別の字があまり出ないので補う．
///    前後の語の字は問わない(見えている字に限ると，前の文節を選び直したあとに古い字で絞ることになり，かえって順が悪くなった)
/// 並べ替えるのは先頭の count 個までで，残りは元の順のまま．文節の読みだけの候補に無い字は，その位置に足す
@MainActor
struct SegmentContextRanker {
    let converter: any KanaKanjiConverting
    /// 文脈で先頭へ集める候補の数
    var count = DefaultSettings.contextualSegmentCandidateCount
    /// 前後 1 語ずつを含めた読みの変換も使うか．使わなければ読み全体の候補(求めてあるもの)だけで並べるので，新たに変換しない
    var usesNeighborConversion = true

    /// reading の start から length 文字の文節の候補 pool を並べ替える．fixed 個の先頭(幹)は動かさない
    func ranked(_ pool: [Candidate], start: Int, length: Int, reading: String, fixed: Int = 0) -> [Candidate] {
        guard count > 0, pool.count > fixed + 1, start >= 0, length > 0, start + length <= reading.count else { return pool }
        let texts = contextualTexts(start: start, length: length, reading: reading)
        guard !texts.isEmpty else { return pool }
        let head = Array(pool.prefix(fixed))
        var rest = Array(pool.dropFirst(fixed))
        var moved: [Candidate] = []
        for text in texts where moved.count < count && !head.contains(where: { $0.text == text }) {
            if let index = rest.firstIndex(where: { $0.text == text }) {
                moved.append(rest.remove(at: index))
            } else {
                // 文節の読みだけの候補に無い字(前後があって初めて出る字)も選べるようにする．学習には使わない
                moved.append(Candidate(text: text, readingCount: length, origin: .sentencePart))
            }
        }
        // 文脈の変換から持ち込んだ字にも崩れた書き方(じゅっ分・コの)があるので，除き直す
        return BrokenSpellings.cleaned(head + moved + rest)
    }

    /// 文脈を含めた変換で，文節の読みの範囲になった字．読み全体の候補から取り出したものを先に，前後 1 語ずつを含めた変換のものをあとに，
    /// よいものから順に重なりなく
    func contextualTexts(start: Int, length: Int, reading: String) -> [String] {
        let range = start..<(start + length)
        let characters = Array(reading)
        let slice = String(characters[range])
        var seen = Set<String>()
        var texts: [String] = []
        func collect(_ candidates: [Candidate], reading: String, range: Range<Int>) {
            // 読みで引いた絵文字は文脈で決まった字ではないので集めない(置き場所は EmojiPlacement が決める)
            for candidate in candidates where candidate.readingCount == reading.count && candidate.commandID == nil && candidate.origin != .emoji {
                // 打ち間違いを直した候補などは読みが違う(「かこう」に「書く」)ので，文節の読みと食い違う字は使わない
                guard let text = CandidateSpan.text(of: candidate, in: range, reading: reading),
                      CandidateSpan.isConsistent(text, with: slice), seen.insert(text).inserted else { continue }
                texts.append(text)
            }
        }
        let sentences = converter.candidates(for: reading)
        collect(sentences, reading: reading, range: range)
        if usesNeighborConversion, let window = neighborWindow(of: range, in: reading, sentence: sentences.first { $0.readingCount == reading.count }) {
            let windowReading = String(characters[window])
            let shifted = (range.lowerBound - window.lowerBound)..<(range.upperBound - window.lowerBound)
            collect(converter.segmentCandidates(for: windowReading), reading: windowReading, range: shifted)
        }
        return texts
    }

    /// 文節の前後 1 語ずつを含めた読みの範囲．語の切れ目は見えている文(読み全体の第 1 候補)の語の並びから求め，
    /// 語の並びが無ければ Zenzai を使わない変換の語の並びから求める(読み全体をもう一度変換するので遅い)．
    /// 前後に語が無い(読み全体が 1 つの文節)，または語の並びが読み全体を覆わなければ nil
    private func neighborWindow(of range: Range<Int>, in reading: String, sentence: Candidate?) -> Range<Int>? {
        let shownWords = sentence?.words ?? []
        let words = shownWords.reduce(0, { $0 + $1.readingCount }) == reading.count && !shownWords.isEmpty ? shownWords : converter.segmentationWords(for: reading)
        var boundaries = [0]
        var position = 0
        for word in words {
            position += word.readingCount
            boundaries.append(position)
        }
        guard boundaries.last == reading.count else { return nil }
        let lower = boundaries.last { $0 < range.lowerBound } ?? range.lowerBound
        let upper = boundaries.first { $0 > range.upperBound } ?? range.upperBound
        guard lower < range.lowerBound || upper > range.upperBound else { return nil }
        return lower..<upper
    }
}
