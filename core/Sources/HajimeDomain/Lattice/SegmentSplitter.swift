/// 分岐図で文節を区切るとき(⇧↓)の，区切れる位置を決める．
///
/// 1 文字ごとではなく，語の切れ目だけにする(「問題｜が｜ある」「それ｜は｜問題｜が｜ある｜と｜思う」「一度｜ログアウト｜して」)．
/// 1 文字ずつ動かすのは ⇧←→ に任せる．
///
/// 語の切れ目は，変換器が語として持つ単位に頼らずに決める(変換器の語には「があると思う」のような句がそのまま入っている)．
/// 読みの各位置で，左の読みの候補と右の読みの候補をつなげて見えている字になる組があれば，そこを切れ目とする．
/// 切っても同じ字になる位置は，前後が独立した語として読めるところ(「問題｜が」は切れるが「問｜題」は「問」「題」と読めても
/// 漢字 1 字どうしなので切らない)．ただし次の切れ目は語の途中のことが多いので除く:
/// - ひらがなどうしのあいだ(「あ｜る」「で｜す」)．右が助詞で始まるか，左が助詞で終わり右が 2 文字以上の語で始まるときだけ切る(「ある｜と」「が｜ある」)
/// - 漢字どうしのあいだで，どちらかが 1 字のもの(「天｜気」)．2 字以上どうしは切る(「運転｜免許」)
/// - 語の頭に来ない字(「ん」「っ」，小さいかな，長音)の前(「ウブ｜ンツ」)
public enum SegmentSplitter {
    /// 区切れる位置で分けた文節
    public struct Split: Sendable, Equatable {
        /// 区切れる位置(読みの先頭からの文字数)．小さい順
        public var positions: [Int]
        /// 区切れる位置で分けた文節の字(positions.count + 1 個)
        public var pieces: [String]

        public init(positions: [Int], pieces: [String]) {
            self.positions = positions
            self.pieces = pieces
        }
    }

    /// 数字で選ぶので，区切れる位置は 9 個まで
    public static let maximumPositions = 9

    /// - Parameters:
    ///   - shown: 見えている文節(選んでいる候補)
    ///   - reading: 文節の読み(ひらがな)
    ///   - candidates: 読みを文脈なしで変換したときの，読み全体の候補の字(よさそうな順)
    ///   - words: 読みを変換したときの語の並び(助詞かどうかを見る)
    ///   どちらも同じ読みで何度も呼ぶので，呼ぶ側でためておく
    public static func split(
        shown: String, reading: String,
        candidates: (String) -> [String], words: (String) -> [Candidate.Word]
    ) -> Split {
        let readingCharacters = Array(reading), text = Array(shown)
        guard readingCharacters.count > 1 else { return Split(positions: [], pieces: [shown]) }
        var cuts: [(reading: Int, text: Int)] = []
        for position in 1..<readingCharacters.count {
            let leftReading = String(readingCharacters[..<position]), rightReading = String(readingCharacters[position...])
            let rights = Set(candidates(rightReading))
            // 見えている字が「左の候補 + 右の候補」になる組のうち，右の候補が長いもの(切れ目が前のもの)を選ぶ
            guard let left = candidates(leftReading).filter({ shown.hasPrefix($0) && rights.contains(String(shown.dropFirst($0.count))) })
                .min(by: { $0.count < $1.count }) else { continue }
            let textCut = left.count
            guard textCut > (cuts.last?.text ?? 0), textCut < text.count,
                  allows(before: text[..<textCut], after: text[textCut...],
                         leftWords: { words(leftReading) }, rightWords: { words(rightReading) }) else { continue }
            cuts.append((position, textCut))
        }
        let textCuts = [0] + cuts.map(\.text) + [text.count]
        let pieces = zip(textCuts, textCuts.dropFirst()).map { String(text[$0..<$1]) }
        guard cuts.count > maximumPositions else { return Split(positions: cuts.map(\.reading), pieces: pieces) }
        // 10 個目からあとは区切らない(最後の文節にまとめる)
        let rest = pieces[maximumPositions...].joined()
        return Split(positions: Array(cuts.prefix(maximumPositions).map(\.reading)), pieces: Array(pieces.prefix(maximumPositions)) + [rest])
    }

