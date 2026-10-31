/// タイプミスを補正するかどうかの判定(R-02)．英単語かどうかは呼び出し側が調べて渡す．
public struct TypoCorrectionRule: Sendable {
    public var level: TypoCorrectionLevel

    public init(level: TypoCorrectionLevel) {
        self.level = level
    }

    /// 補正の対象として調べる部分．文の途中に打った英単語も見つけられるよう，区切りから末尾までの部分を長い順に返す．
    ///
    /// 次の条件をすべて満たす部分に限る．
    /// - ローマ字として読めない並びを含み，英字だけを打った部分
    /// - ローマ字として読めない文字で始まるか(「このばーじょんの」+「python」)，読みの先頭から始まる(「pthon」)．
    ///   「nopython」のように前の日本語を英単語に飲み込まないため．
    ///   ただし「このrepository」のように，かなになる綴りで始まる文の途中の英単語は見つけられない
    /// - 打ちかけのローマ字が残っていない(末尾の「n」は除く)．打っている途中の単語を補正しないため．
    ///   打ちかけの子音(「reac」+「t」の t)は英単語の続きのことが多く，残りだけで直すと「reach」のように誤る．
    ///   includingPending なら打ちかけも英単語に含めて返す．補正している英単語を，続けて打ったキーまで延ばすときに使う
    ///   (「scrip」+「t」．子音で終わる英単語は，最後のキーが打ちかけとして残る)
    public func tails(in composition: Composition, includingPending: Bool = false) -> [Composition.Tail] {
        guard level != .off, includingPending || composition.pending.isEmpty || composition.pending == "n" else { return [] }
        return composition.tails().filter { tail in
            tail.containsInvalidRomaji
                && (tail.startsWithUnconvertible || tail.startsFreeRegion)
                && tail.keys.count >= DefaultSettings.minimumCorrectionLength
                && tail.keys.count <= DefaultSettings.maximumCorrectionLength
                && tail.keys.allSatisfy { $0.isASCII && $0.isLetter }
                // Shift を押して打った大文字は，英字として打ったもの(「konoIMEha」の IME)．綴りを直さず打ったままにする
                && !tail.keys.contains(where: \.isUppercase)
        }
    }

    /// 綴りの誤りを探す部分を，調べる順に返す．tails は tails(in:) の結果(長い順)．
    ///
    /// 英単語の頭がかなになった綴りの誤り(「jvascript」→「jゔぁscりpt」)は，いちばん短い部分(「script」)だけを調べると
    /// 英単語全体を直せない．そこで，ローマ字として読めない文字で始まる部分を長い順に調べる．
    /// その文字(「j」)は日本語として打ったものではないので，そこを英字の打ち始めとみなせる．
    /// かなで始まる部分(「konopthon」「reactwo」)は調べない．前の日本語や後ろの助詞まで英単語に飲み込むため
    /// (macOS の綴りの候補は reactwo に react を返す)．
    /// 長い部分も，候補との編集距離が maximumCorrectionDistance 以内でなければ直さない(correction)ので，
    /// 前の日本語の打ち間違い(「tkitou」の t)から始まる部分が，後ろの日本語ごと英単語になることはまず無い．
    /// いちばん短い部分がかなで始まるとき(確定させた英単語の直後から始まる部分)は，これまでどおりそれも最後に調べる
    public func misspellingTails(from tails: [Composition.Tail]) -> [Composition.Tail] {
        let starts = tails.filter(\.startsWithUnconvertible)
        guard let last = tails.last, !starts.contains(last) else { return starts }
        return starts + [last]
    }

