import HajimeDomain

/// パレットの窓に出す内容(R-26)．描く側はこれをそのまま描き，判断はしない．
///
/// 窓は上から，探す欄・種類の切り替え(絵文字・記号・顔文字)・まとまりのタブ・見出し・文字のマス目・選んでいる文字の説明・キーの案内．
/// マス目は見えている行だけを渡す．全体の行の数と先頭の行の位置で，描く側はスクロールバーを描く．
/// 顔文字は横に長いので，1 行に cellsPerRow 個の広いマスを，マス目の幅(columns 個の四角いマスの幅)に等しく並べる
public struct PalettePanel: Sendable, Equatable {
    /// 種類の切り替えの 1 つ
    public struct Mode: Sendable, Equatable {
        public var kind: PaletteItem.Kind
        public var title: String
        public var isSelected: Bool

        public init(kind: PaletteItem.Kind, title: String, isSelected: Bool) {
            self.kind = kind
            self.title = title
            self.isSelected = isSelected
        }
    }

    /// まとまりのタブ．id は PaletteSection.Kind の値(PaletteTarget.tab で返す)
    public struct Tab: Sendable, Equatable {
        public var section: PaletteSection.Kind
        public var title: String
        /// アイコンを描けないときに代わりに見せる文字
        public var symbol: String
        public var isSelected: Bool

        public init(section: PaletteSection.Kind, title: String, symbol: String, isSelected: Bool) {
            self.section = section
            self.title = title
            self.symbol = symbol
            self.isSelected = isSelected
        }
    }

    public struct Cell: Sendable, Equatable {
        /// マスに描く文字(既定の肌の色にしたもの)
        public var text: String
        /// 読み上げに使う名前
        public var name: String
        public var isPinned: Bool

        public init(text: String, name: String, isPinned: Bool = false) {
            self.text = text
            self.name = name
            self.isPinned = isPinned
        }
    }

    public struct Row: Sendable, Equatable {
        /// 全体の中での行の位置(0 から)
        public var index: Int
        public var cells: [Cell]
        /// まとまりの最初の行か．描く側は行の上に区切りの線を引き，まとまりの名前を添える
        public var startsSection: Bool
        /// 行が属するまとまりの名前
        public var sectionTitle: String

        public init(index: Int, cells: [Cell], startsSection: Bool, sectionTitle: String) {
            self.index = index
            self.cells = cells
            self.startsSection = startsSection
            self.sectionTitle = sectionTitle
        }
    }

    /// マス目の中の位置
    public struct Position: Sendable, Hashable {
        public var row: Int
        public var column: Int

        public init(row: Int, column: Int) {
            self.row = row
            self.column = column
        }
    }

    /// 選んでいる文字の説明．出さない設定の項目は空にしてある
    public struct Preview: Sendable, Equatable {
        /// 入れる文字(肌の色を当てたもの)
        public var text: String
        /// 見出しの名前．日本語の名前(CLDR の日本語の短い名前など)．無ければ英語の名前
        public var name: String
        /// 見出しの名前を定めたところ(「CLDR」)．わからなければ nil
        public var nameSource: String?
        /// Unicode の名前．1 つの符号位置の文字は UCD の名前，並び(国旗・ZWJ・キーキャップ)は CLDR の英語の短い名前．
        /// 出さない設定のときと，名前の無いもの(顔文字)は空
        public var unicodeName: String
        /// unicodeName を定めたところ(「Unicode」「CLDR」)
        public var unicodeNameSource: String?
        /// 名前の読みと，ほかの読みのうち先頭のいくつか．見出しの名前と同じ読みは除く
        public var readings: [String]
        /// 「:bow:」の形
        public var shortcodes: [String]
        /// 「U+1F647」の形を 1 つの符号位置ごとに．顔文字は並べても長いだけなので空
        public var codePoints: [String]
        public var isPinned: Bool

        public init(text: String, name: String, nameSource: String? = nil, unicodeName: String = "", unicodeNameSource: String? = nil,
                    readings: [String] = [], shortcodes: [String] = [], codePoints: [String] = [], isPinned: Bool = false) {
            self.text = text
            self.name = name
            self.nameSource = nameSource
            self.unicodeName = unicodeName
            self.unicodeNameSource = unicodeNameSource
            self.readings = readings
            self.shortcodes = shortcodes
            self.codePoints = codePoints
            self.isPinned = isPinned
        }
    }

    /// 説明の欄に出す項目(設定)．描く側は，選んでいる文字によらずこれで欄の高さを決める(窓の大きさを中身で変えない)
    public struct PreviewFields: Sendable, Equatable {
        public var unicodeName: Bool
        public var readings: Bool
        public var shortcodes: Bool
        public var codePoints: Bool

        public init(unicodeName: Bool = true, readings: Bool = true, shortcodes: Bool = true, codePoints: Bool = true) {
            self.unicodeName = unicodeName
            self.readings = readings
            self.shortcodes = shortcodes
            self.codePoints = codePoints
        }

