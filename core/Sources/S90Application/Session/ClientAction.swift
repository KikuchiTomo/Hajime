import S90Domain

/// InputSession がアダプタに頼む画面への操作．アダプタはこれを OS の API に置き換えるだけで，判断はしない．
public enum ClientAction: Sendable, Equatable {
    /// 文字を確定して入力欄に入れる
    case commit(String)
    /// 変換中の文字を表示する(空なら消す)
    case setMarkedText(MarkedText)
    case showCandidates(CandidatePanel)
    case hideCandidates
    /// 入力モードを切り替えたことを知らせる札を出す
    case showModeIndicator(InputMode)
    /// OS の入力メニューの表示を，このモードに合わせる
    case selectMode(InputMode)
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
    }

    public struct Entry: Sendable, Equatable {
        public var text: String
        /// 「入力のまま」などの添え書き
        public var annotation: String?
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
}
