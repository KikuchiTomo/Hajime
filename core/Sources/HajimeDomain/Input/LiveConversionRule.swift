/// ライブ変換で，打っている途中に何を見せるか．
///
/// 打っている途中の語は，まだ続きを打つかもしれない(「らい」のあとに「ぶ」が来て「ライブ」になる)．
/// そこで打鍵が続くあいだは，短い読みと，末尾の短い語をかなのまま見せる(「らい」を「雷」にしない)．
/// 打鍵が止まったとき，Space・Enter・句読点のときは，変換した文をそのまま見せる(settled)．
/// 区切りや休止で見せ方を変えるのは，作業の切れ目で変化を出すほうが妨げにならないため
/// (Iqbal & Bailey 2005．docs/dev/research/list-free-input.md)
public struct LiveConversionRule: Sendable {
    public init() {}

    /// - Parameters:
    ///   - candidate: 読み全体の第 1 候補
    ///   - reading: 読み(かな)
    ///   - settled: 打鍵が止まったか．止まっていれば変換した文をそのまま見せる
    public func display(of candidate: Candidate, reading: String, settled: Bool) -> String {
        guard !settled else { return candidate.text }
        if reading.count < DefaultSettings.liveConversionMinimumLength {
            return reading
        }
        guard let word = candidate.trailingWord,
            word.readingCount <= DefaultSettings.liveConversionHeldWordLength,
            word.readingCount <= reading.count, word.textCount <= candidate.text.count else { return candidate.text }
        let tail = String(reading.suffix(word.readingCount))
        let shown = String(candidate.text.suffix(word.textCount))
        // かなのままの語(助詞など)はそのまま
        guard shown != tail else { return candidate.text }
        return String(candidate.text.dropLast(word.textCount)) + tail
    }

    /// 打っている途中の文(candidate)の先頭を，前に打鍵が止まったときに見せた文(settled)に合わせる．
    /// 止まったときは時間をかけて求める(Zenzai)ので，打っている途中の速い変換とは先頭の語が違うことがある(打って ↔ 売って)．
    /// 打つたびに先頭が入れ替わるとちらつくので，両方の語の区切りが合う位置までは止まったときの文を使う．
    /// settled の読みが reading の先頭でないとき，語の区切りが分からないとき，合う区切りが無いときは candidate の文のまま
    /// - Parameters:
    ///   - candidate: 読み全体の第 1 候補(打っている途中の速い変換)
    ///   - reading: 読み(かな)
    ///   - settled: 前に打鍵が止まったときの読み全体の第 1 候補と，その読み
    public func stabilized(_ candidate: Candidate, reading: String, settled: (candidate: Candidate, reading: String)?) -> Candidate {
        guard let settled, settled.reading.count < reading.count, reading.hasPrefix(settled.reading),
              let before = Self.boundaries(of: settled.candidate), let now = Self.boundaries(of: candidate) else { return candidate }
        // 両方の文で語が切れる，いちばん後ろの読みの位置
        guard let shared = before.keys.filter({ $0 > 0 && now[$0] != nil }).max(),
              let settledEnd = before[shared], let currentEnd = now[shared] else { return candidate }
        var result = candidate
        result.text = String(settled.candidate.text.prefix(settledEnd)) + String(candidate.text.dropFirst(currentEnd))
        result.words = Self.words(of: settled.candidate, upTo: shared) + Self.words(of: candidate, from: shared)
        return result
    }

    /// 読みの先頭から position 文字までの語
    private static func words(of candidate: Candidate, upTo position: Int) -> [Candidate.Word] {
        var reading = 0
        return candidate.words.prefix { word in
            reading += word.readingCount
            return reading <= position
        }
    }

    /// 読みの position 文字目から後ろの語
    private static func words(of candidate: Candidate, from position: Int) -> [Candidate.Word] {
        var reading = 0
        return Array(candidate.words.drop { word in
            reading += word.readingCount
            return reading <= position
        })
    }

    /// 語の区切りの読みの位置と，そこまでの文字数．語をつなげて文にならなければ nil
    private static func boundaries(of candidate: Candidate) -> [Int: Int]? {
        guard !candidate.words.isEmpty, candidate.words.map(\.text).joined() == candidate.text else { return nil }
        var result: [Int: Int] = [:]
        var reading = 0
        var text = 0
        for word in candidate.words {
            reading += word.readingCount
            text += word.text.count
            result[reading] = text
        }
        return result
    }
}