    /// 字だけで語の途中と分かる切れ目か．カタカナどうし(「ログ｜アウト」)と，どちらかが 1 字の漢字どうし(「天｜気」「移転｜期」)
    public static func cutsWord(before: String, after: String) -> Bool {
        guard let last = before.last, let first = after.first else { return false }
        switch (kind(of: last), kind(of: first)) {
        case (.katakana, .katakana):
            return true
        case (.other, .other) where isIdeograph(last) && isIdeograph(first):
            return ideographRun(before.reversed()) < 2 || ideographRun(after) < 2
        default:
            return false
        }
    }

    /// 字の切れ目が語の途中でないか．字の種類の組ごとに決める
    private static func allows(
        before: ArraySlice<Character>, after: ArraySlice<Character>,
        leftWords: () -> [Candidate.Word], rightWords: () -> [Candidate.Word]
    ) -> Bool {
        // 語の頭に来ない字(「ん」「っ」，小さいかな，長音)の前は語の途中
        guard let last = before.last, let first = after.first, ClauseSplitter.canStartClause(with: first) else { return false }
        switch (kind(of: last), kind(of: first)) {
        case (.hiragana, .hiragana):
            // 右が助詞で始まり左の語が 2 文字以上(「ある｜と」「です｜ね」．「て｜も」は切らない)か，
            // 左が助詞で終わり右が名詞のほかの自立語で始まる(「が｜ある」．「で｜すね」は「すね」が名詞なので切らない)．
            // 活用した形に付く助詞の前(「読ん｜で」)と，文の終わりの助詞のあと(「わ｜から」)では切らない
            let right = rightWords(), left = leftWords()
            guard let head = right.first, let tail = left.last, !head.startsWithConjunctiveParticle else { return false }
            return (head.startsWithParticle && tail.readingCount >= 2)
                || (tail.endsWithParticle && !tail.endsWithSentenceFinalParticle && head.startsWithPredicate)
        case (.katakana, .katakana):
            // カタカナの並びは 1 語のことが多い(「ログ｜アウト」と切らない)
            return !cutsWord(before: String(before), after: String(after))
        case (.other, .hiragana) where isIdeograph(last):
            // 漢字のあとのひらがなは送り仮名のことがある(「飲｜み」「食｜べて」)．漢字が 2 字以上か，助詞で始まるときだけ切る．
            // 活用した形に付く助詞の前では切らない
            guard let head = rightWords().first, !head.startsWithConjunctiveParticle else { return false }
            return ideographRun(before.reversed()) >= 2 || head.startsWithParticle
        case (.hiragana, .other) where isIdeograph(first):
            // 文節の頭の 1 字のひらがなは接頭語のことがある(「お｜茶」)．頭のときだけ，2 字以上か助詞で終わるときに切る
            let run = hiraganaRun(before.reversed())
            return run < before.count || run >= 2 || leftWords().last?.endsWithParticle == true
        case (.other, .other) where isIdeograph(last) && isIdeograph(first):
            // 漢字どうしは，どちらも 2 字以上のときだけ切る(「運転｜免許」．「天｜気」「東京｜都」は切らない)
            return !cutsWord(before: String(before), after: String(after))
        default:
            return true
        }
    }

    private static func hiraganaRun<S: Sequence>(_ characters: S) -> Int where S.Element == Character {
        var count = 0
        for character in characters {
            guard kind(of: character) == .hiragana else { break }
            count += 1
        }
        return count
    }

    private static func isIdeograph(_ character: Character) -> Bool {
        character.unicodeScalars.first.map { $0.properties.isIdeographic } ?? false
    }

    /// 切れ目から続く漢字の数
    private static func ideographRun<S: Sequence>(_ characters: S) -> Int where S.Element == Character {
        var count = 0
        for character in characters {
            guard isIdeograph(character) else { break }
            count += 1
        }
        return count
    }

    private enum Kind { case hiragana, katakana, other }

    private static func kind(of character: Character) -> Kind {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return .other }
        switch scalar.value {
        case 0x3041...0x3096: return .hiragana
        case 0x30A1...0x30FA, 0x30FC: return .katakana
        default: return .other
        }
    }
}
