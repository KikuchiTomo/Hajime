/// 分岐図で文節を区切るとき(⇧↓)の，区切れる位置を決める．
///
/// 1 文字ごとではなく，意味のある切れ目だけにする(「問題｜が｜ある」「一度｜ログアウト｜して」)．1 文字ずつ動かすのは ⇧←→ に任せる．
/// 切れ目は，見えている文節の字の種類が変わるところ(漢字・カタカナ・ひらがな．ただし漢字のあとの送り仮名では切らない)と，
/// ひらがなの中の助詞の前後:
/// - 漢字やカタカナのあとのひらがなが 1 文字の助詞で始まれば，助詞のあとで切る(「が｜ある」)
/// - 変換の語の並び(Zenzai を使わない変換)が，ひらがなの終わりの 1 文字の助詞を語として分けていれば，その前で切る(「それ｜は」)
///
/// 見えている文節の字と読みを突き合わせられないとき(英字や記号の混ざる文節)は，語の並びの切れ目をそのまま使う
public enum SegmentSplitter {
    /// 区切れる位置で分けた文節
    public struct Split: Sendable, Equatable {
        /// 区切れる位置(読みの先頭からの文字数)．小さい順
        public var positions: [Int]
        /// 区切れる位置で分けた文節の字(positions.count + 1 個)．見えている字で分けられなければ読みを分ける
        public var pieces: [String]

        public init(positions: [Int], pieces: [String]) {
            self.positions = positions
            self.pieces = pieces
        }
    }

    /// 数字で選ぶので，区切れる位置は 9 個まで
    public static let maximumPositions = 9

    /// 助詞として切り離す 1 文字のひらがな
    static let particles: Set<Character> = ["が", "を", "に", "は", "で", "と", "の", "も", "へ", "や"]

    /// - Parameters:
    ///   - shown: 見えている文節(選んでいる候補)
    ///   - reading: 文節の読み(ひらがな)
    ///   - words: 文節の読みを変換したときの語の並び
    public static func split(shown: String, reading: String, words: [Candidate.Word]) -> Split {
        let wordEnds = boundaries(of: words, readingCount: reading.count)
        let split = aligned(shown: shown, reading: reading, wordEnds: wordEnds)
            ?? Split(positions: wordEnds, pieces: pieces(of: reading, at: wordEnds))
        guard split.positions.count > maximumPositions else { return split }
        // 10 個目からあとは区切らない(最後の文節にまとめる)
        let positions = Array(split.positions.prefix(maximumPositions))
        let rest = split.pieces[maximumPositions...].joined()
        return Split(positions: positions, pieces: Array(split.pieces.prefix(maximumPositions)) + [rest])
    }

    /// 語の並びの切れ目(読みの先頭からの文字数)．文節の中だけ．語の読みの長さが合わなければ空
    static func boundaries(of words: [Candidate.Word], readingCount: Int) -> [Int] {
        var position = 0
        var ends: [Int] = []
        for word in words {
            position += word.readingCount
            ends.append(position)
        }
        guard position == readingCount else { return [] }
        return ends.filter { $0 > 0 && $0 < readingCount }
    }

    private static func pieces(of text: String, at positions: [Int]) -> [String] {
        let characters = Array(text)
        let cuts = [0] + positions + [characters.count]
        return zip(cuts, cuts.dropFirst()).map { String(characters[$0..<$1]) }
    }

    // MARK: - 見えている字と読みの突き合わせ

    private enum Kind { case hiragana, katakana, other }

    private static func kind(of character: Character) -> Kind {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return .other }
        switch scalar.value {
        case 0x3041...0x3096: return .hiragana
        case 0x30A1...0x30FA, 0x30FC: return .katakana
        default: return .other
        }
    }

    /// 字の種類が同じものの並び
    private struct Run {
        var kind: Kind
        var text: [Character]
        /// 読みでの始まりと終わり(突き合わせたあとに決まる)
        var readingStart = 0
        var readingEnd = 0
    }

    private static func runs(of text: String) -> [Run] {
        var runs: [Run] = []
        for character in text {
            let kind = kind(of: character)
            // 長音はカタカナにもひらがなにも続ける
            if let last = runs.last, last.kind == kind || (character == "ー" && last.kind != .other) {
                runs[runs.count - 1].text.append(character)
            } else {
                runs.append(Run(kind: kind, text: [character]))
            }
        }
        return runs
    }

    /// 見えている字を，字の種類ごとに読みと突き合わせて区切る．仮名の並びは読みにそのまま現れ，それ以外(漢字など)は仮名と仮名のあいだの読みを受け持つ
    private static func aligned(shown: String, reading: String, wordEnds: [Int]) -> Split? {
        var runs = runs(of: shown)
        let readingCharacters = Array(reading)
        var position = 0
        for index in runs.indices {
            runs[index].readingStart = position
            if runs[index].kind != .other {
                let kana = Array(KanaWidth.hiragana(from: String(runs[index].text)))
                guard readingCharacters.count >= position + kana.count,
                      Array(readingCharacters[position..<position + kana.count]) == kana else { return nil }
                position += kana.count
            } else if let next = runs[(index + 1)...].first(where: { $0.kind != .other }) {
                // 次の仮名の並びが読みに現れるところまでを受け持つ(少なくとも 1 文字)
                let kana = Array(KanaWidth.hiragana(from: String(next.text)))
                guard let found = firstIndex(of: kana, in: readingCharacters, from: position + 1) else { return nil }
                position = found
            } else {
                guard position < readingCharacters.count else { return nil }
                position = readingCharacters.count
            }
            runs[index].readingEnd = position
        }
        guard position == readingCharacters.count, !runs.isEmpty else { return nil }

        // (読みの位置, 見えている字の位置)
        var cuts: [(reading: Int, text: Int)] = []
        var textPosition = 0
        for (index, run) in runs.enumerated() {
            // 漢字のあとのひらがなは送り仮名のことがある(「思｜う」と切らない)．助詞で始まるか，語の並びが切っているときだけ切る
            let isOkurigana = index > 0 && runs[index - 1].kind == .other && run.kind == .hiragana
                && !particles.contains(run.text[0]) && !wordEnds.contains(run.readingStart)
            if index > 0, !isOkurigana { cuts.append((run.readingStart, textPosition)) }
            if run.kind == .hiragana {
                // 漢字やカタカナのあとの「が｜ある」
                if index > 0, run.text.count > 1, particles.contains(run.text[0]) {
                    cuts.append((run.readingStart + 1, textPosition + 1))
                }
                // 語の並びが分けた，ひらがなの終わりの 1 文字の助詞(「それ｜は」)
                if run.text.count > 1, particles.contains(run.text[run.text.count - 1]), wordEnds.contains(run.readingEnd - 1) {
                    cuts.append((run.readingEnd - 1, textPosition + run.text.count - 1))
                }
            }
            textPosition += run.text.count
        }
        var seen = Set<Int>()
        cuts = cuts.filter { $0.reading > 0 && $0.reading < readingCharacters.count && seen.insert($0.reading).inserted }.sorted { $0.reading < $1.reading }
        return Split(positions: cuts.map(\.reading), pieces: pieces(of: shown, at: cuts.map(\.text)))
    }

    private static func firstIndex(of needle: [Character], in haystack: [Character], from start: Int) -> Int? {
        guard !needle.isEmpty, start <= haystack.count - needle.count else { return nil }
        return (start...(haystack.count - needle.count)).first { Array(haystack[$0..<$0 + needle.count]) == needle }
    }
}
