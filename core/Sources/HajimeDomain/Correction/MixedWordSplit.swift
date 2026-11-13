/// 英字入力(自動)で，空白を挟まずに続けて打った英語と日本語の並び(「kyouhazoomdekaigi」)を語に分ける(R-05)．
///
/// 並び全体がローマ字として読めないときに，ローマ字として読めない英単語(「zoom」「push」)を切り出し，
/// 残りをローマ字として読める語にする．英単語のところで読めなくなった並びを丸ごと英語にすると，
/// 英単語より前と後ろの日本語まで英語のままになるため．分けた語ごとに英語か日本語かを見分けるのは呼び出し側(WordLanguageJudge)
public enum MixedWordSplit {
    /// 分けた 1 語
    public struct Piece: Sendable, Equatable {
        /// 打った英字
        public var keys: String
        /// 英単語として切り出した語か．false ならローマ字として読める語
        public var isEnglishWord: Bool

        public init(keys: String, isEnglishWord: Bool) {
            self.keys = keys
            self.isEnglishWord = isEnglishWord
        }
    }

    /// ローマ字として読める語と英単語に分ける．次の 2 つで並び全体を覆える分け方のうち，英単語の数が最も少ないもの．
    /// 同じなら語の数が少ないもの，それも同じなら英単語の文字が多いもの．
    /// 英単語の辞書には短い語が多く(「nip」「ush」)，英単語を細かく並べればたいていの並びを覆えるため，英単語はなるべく少なくする．
    /// 英単語の数が同じなら長い英単語にする(「kyouha」+「zoom」を「kyouhazo」+「om」より先にする)
    /// - ローマ字として読める語(英字の小文字と「-」．末尾の「n」は「ん」)．ローマ字の語は続けて並べない
    /// - ローマ字として読めず，英語の辞書(isEnglishWord)にある語．長さは DefaultSettings.mixedWordEnglishLength
    ///
    /// 分けられないか，ローマ字として読める語を含まないか，1 語にしかならなければ nil
    public static func split(_ keys: String, isEnglishWord: (String) -> Bool) -> [Piece]? {
        let characters = Array(keys)
        let count = characters.count
        guard count >= 2, count <= DefaultSettings.maximumMixedWordKeys else { return nil }
        // readable[start][end - start - 1]: start..<end をローマ字として読めるか
        var readable = [[Bool]](repeating: [], count: count)
        for start in 0..<count {
            var composition = Composition()
            for end in (start + 1)...count {
                let character = characters[end - 1]
                guard (character.isASCII && character.isLetter && character.isLowercase) || character == "-" else { break }
                composition.insertRomaji(character)
                if composition.containsInvalidRomaji { break }
                readable[start].append(composition.pending.isEmpty || composition.pending == "n")
            }
        }
        func isReadable(_ start: Int, _ end: Int) -> Bool {
            let row = readable[start]
            return end - start - 1 < row.count && row[end - start - 1]
        }

        // 位置と最後の語の種類(0: ローマ字，1: 英単語)ごとの，最もよい分け方(語の数，英単語の文字数)と 1 つ前
        struct Step { var englishWords: Int; var pieces: Int; var englishLetters: Int; var start: Int; var previousKind: Int }
        func better(_ lhs: Step, than rhs: Step?) -> Bool {
            guard let rhs else { return true }
            return (lhs.englishWords, lhs.pieces, -lhs.englishLetters) < (rhs.englishWords, rhs.pieces, -rhs.englishLetters)
        }
        var best = [[Step?]](repeating: [nil, nil], count: count + 1)
        let lengths = DefaultSettings.mixedWordEnglishLength
        for end in 1...count {
            for start in 0..<end {
                let previous: [(kind: Int, step: Step)] = start == 0
                    ? [(kind: -1, step: Step(englishWords: 0, pieces: 0, englishLetters: 0, start: 0, previousKind: -1))]
                    : (0...1).compactMap { kind in best[start][kind].map { (kind: kind, step: $0) } }
                guard !previous.isEmpty else { continue }
                let readableHere = isReadable(start, end)
                let length = end - start
                let englishHere = !readableHere && lengths.contains(length)
                    && characters[start..<end].allSatisfy { $0.isASCII && $0.isLetter } && isEnglishWord(String(characters[start..<end]))
                for (kind, step) in previous {
                    if readableHere, kind != 0 {
                        let next = Step(englishWords: step.englishWords, pieces: step.pieces + 1, englishLetters: step.englishLetters,
                                        start: start, previousKind: kind)
                        if better(next, than: best[end][0]) { best[end][0] = next }
                    }
                    if englishHere {
                        let next = Step(englishWords: step.englishWords + 1, pieces: step.pieces + 1, englishLetters: step.englishLetters + length,
                                        start: start, previousKind: kind)
                        if better(next, than: best[end][1]) { best[end][1] = next }
                    }
                }
            }
        }
        var kind = (0...1).filter { best[count][$0] != nil }.min { lhs, rhs in better(best[count][lhs]!, than: best[count][rhs]) }
        var end = count
        var pieces: [Piece] = []
        while let current = kind, let step = best[end][current] {
            pieces.insert(Piece(keys: String(characters[step.start..<end]), isEnglishWord: current == 1), at: 0)
            end = step.start
            kind = step.previousKind >= 0 ? step.previousKind : nil
        }
        guard end == 0, pieces.count >= 2, pieces.contains(where: { !$0.isEnglishWord }) else { return nil }
        return pieces
    }
}
