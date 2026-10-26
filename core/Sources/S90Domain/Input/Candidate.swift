/// 変換候補の出どころ．確定したときに何をするか(学習するか，など)が変わる．
public enum CandidateOrigin: Sendable, Equatable {
    /// 変換エンジンの候補．id はエンジンのアダプタが自分の候補を引くための番号
    case engine(id: Int)
    /// タイプミスの補正(R-02)
    case correction
    /// 打ったままの文字列(補正を取り消すときの候補)
    case asTyped
    /// 文字の種類の変換(R-03)
    case variant(ScriptVariant)
    /// 文全体の候補から切り出した文節．学習には使わない
    case sentencePart
    /// 複数の候補をつないだもの(文節格子の全体など)
    case combined
    /// 読みから引いた記号(SymbolDictionary)と日付(DateExpressions)
    case symbol
    /// 利用者が登録した語
    case userDictionary
}

/// 候補ひとつ．readingCount は，この候補が読みの先頭から何文字ぶんを置き換えるか．
/// score はエンジンが付けた対数尤度で，大きいほどよい．エンジン以外の候補は 0
public struct Candidate: Sendable, Equatable {
    /// 候補の末尾の語．読みの何文字ぶんが，候補の何文字になったか
    public struct TrailingWord: Sendable, Equatable {
        public var readingCount: Int
        public var textCount: Int

        public init(readingCount: Int, textCount: Int) {
            self.readingCount = readingCount
            self.textCount = textCount
        }
    }

    /// エンジンの辞書の語ひとつ．辞書には「な人だ」「を立てる」のように，助詞や助動詞と次の語をつないだ語もある
    public struct Word: Sendable, Equatable {
        public var text: String
        public var readingCount: Int
        /// 助詞で始まる語か(「はいい」「を立てる」)
        public var startsWithParticle: Bool
        /// 助詞で終わる語か(「があれば」)
        public var endsWithParticle: Bool
        /// 名詞などの自立語で始まる語か(ひらがなで書く「ところ」「こと」も含む)
        public var startsWithNoun: Bool

        public init(text: String, readingCount: Int, startsWithParticle: Bool = false, endsWithParticle: Bool = false, startsWithNoun: Bool = false) {
            self.text = text
            self.readingCount = readingCount
            self.startsWithParticle = startsWithParticle
            self.endsWithParticle = endsWithParticle
            self.startsWithNoun = startsWithNoun
        }
    }

    public var text: String
    public var readingCount: Int
    public var origin: CandidateOrigin
    public var score: Double
    /// 末尾の語(エンジンが語の区切りを教えるときだけ)．打っている途中の語をかなのまま見せるのに使う
    public var trailingWord: TrailingWord?
    /// 候補を作る語の並び(エンジンが語の区切りを教えるときだけ)．文節に分けるのに使う(ClauseSplitter)
    public var words: [Word]

    public init(text: String, readingCount: Int, origin: CandidateOrigin, score: Double = 0, trailingWord: TrailingWord? = nil, words: [Word] = []) {
        self.text = text
        self.readingCount = readingCount
        self.origin = origin
        self.score = score
        self.trailingWord = trailingWord
        self.words = words
    }

    /// 変換エンジンが出した候補か．確定したときに学習に使うのはこれだけ
    public var isFromEngine: Bool {
        if case .engine = origin { true } else { false }
    }
}

extension Candidate: CustomStringConvertible, CustomDebugStringConvertible {
    // 候補の文字列は入力内容そのものなので，ログには長さだけを出す
    public var description: String { "Candidate(length: \(text.count), readingCount: \(readingCount), origin: \(origin))" }
    public var debugDescription: String { description }
}
