/// 専門用語の辞書の分野(R-29)．同梱の辞書の terms.tsv の 4 列目の id で，設定の項目の名前(termFields.<id>)にもなる．
/// 分野を消したり id を変えたりすると，利用者が切った分野の設定が効かなくなるので，足すだけにする
public enum TermField: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case computing, medicine, biology, chemistry, physics, mathematics, earth, engineering, architecture, law, economics, business
    case linguistics, philosophy, religion, music, design, food, sports, games, military, agriculture, performingArts, history

    /// 設定の画面と分岐図(どの辞書の語か)に出す名前．macOS と Windows で同じものを出す(Windows の設定の画面は strings.rs の TERM_FIELDS)
    public var name: String {
        switch self {
        case .computing: "情報技術"
        case .medicine: "医学"
        case .biology: "生物学"
        case .chemistry: "化学"
        case .physics: "物理学"
        case .mathematics: "数学"
        case .earth: "地学・天文学"
        case .engineering: "工学"
        case .architecture: "建築"
        case .law: "法律・政治"
        case .economics: "経済・金融"
        case .business: "ビジネス"
        case .linguistics: "言語学"
        case .philosophy: "哲学・思想"
        case .religion: "宗教・神話"
        case .music: "音楽"
        case .design: "美術・デザイン"
        case .food: "料理・食品"
        case .sports: "スポーツ"
        case .games: "囲碁・将棋・ゲーム"
        case .military: "軍事"
        case .agriculture: "農林水産"
        case .performingArts: "芸能・映像"
        case .history: "歴史・考古学"
        }
    }
}

/// 分野ごとに専門用語の辞書を使うか(R-29)．既定はすべて使う．設定のファイルに無い分野(あとから足した分野)も使う
public struct TermFieldSettings: Sendable, Equatable, Codable {
    public var computing = true
    public var medicine = true
    public var biology = true
    public var chemistry = true
    public var physics = true
    public var mathematics = true
    public var earth = true
    public var engineering = true
    public var architecture = true
    public var law = true
    public var economics = true
    public var business = true
    public var linguistics = true
    public var philosophy = true
    public var religion = true
    public var music = true
    public var design = true
    public var food = true
    public var sports = true
    public var games = true
    public var military = true
    public var agriculture = true
    public var performingArts = true
    public var history = true

    public init() {}

    public subscript(field: TermField) -> Bool {
        get { self[keyPath: Self.keyPath(of: field)] }
        set { self[keyPath: Self.keyPath(of: field)] = newValue }
    }

    /// 使う分野
    public var enabledFields: Set<TermField> { Set(TermField.allCases.filter { self[$0] }) }

    private static func keyPath(of field: TermField) -> WritableKeyPath<TermFieldSettings, Bool> {
        switch field {
        case .computing: \.computing
        case .medicine: \.medicine
        case .biology: \.biology
        case .chemistry: \.chemistry
        case .physics: \.physics
        case .mathematics: \.mathematics
        case .earth: \.earth
        case .engineering: \.engineering
        case .architecture: \.architecture
        case .law: \.law
        case .economics: \.economics
        case .business: \.business
        case .linguistics: \.linguistics
        case .philosophy: \.philosophy
        case .religion: \.religion
        case .music: \.music
        case .design: \.design
        case .food: \.food
        case .sports: \.sports
        case .games: \.games
        case .military: \.military
        case .agriculture: \.agriculture
        case .performingArts: \.performingArts
        case .history: \.history
        }
    }

    // 項目の名前は TermField の id．無い項目と読めない項目は使う(既定のまま)
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ field: TermField) { stringValue = field.rawValue }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        for field in TermField.allCases {
            self[field] = (try? container.decodeIfPresent(Bool.self, forKey: Key(field))) ?? true
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for field in TermField.allCases {
            try container.encode(self[field], forKey: Key(field))
        }
    }
}

/// 専門用語の辞書の 1 語と，その分野
public struct TermWord: Sendable, Equatable, Hashable {
    public var word: DictionaryWord
    public var field: TermField
    /// 通常の辞書に同じ読みの語があるか(辞書を作るときに決める)．あれば点数を下げ，ふだんの語を押しのけないようにする
    public var hasHomophones: Bool

    public init(word: DictionaryWord, field: TermField, hasHomophones: Bool = false) {
        self.word = word
        self.field = field
        self.hasHomophones = hasHomophones
    }
}
