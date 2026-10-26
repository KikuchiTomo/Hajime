/// 入力方式(R-05)
public enum InputStyle: String, Sendable, Equatable, Codable, CaseIterable {
    /// ローマ字入力
    case romaji
    /// JIS かな配列のかな入力
    case kana
    /// 英語のまま入力し，ローマ字として読める並びには日本語の候補を出す(EN 入力)．Tab で日本語にする
    case english
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

/// 利用者が登録した語
public struct UserDictionaryEntry: Sendable, Equatable, Codable, Hashable {
    /// 読み(ひらがな)
    public var reading: String
    public var word: String

    public init(reading: String, word: String) {
        self.reading = reading
        self.word = word
    }

    /// 読みはひらがなと長音だけ，語は空でなく，どちらも上限の長さ以内
    public var isValid: Bool {
        !reading.isEmpty && !word.isEmpty
            && reading.count <= DefaultSettings.maximumUserDictionaryReadingLength
            && word.count <= DefaultSettings.maximumUserDictionaryWordLength
            && reading.unicodeScalars.allSatisfy { (0x3041...0x3096).contains($0.value) || $0 == "ー" }
    }
}

extension UserDictionaryEntry: CustomStringConvertible, CustomDebugStringConvertible {
    // 登録した語は入力内容と同じに扱うので，ログには長さだけを出す(docs/dev/SECURITY-MODEL.md)
    public var description: String { "UserDictionaryEntry(readingLength: \(reading.count), wordLength: \(word.count))" }
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

    /// 前後の空白を除いて 1 語を足す
    public static func add(reading: String, word: String, to entries: inout [UserDictionaryEntry]) -> AddResult {
        let entry = UserDictionaryEntry(reading: reading.trimmed, word: word.trimmed)
        guard entry.isValid else { return .invalid }
        guard !entries.contains(entry) else { return .alreadyRegistered }
        guard entries.count < DefaultSettings.maximumUserDictionaryEntries else { return .full }
        entries.append(entry)
        return .added
    }

    /// 取り込んだ語を足す．形の誤った語・登録済みの語・上限を超えた語は足さない．足した数を返す
    public static func merge(_ imported: [UserDictionaryEntry], into entries: inout [UserDictionaryEntry]) -> Int {
        var seen = Set(entries)
        var added = 0
        for entry in imported where entry.isValid && entries.count < DefaultSettings.maximumUserDictionaryEntries && seen.insert(entry).inserted {
            entries.append(entry)
            added += 1
        }
        return added
    }
}

extension String {
    fileprivate var trimmed: String {
        String(drop { $0 == " " || $0 == "\u{3000}" || $0 == "\t" }.reversed().drop { $0 == " " || $0 == "\u{3000}" || $0 == "\t" }.reversed())
    }
}
