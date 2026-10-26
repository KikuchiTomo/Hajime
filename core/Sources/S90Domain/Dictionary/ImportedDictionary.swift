import Foundation

/// 取り込んだ辞書の語の品詞．変換エンジンの品詞に置き換えて渡す．
/// 動詞や形容詞の活用は扱わないので，分からない品詞はすべて名詞として扱う
public enum WordClass: String, Sendable, Equatable, Codable, CaseIterable {
    case noun
    case properNoun
    case personName
    case surname
    case givenName
    case organization
    case place
    case symbol

    /// 辞書のファイルに書かれた品詞の名前から決める．分からなければ名詞
    public init(partOfSpeech name: String) {
        let name = String(name.filter { $0 != " " && $0 != "\u{3000}" })
        if name.contains("人名") || name.contains("名前") {
            self = name.contains("姓") ? .surname : name.contains("名") && name != "人名" ? .givenName : .personName
        } else if name.contains("姓") {
            self = .surname
        } else if name.contains("地名") || name.contains("駅") {
            self = .place
        } else if name.contains("組織") || name.contains("会社") || name.contains("団体") {
            self = .organization
        } else if name.contains("固有名詞") {
            self = .properNoun
        } else if name.contains("記号") || name.contains("顔文字") || name.contains("絵文字") {
            self = .symbol
        } else {
            self = .noun
        }
    }
}

/// 取り込んだ辞書の語 1 つ．読みはひらがな
public struct DictionaryWord: Sendable, Equatable, Hashable {
    public var reading: String
    public var word: String
    public var wordClass: WordClass

    public init(reading: String, word: String, wordClass: WordClass = .noun) {
        self.reading = reading
        self.word = word
        self.wordClass = wordClass
    }

    /// 読みはひらがなと長音だけ，語は空でなく，どちらも上限の長さ以内．タブと改行を含まない(索引のファイルの区切りのため)
    public var isValid: Bool {
        !reading.isEmpty && !word.isEmpty
            && reading.count <= DefaultSettings.maximumImportedReadingLength
            && word.count <= DefaultSettings.maximumImportedWordLength
            && reading.unicodeScalars.allSatisfy { (0x3041...0x3096).contains($0.value) || $0 == "ー" }
            && !word.contains(where: { $0 == "\t" || $0.isNewline })
    }
}

extension DictionaryWord: CustomStringConvertible, CustomDebugStringConvertible {
    // 辞書の語は入力内容と同じに扱うので，ログには長さだけを出す
    public var description: String { "DictionaryWord(readingLength: \(reading.count), wordLength: \(word.count), class: \(wordClass))" }
    public var debugDescription: String { description }
}

/// 取り込んだ辞書を効かせる条件
public enum DictionaryCondition: Sendable, Equatable, Codable, Hashable {
    /// いつでも効かせる
    case always
    /// 選んだアプリ(バンドル ID の前方一致)でだけ効かせる
    case apps([String])
    /// ふだんは低い優先度で効かせ，最近その辞書の語を確定していれば優先度を上げる
    case context
}

/// 取り込んだ辞書 1 つの設定．語そのものは別のファイル(索引)に置き，設定には入れない．
/// 一覧の並び順が優先度(上ほど高い)
public struct ImportedDictionary: Sendable, Equatable, Codable, Hashable, Identifiable {
    public var id: String
    /// 一覧に出す名前(既定は取り込んだファイルの名前)
    public var name: String
    /// 分野(「電気」「法律」など．利用者が付ける)．空なら付けない
    public var field: String
    public var isEnabled: Bool
    public var condition: DictionaryCondition
    /// 取り込んだ語の数
    public var wordCount: Int
    /// 索引のファイルの中身の SHA-256(16 進の小文字)．同期のとき，ほかの Mac の索引が古いかどうかと，
    /// 運んだファイルが壊れていないかを確かめるのに使う．同期を入れる前に取り込んだ辞書は nil
    public var revision: String?

    public init(id: String, name: String, field: String = "", isEnabled: Bool = true, condition: DictionaryCondition = .always, wordCount: Int,
                revision: String? = nil) {
        self.id = id
        self.name = name
        self.field = field
        self.isEnabled = isEnabled
        self.condition = condition
        self.wordCount = wordCount
        self.revision = revision
    }

    /// 索引のファイルの名前．id は取り込むときに作る UUID．同期のファイルから来た設定にも入るので，
    /// UUID の形でない id(「../」などでパスを差し込むもの)は設定を読むときに捨てる(hasValidIdentity)
    public var indexFileName: String { "\(id).tsv" }

    /// id が UUID の形で，revision があれば 64 桁の 16 進の小文字か
    public var hasValidIdentity: Bool {
        guard UUID(uuidString: id) != nil, id.count == 36 else { return false }
        guard let revision else { return true }
        return revision.count == 64 && revision.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    /// 分岐図に出す名前．分野があれば分野
    public var displayName: String { field.isEmpty ? name : field }
}

/// どの辞書を今効かせ，どれだけ優先するかを決める．
/// 上の辞書ほど優先度が高く(点数の差 DefaultSettings.importedDictionaryPriorityStep ずつ)，
/// 文脈の条件の辞書は，最近その辞書の語を確定した回数が足りなければ優先度を下げる(DefaultSettings.importedDictionaryContextPenalty)
public enum DictionaryActivation {
    public struct Active: Sendable, Equatable {
        public var dictionary: ImportedDictionary
        /// 語の点数に足す値(0 か負)
        public var costOffset: Float
    }

    /// - Parameters:
    ///   - applicationID: 入力先のアプリのバンドル ID
    ///   - recentHits: 辞書の id ごとの，最近確定したその辞書の語の数
    public static func active(_ dictionaries: [ImportedDictionary], applicationID: String?, recentHits: [String: Int]) -> [Active] {
        dictionaries.enumerated().compactMap { index, dictionary in
            guard dictionary.isEnabled else { return nil }
            var offset = -Float(index) * DefaultSettings.importedDictionaryPriorityStep
            switch dictionary.condition {
            case .always:
                break
            case .apps(let prefixes):
                guard let applicationID, prefixes.contains(where: { !$0.isEmpty && applicationID.hasPrefix($0) }) else { return nil }
            case .context:
                if recentHits[dictionary.id, default: 0] < DefaultSettings.importedDictionaryContextHits {
                    offset -= DefaultSettings.importedDictionaryContextPenalty
                }
            }
            return Active(dictionary: dictionary, costOffset: offset)
        }
    }
}