    /// ローマ字として読めてしまう英単語を，英単語とみなすか(「gitwotukau」→「gitを使う」)．
    /// 英単語の終わりがかなの区切りに合わない(「git」+「wo」の「two」のように，綴りの途中で切れる)ものだけを調べ，
    /// 全体を日本語として読んだもっともらしさ(japanese)と，英単語の後ろだけを日本語として読んだもっともらしさ(following)を比べる
    /// - Parameters:
    ///   - endsOnBoundary: 英単語の終わりが，かなの区切りに合うか
    ///   - japanese: 英単語から後ろ全体を日本語として読んだときのもっともらしさ
    ///   - following: 英単語の後ろだけを日本語として読んだときのもっともらしさ
    ///   - followingReading: 英単語の後ろの読み．英単語のあとに続く助詞などで始まるときだけ英単語とみなす
    ///     (「gitを」「gitで」)．打ち間違いのある日本語(「arigatoou」)の一部を英単語(「gat」)と取り違えないため
    public func readsAsEnglish(endsOnBoundary: Bool, japanese: Double, following: Double, followingReading: String) -> Bool {
        guard level != .off, !endsOnBoundary, japanese.isFinite || following.isFinite,
            Self.startsLikeFollowingEnglish(followingReading) else { return false }
        return following - DefaultSettings.wordReadAsRomajiCost > japanese
    }

    /// この文字のすぐあとに打った英字は，識別子の続きか(「user_name」「a.b」「userName」「v2」)．識別子は直さない(R-06)
    public static func continuesIdentifier(_ character: Character) -> Bool {
        character == "_" || character == "." || (character.isASCII && (character.isLetter || character.isNumber))
    }

    /// 英単語が日本語の文の中にあるか．前の読みか，組み立てる前の入力位置の直前に日本語(かな・漢字)があればそうみなす(R-06)
    public func isInJapaneseSentence(before reading: some Collection<Character>, precedingCharacter: Character?) -> Bool {
        reading.contains(where: WordLanguageJudge.isJapanese) || (precedingCharacter.map(WordLanguageJudge.isJapanese) ?? false)
    }

    /// 読みが，文の中の英単語のすぐあとによく続く語で始まるか
    public static func startsLikeFollowingEnglish(_ reading: String) -> Bool {
        wordsAfterEnglish.contains(where: reading.hasPrefix)
    }

    /// 綴りの誤りとみなす部分の後ろが，英字のあとに続く日本語として読めるか(「pc」+「から」，「sns」+「を」，「ok」+「です」)．
    /// 英字の略語などをそのまま打ち，続けて助詞を打ったものなので，後ろの日本語まで英単語に飲み込んで直さない(「pcka」→ pika)．
    /// 後ろは英字のあとのいちばん長い，かなになり切る部分で，打ちかけのとき(「か」)は続く語の頭でもよい
    public static func endsWithJapaneseAfterLetters(_ keys: String) -> Bool {
        let keys = Array(keys)
        for start in keys.indices.dropFirst() {
            var following = Composition()
            for key in keys[start...] { following.insertRomaji(key) }
            guard !following.containsInvalidRomaji, following.pending.isEmpty else { continue }
            let reading = following.conversionReading
            return startsLikeFollowingEnglish(reading) || wordsAfterEnglish.contains { $0.hasPrefix(reading) }
        }
        return false
    }

    /// 文の中の英単語のすぐあとによく続く語(助詞と「する」「です」など)
    static let wordsAfterEnglish = [
        "を", "が", "は", "に", "で", "の", "と", "も", "へ", "や", "から", "まで", "より", "って",
        "する", "した", "して", "しま", "され", "させ", "です", "でし", "だ", "じゃ", "なら",
    ]

    /// keys が英単語ならそのまま，綴りの誤りなら近い単語を補正の結果として返す
    public func correction(for keys: String, isWord: Bool, suggestions: [String]) -> String? {
        if isWord { return keys }
        guard level == .standard else { return nil }
        return suggestions.first { suggestion in
            suggestion.count >= DefaultSettings.minimumCorrectionLength
                && suggestion.allSatisfy({ $0.isASCII && $0.isLetter })
                && EditDistance.damerauLevenshtein(keys.lowercased(), suggestion.lowercased())
                    <= DefaultSettings.maximumCorrectionDistance
        }
    }
}

public enum EditDistance {
    /// 隣り合う 2 文字の入れ替えを 1 回と数える編集距離(制限付き Damerau–Levenshtein)
    public static func damerauLevenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { table[i][0] = i }
        for j in 0...b.count { table[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                table[i][j] = min(table[i - 1][j] + 1, table[i][j - 1] + 1, table[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    table[i][j] = min(table[i][j], table[i - 2][j - 2] + 1)
                }
            }
        }
        return table[a.count][b.count]
    }
}
