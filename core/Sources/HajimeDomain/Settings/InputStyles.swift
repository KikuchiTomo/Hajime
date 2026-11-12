/// 入力方式(R-05)
public enum InputStyle: String, Sendable, Equatable, Codable, CaseIterable {
    /// ローマ字入力
    case romaji
    /// JIS かな配列のかな入力
    case kana
    /// 英語のまま入力し，ローマ字として読める並びには日本語の候補を出す(EN 入力)．Tab で日本語にする
    case english
    /// 英語で打ちながら，日本語にできる語は語ごとに見分けて日本語にする(英字入力(自動))
    case englishAuto

    /// 英字のまま打つ方式か(英字入力と英字入力(自動))
    public var typesLetters: Bool {
        switch self {
        case .english, .englishAuto: true
        case .romaji, .kana: false
        }
    }
}

/// 英字を打つときのキーボードの配列．ローマ字入力と EN 入力で，どのキーでどの英字が入るかを決める．
/// かな入力はキーの位置からかなを決めるので，この設定によらない
public enum KeyboardLayout: String, Sendable, Equatable, Codable, CaseIterable {
    /// OS で最後に使った英字の配列のまま
    case system
    case abc
    case us
    case dvorak
    /// Dvorak．Command を押している間だけ QWERTY
    case dvorakQwertyCommand
    case colemak
}

/// Space で変換したときに最初に選ぶ文節
public enum InitialFocus: String, Sendable, Equatable, Codable, CaseIterable {
    /// 文の先頭
    case start
    /// 文の末尾
    case end
    /// 誤変換の可能性がいちばん高い文節
    case automatic
}

/// 語の意味(R-08)を候補の窓のどこに出すか
public enum MeaningPlacement: String, Sendable, Equatable, Codable, CaseIterable {
    /// 候補の右．一覧は選んでいる候補を指すカードにし，分岐図は選んでいる候補の先に意味の枝を伸ばす
    case side
    /// 候補の下(足元の上)
    case below
}

/// 打っているあいだに窓(入力中の候補・入力中の予測)を出すか
public enum SuggestionDisplay: String, Sendable, Equatable, Codable, CaseIterable {
    case off
    /// ライブ変換がオフのときだけ出す(ライブ変換で文が見えているときは要らない)
    case whenLiveConversionOff
    case always
}

/// 打ち間違いを直す基準．直した読みが打ったままの読みよりどれだけもっともらしければ直すか(対数確率の差)
public enum CorrectionSensitivity: String, Sendable, Equatable, Codable, CaseIterable {
    /// 確かなときだけ直す
    case cautious
    case standard
    /// 少しでももっともらしければ直す
    case aggressive

    /// 直す差と，直さずに「もしかして」と示す差
    public var margins: (apply: Double, suggest: Double) {
        switch self {
        case .cautious: (DefaultSettings.readingCorrectionMargin + 1, DefaultSettings.readingSuggestionMargin + 1)
        case .standard: (DefaultSettings.readingCorrectionMargin, DefaultSettings.readingSuggestionMargin)
        case .aggressive: (DefaultSettings.readingCorrectionMargin - 1, DefaultSettings.readingSuggestionMargin - 0.5)
        }
    }
}

/// 句読点の組み合わせ
public enum PunctuationStyle: String, Sendable, Equatable, Codable, CaseIterable {
    /// 、。
    case toutenKuten
    /// ，．
    case commaPeriod
    /// 、．
    case toutenPeriod
    /// ，。
    case commaKuten

    public var comma: String {
        switch self {
        case .toutenKuten, .toutenPeriod: "、"
        case .commaPeriod, .commaKuten: "，"
        }
    }

    public var period: String {
        switch self {
        case .toutenKuten, .commaKuten: "。"
        case .commaPeriod, .toutenPeriod: "．"
        }
    }
}

/// [ ] で入れる括弧
public enum BracketStyle: String, Sendable, Equatable, Codable, CaseIterable {
    /// 「」
    case corner
    /// ［］
    case square

    public var open: String { self == .corner ? "「" : "［" }
    public var close: String { self == .corner ? "」" : "］" }
}

/// / で入れる文字
public enum SlashStyle: String, Sendable, Equatable, Codable, CaseIterable {
    /// ・
    case nakaguro
    /// ／
    case slash

    public var text: String { self == .nakaguro ? "・" : "／" }
}

/// 文字の幅
public enum CharacterWidth: String, Sendable, Equatable, Codable, CaseIterable {
    case halfwidth
    case fullwidth
}

/// 確定した候補から学ぶか
public enum LearningMode: String, Sendable, Equatable, Codable, CaseIterable {
    /// 学んで，学んだことを使う
    case enabled
    /// 学んだことは使うが，新しくは学ばない
    case readOnly
    /// 学ばず，学んだことも使わない
    case disabled
}

/// かな漢字変換に使う Zenzai のモデル．xsmall のモデルが無い環境では，どれを選んでも small で変換する
public enum ZenzaiModelChoice: String, Sendable, Equatable, Codable, CaseIterable {
    /// small のモデルだけを使う．精度を優先する
    case accurate
    /// xsmall のモデルだけを使う．速さを優先する(GPU の無い環境で打っている間も Zenzai を使えるように)
    case fast
    /// 打っている間の表示は xsmall，打鍵が止まったときと変換(Space)は small で求める
    case combined
}