        /// タグ(ショートコードかコードポイント)の行を出すか
        public var chips: Bool { shortcodes || codePoints }
    }

    /// 肌の色を選ぶ帯．肌の色を変えない形から暗い形まで(SkinTone.allCases の順)
    public struct SkinTonePicker: Sendable, Equatable {
        public var options: [String]
        public var selected: Int

        public init(options: [String], selected: Int) {
            self.options = options
            self.selected = selected
        }
    }

    /// 前に出した内容からの動き．描く側はこれを見て，選択やタブの印を滑らせ，マス目の中身を入れ替える動きを付ける．
    /// 何が動いたかは core が決め，動きを付けるかどうか(OS の「視差効果を減らす」「アニメーション効果」)と動きの速さは描く側が決める
    public struct Motion: Sendable, Equatable {
        /// マス目の中身の入れ替わり方
        public enum Content: String, Sendable, Equatable, CaseIterable {
            /// 種類を後ろ(右の切り替え)へ移した．中身を左へ送る
            case next
            /// 種類を前(左の切り替え)へ移した．中身を右へ送る
            case previous
            /// 下のまとまりへ飛んだ．中身を上へ送る
            case down
            /// 上のまとまりへ飛んだ．中身を下へ送る
            case up
        }

        /// 選択が動いてきた元のマス．マス目の中身とスクロールの位置が前と同じときだけ(選択の枠を滑らせる)
        public var selectionFrom: Position?
        /// 前に選んでいた種類(種類の切り替えの印を滑らせる)
        public var modeFrom: PaletteItem.Kind?
        /// 前に選んでいたまとまり．タブの並びが前と同じときだけ(タブの印を滑らせる)
        public var tabFrom: PaletteSection.Kind?
        /// マス目の中身が入れ替わった
        public var content: Content?
        /// 肌の色の帯を開いた
        public var opensPicker: Bool
        /// 選んでいる文字のピン留めを切り替えた
        public var togglesPin: Bool

        public init(selectionFrom: Position? = nil, modeFrom: PaletteItem.Kind? = nil, tabFrom: PaletteSection.Kind? = nil, content: Content? = nil,
                    opensPicker: Bool = false, togglesPin: Bool = false) {
            self.selectionFrom = selectionFrom
            self.modeFrom = modeFrom
            self.tabFrom = tabFrom
            self.content = content
            self.opensPicker = opensPicker
            self.togglesPin = togglesPin
        }

        /// 動くものが無い
        public var isEmpty: Bool { self == Motion() }
    }

    /// 足元に出すキーの案内
    public struct Hint: Sendable, Equatable {
        public var key: String
        public var action: String

        public init(key: String, action: String) {
            self.key = key
            self.action = action
        }
    }

    public var modes: [Mode]
    /// 探す欄に出す文字(打っている途中のローマ字を含む)
    public var query: String
    /// 探す欄が空のときに薄く出す案内
    public var placeholder: String
    public var tabs: [Tab]
    /// マス目の上に出す見出し(見えている先頭の行のまとまりの名前．探しているときは結果の数)
    public var heading: String
    public var rows: [Row]
    /// 全体の行の数と，見えている先頭の行の位置
    public var rowCount: Int
    public var firstRow: Int
    /// 列の数と，一度に見せる行の数．顔文字のように説明の欄が低い種類は，その分の行を足してある
    public var columns: Int
    public var visibleRows: Int
    /// 1 行のマスの数．四角いマスなら columns と同じ．顔文字の広いマスなら少なく，マスの幅はマス目の幅をこれで割ったもの
    public var cellsPerRow: Int
    public var selection: Position?
    /// 選んでいる文字の説明．出さない設定のときと，選んでいる文字が無いときは nil
    public var preview: Preview?
    /// 説明の欄を出すか(設定)．出すなら，選んでいる文字が無いときも欄の場所を空けておく(窓の大きさを中身で変えない)
    public var showsPreview: Bool
    /// 説明の欄に出す項目(設定)
    public var previewFields: PreviewFields
    /// 既定の肌の色(足元の肌の色のボタンに出す)
    public var skinTone: SkinTone
    public var skinTonePicker: SkinTonePicker?
    /// 文字が無いときの知らせ(「見つかりません」「読み込んでいます」)
    public var message: String?
    public var hints: [Hint]
    /// 前に出した内容からの動き
    public var motion: Motion

