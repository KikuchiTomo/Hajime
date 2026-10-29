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
}