/// 利用者が登録した語．読みと語の組で 1 語とみなし，同じ組を品詞を変えて重ねて登録しない
public struct UserDictionaryEntry: Sendable, Equatable, Codable, Hashable {
    /// 読み．ひらがなか，ローマ字・英字(「gh」「toyota」)．引くときは lookupReading にそろえる
    public var reading: String
    public var word: String
    public var wordClass: WordClass

    public init(reading: String, word: String, wordClass: WordClass = DefaultSettings.userWordClass) {
        self.reading = reading
        self.word = word
        self.wordClass = wordClass
    }

    private enum CodingKeys: String, CodingKey {
        case reading, word, wordClass
    }

    /// 品詞を書いていない語(品詞を選べるようになる前に登録した語)は固有名詞として読む．それまで固有名詞として変換エンジンに渡していたため．
    /// 知らない品詞(新しいバージョンで足した品詞)は名詞として読む
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reading = try container.decode(String.self, forKey: .reading)
        word = try container.decode(String.self, forKey: .word)
        let name = try container.decodeIfPresent(String.self, forKey: .wordClass)
        wordClass = name.map { WordClass(rawValue: $0) ?? .noun } ?? DefaultSettings.legacyUserWordClass
    }

    /// 同じ語とみなすか(読みと語が同じ)．品詞は比べない
    public func isSameWord(as other: UserDictionaryEntry) -> Bool {
        reading == other.reading && word == other.word
    }

    /// 読みはひらがな・長音か，ローマ字・英字・数字．語は空でなく，どちらも上限の長さ以内
    public var isValid: Bool {
        !reading.isEmpty && !word.isEmpty
            && reading.count <= DefaultSettings.maximumUserDictionaryReadingLength
            && word.count <= DefaultSettings.maximumUserDictionaryWordLength
            && lookupReading != nil
    }

    /// 引くときの読み(ReadingNormalization)．ローマ字の読みは，打ったときと同じかなにする
    public var lookupReading: String? { ReadingNormalization.normalized(reading) }

    /// 読みが，かなになり切るか(変換エンジンに文の中の語として渡せるか)．
    /// かなにならない英字の残る読み(「gh」)は，読み全体が一致したときだけ候補に出す
    public var hasKanaReading: Bool {
        lookupReading.map { !$0.contains(where: \.isASCII) } ?? false
    }
}

extension UserDictionaryEntry: CustomStringConvertible, CustomDebugStringConvertible {
    // 登録した語は入力内容と同じに扱うので，ログには長さだけを出す(docs/dev/SECURITY-MODEL.md)
    public var description: String { "UserDictionaryEntry(readingLength: \(reading.count), wordLength: \(word.count), class: \(wordClass))" }
    public var debugDescription: String { description }
}

/// ユーザー辞書を編集する規則．macOS と Windows の設定の画面が共通に使う
public enum UserDictionaryEditing {
    public enum AddResult: Equatable {
        case added
        case alreadyRegistered
        case invalid
        case full
    }

    /// 前後の空白を除いて 1 語を足す．同じ読みと語がもうあれば，品詞だけを書き換える
    public static func add(reading: String, word: String, wordClass: WordClass = DefaultSettings.userWordClass,
                           to entries: inout [UserDictionaryEntry]) -> AddResult {
        let entry = UserDictionaryEntry(reading: reading.trimmed, word: word.trimmed, wordClass: wordClass)
        guard entry.isValid else { return .invalid }
        if let index = entries.firstIndex(where: { $0.isSameWord(as: entry) }) {
            guard entries[index].wordClass != entry.wordClass else { return .alreadyRegistered }
            entries[index].wordClass = entry.wordClass
            return .added
        }
        guard entries.count < DefaultSettings.maximumUserDictionaryEntries else { return .full }
        entries.append(entry)
        return .added
    }

    /// 読みと語が同じ語を除く(品詞は問わない)
    public static func remove(_ removed: some Sequence<UserDictionaryEntry>, from entries: inout [UserDictionaryEntry]) {
        let keys = Set(removed.map { Key($0) })
        entries.removeAll { keys.contains(Key($0)) }
    }

    /// 取り込んだ語を足す．形の誤った語・登録済みの語(読みと語が同じもの)・上限を超えた語は足さない．足した数を返す
    public static func merge(_ imported: [UserDictionaryEntry], into entries: inout [UserDictionaryEntry]) -> Int {
        var seen = Set(entries.map { Key($0) })
        var added = 0
        for entry in imported where entry.isValid && entries.count < DefaultSettings.maximumUserDictionaryEntries && seen.insert(Key(entry)).inserted {
            entries.append(entry)
            added += 1
        }
        return added
    }

    private struct Key: Hashable {
        let reading: String
        let word: String
        init(_ entry: UserDictionaryEntry) {
            reading = entry.reading
            word = entry.word
        }
    }
}

extension String {
    var trimmed: String {
        String(drop { $0 == " " || $0 == "\u{3000}" || $0 == "\t" }.reversed().drop { $0 == " " || $0 == "\u{3000}" || $0 == "\t" }.reversed())
    }
}