    public init(modes: [Mode], query: String, placeholder: String, tabs: [Tab], heading: String, rows: [Row], rowCount: Int, firstRow: Int,
                columns: Int, visibleRows: Int, cellsPerRow: Int? = nil, selection: Position?, preview: Preview?, showsPreview: Bool,
                previewFields: PreviewFields = PreviewFields(), skinTone: SkinTone, skinTonePicker: SkinTonePicker?, message: String?, hints: [Hint],
                motion: Motion = Motion()) {
        self.modes = modes
        self.query = query
        self.placeholder = placeholder
        self.tabs = tabs
        self.heading = heading
        self.rows = rows
        self.rowCount = rowCount
        self.firstRow = firstRow
        self.columns = columns
        self.visibleRows = visibleRows
        self.cellsPerRow = max(min(cellsPerRow ?? columns, columns), 1)
        self.selection = selection
        self.preview = preview
        self.showsPreview = showsPreview
        self.previewFields = previewFields
        self.skinTone = skinTone
        self.skinTonePicker = skinTonePicker
        self.message = message
        self.hints = hints
        self.motion = motion
    }
}

extension PalettePanel: CustomStringConvertible, CustomDebugStringConvertible {
    // 探した語は入力の中身なので，ログには行の数と位置だけを出す
    public var description: String { "PalettePanel(rows: \(rowCount), firstRow: \(firstRow), query: \(query.count))" }
    public var debugDescription: String { description }
}

/// パレットのマス目のまとまり．ピン留め・よく使う文字・表のまとまり・探した結果
public struct PaletteSection: Sendable, Equatable {
    public enum Kind: Sendable, Hashable {
        case pinned
        case frequent
        case category(PaletteCategory)
        case results
    }

    public var kind: Kind
    public var items: [PaletteItem]

    public init(kind: Kind, items: [PaletteItem]) {
        self.kind = kind
        self.items = items
    }

    public var title: String {
        switch kind {
        case .pinned: PaletteStrings.pinned
        case .frequent: PaletteStrings.frequent
        case .category(let category): category.title
        case .results: PaletteStrings.results
        }
    }
}

/// パレットの窓をマウスで押した対象．窓の描き方を知るアプリ側が押した位置から決め，InputSession.palette に渡す
public enum PaletteTarget: Sendable, Hashable {
    /// マスを押した(文字を入れる)
    case cell(PalettePanel.Position)
    /// マスの上にポインタを置いた(選ぶだけで入れない)
    case hover(PalettePanel.Position)
    case tab(PaletteSection.Kind)
    case mode(PaletteItem.Kind)
    /// 行の数だけスクロールした(下が正)
    case scroll(Int)
    /// 肌の色の帯の 1 つを押した
    case skinTone(SkinTone)
    /// 足元の肌の色のボタンを押した(帯を開く・閉じる)
    case skinToneButton
    /// 説明のピン留めのボタンを押した
    case pin
    /// 窓を閉じた
    case close
}

/// パレットの窓に出す言葉．macOS と Windows で同じものを出す
public enum PaletteStrings {
    public static let emoji = "絵文字"
    public static let symbol = "記号"
    public static let kaomoji = "顔文字"
    public static let pinned = "ピン留め"
    public static let frequent = "よく使う"
    public static let results = "検索結果"
    public static let emojiPlaceholder = "絵文字を検索"
    public static let symbolPlaceholder = "記号を検索"
    public static let kaomojiPlaceholder = "顔文字を検索"
    public static let notFound = "見つかりません。英語の名前やショートコードでも探せます"
    public static let loading = "読み込んでいます"
    public static let insert = "入力"
    public static let insertAndContinue = "続けて入力"
    public static let category = "分類"
    public static let switchKind = "種類"
    public static let skinTone = "肌の色"
    public static let pin = "ピン留め"
    public static let close = "閉じる"
    /// 説明の欄で，名前を定めたところ(見出しに添える・Unicode の名前の行を見分ける)
    public static let unicodeSource = "Unicode"
    public static let cldrSource = "CLDR"
    /// Hajime IME が付けた記号の名前(tools/palette/names.txt など)
    public static let hajimeSource = "Hajime IME"
    /// 説明の欄で読みを並べるときの区切り
    public static let readingSeparator = "、"
    /// タブにアイコンを描けないときに代わりに見せる文字
    public static let pinnedSymbol = "📌"
    public static let frequentSymbol = "🕘"
    public static let resultsSymbol = "🔍"
    /// 既定の肌の色を選ぶ帯に見せる絵文字
    public static let skinToneSample = PaletteItem(kind: .emoji, category: .people, text: "👋", skinTones: ["👋🏻", "👋🏼", "👋🏽", "👋🏾", "👋🏿"])

    public static func title(of kind: PaletteItem.Kind) -> String {
        switch kind {
        case .emoji: emoji
        case .symbol: symbol
        case .kaomoji: kaomoji
        }
    }

    /// 探す欄が空のときに薄く出す案内
    public static func placeholder(of kind: PaletteItem.Kind) -> String {
        switch kind {
        case .emoji: emojiPlaceholder
        case .symbol: symbolPlaceholder
        case .kaomoji: kaomojiPlaceholder
        }
    }

    public static func resultCount(_ count: Int) -> String { "\(count) 件" }
}
