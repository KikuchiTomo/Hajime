import S90Domain

/// InputSession がアダプタに頼む画面への操作．アダプタはこれを OS の API に置き換えるだけで，判断はしない．
public enum ClientAction: Sendable, Equatable {
    /// 文字を確定して入力欄に入れる
    case commit(String)
    /// 変換中の文字を表示する(空なら消す)
    case setMarkedText(MarkedText)
    case showCandidates(CandidatePanel)
    /// 文節格子を出す．hideCandidates で一覧と一緒に消える
    case showLattice(LatticePanel)
    case hideCandidates
    /// 入力モードを切り替えたことを知らせる札を出す
    case showModeIndicator(InputMode)
    /// OS の入力メニューの表示を，このモードに合わせる
    case selectMode(InputMode)
    /// 入力方式を切り替える(設定に保存する)．R-05
    case selectInputStyle(InputStyle)
}

/// 処理の結果．handled が false なら，キーは入力先のアプリにそのまま渡る
public struct KeyResult: Sendable, Equatable {
    public var handled: Bool
    public var actions: [ClientAction]

    public init(handled: Bool, actions: [ClientAction] = []) {
        self.handled = handled
        self.actions = actions
    }

    public static let passThrough = KeyResult(handled: false)
}

/// 変換中の文字．区間ごとに下線の種類を変える
public struct MarkedText: Sendable, Equatable {
    public enum Style: Sendable, Equatable {
        /// 打っている途中の読み．細い下線
        case reading
        /// ライブ変換で変換した部分．細い下線
        case converted
        /// 候補を選んでいる区間．太い下線
        case focused
        /// タイプミスを補正した部分．点線の下線(docs/dev/DESIGN-SYSTEM.md)
        case correction
    }

    public struct Segment: Sendable, Equatable {
        public var text: String
        public var style: Style

        public init(_ text: String, style: Style) {
            self.text = text
            self.style = style
        }
    }

    public var segments: [Segment]

    public init(_ segments: [Segment]) {
        self.segments = segments.filter { !$0.text.isEmpty }
    }

    public static let empty = MarkedText([])

    public var text: String { segments.map(\.text).joined() }
    public var isEmpty: Bool { segments.isEmpty }
}

/// 候補ウィンドウに出す内容
public struct CandidatePanel: Sendable, Equatable {
    public struct Variant: Sendable, Equatable {
        public var label: String
        public var isAvailable: Bool

        public init(label: String, isAvailable: Bool) {
            self.label = label
            self.isAvailable = isAvailable
        }
    }

    public struct Entry: Sendable, Equatable {
        public var text: String
        /// 「入力のまま」などの添え書き
        public var annotation: String?

        public init(text: String, annotation: String?) {
            self.text = text
            self.annotation = annotation
        }
    }

    public enum Focus: Sendable, Equatable {
        case candidate
        case variants
    }

    /// 種類の行．出さない設定のときは空
    public var variants: [Variant]
    public var selectedVariant: Int?
    /// 今のページの候補
    public var entries: [Entry]
    /// ページの中で選んでいる候補．種類の行にいるときは nil
    public var selectedEntry: Int?
    public var focus: Focus
    /// 候補全体の中での位置(1 から数える)と総数．足元に出す
    public var position: Int
    public var total: Int
    /// 補正の直後など，足元に出す案内
    public var note: String?

    public init(variants: [Variant], selectedVariant: Int?, entries: [Entry], selectedEntry: Int?, focus: Focus, position: Int, total: Int, note: String?) {
        self.variants = variants
        self.selectedVariant = selectedVariant
        self.entries = entries
        self.selectedEntry = selectedEntry
        self.focus = focus
        self.position = position
        self.total = total
        self.note = note
    }
}

/// 分岐図に出す内容(ADR 0007)．文を 1 本の幹として文節を横に並べ，
/// 注目している文節から下へ変換の候補の枝，上へ字種の枝を伸ばす．迷う文節には次の候補を 1 つだけ薄く添える
public struct LatticePanel: Sendable, Equatable {
    public struct Column: Sendable, Equatable {
        /// 幹に出す，今選んでいるもの
        public var text: String
        /// 下の枝に並べる変換の候補(今のページ)．注目していない文節では空
        public var alternatives: [String]
        /// 下の枝で選んでいる位置．上の枝(字種)を選んでいるときは nil
        public var selectedAlternative: Int?
        /// 上の枝に並べる字種．幹に近い順．注目していない文節では空
        public var variants: [String]
        public var selectedVariant: Int?
        public var isFocused: Bool
        /// 迷う文節か(第 1 候補と 2 番目の差が小さい)
        public var isUncertain: Bool
        /// 利用者が選び直した文節か
        public var isDecided: Bool
        /// 注目していない迷う文節に薄く添える，次の候補
        public var preview: String?

        public init(text: String, alternatives: [String] = [], selectedAlternative: Int? = nil, variants: [String] = [], selectedVariant: Int? = nil,
                    isFocused: Bool, isUncertain: Bool, isDecided: Bool = false, preview: String? = nil) {
            self.text = text
            self.alternatives = alternatives
            self.selectedAlternative = selectedAlternative
            self.variants = variants
            self.selectedVariant = selectedVariant
            self.isFocused = isFocused
            self.isUncertain = isUncertain
            self.isDecided = isDecided
            self.preview = preview
        }
    }

    public var columns: [Column]
    /// 注目している文節の候補のうち，今のページの先頭が何番目か(1 から)と全体の数
    public var position: Int
    public var total: Int
    /// 説明の行に出す知らせ(打ち間違いを直したことなど)
    public var note: String?

    public init(columns: [Column], position: Int = 1, total: Int = 0, note: String? = nil) {
        self.columns = columns
        self.position = position
        self.total = total
        self.note = note
    }
}
