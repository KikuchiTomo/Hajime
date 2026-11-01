import HajimeDomain

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
    /// 設定の画面を開く(キーで開くとき)
    case openSettings
    /// ライブ変換を切り替える(設定に保存する)
    case toggleLiveConversion
    /// 手書きで文字を探す窓を出す(R-14)．選んだ文字は commit と同じく入力先に入れる
    case showHandwriting
    /// 入力位置の近くに短い案内を出す(打ち間違いを直したこと・「もしかして」)．hideCandidates で一緒に消える
    case showNote(Note)
    /// 打ち間違いの訂正を求め終わるまで変換を待つ．入力コントローラは訂正を求めて渡し(provideCorrections)，
    /// resumeConversion で変換を続ける．訂正を求めない作りなら resumeConversion をすぐ呼ぶ
    case awaitCorrections
    /// 再変換のキーを押した．入力先で選んでいる文字を読んで InputSession.reconvert に渡す(入力先を読めるのはアプリ側)
    case requestReconversion
    /// コマンドの候補を選んで確定した．アプリ側(macOS は入力メソッドのプロセス，Windows はエンジンのプロセス)がコマンドを動かす．
    /// 入力先のアプリ(Windows の DLL)には渡さない
    case runCommand(LauncherCommand)
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
    /// 入力位置(先頭からの文字数)．nil なら末尾．文節をその場で打ち直しているときは，打ち直している文節の終わりに置く
    public var caret: Int?

    public init(_ segments: [Segment], caret: Int? = nil) {
        self.segments = segments.filter { !$0.text.isEmpty }
        self.caret = caret
    }

    /// 入力位置の前の文字列
    public var textBeforeCaret: String { caret.map { String(text.prefix($0)) } ?? text }

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
        /// 打ち間違いを直した部分(text の中の文字の位置)．補正の点線の下線を引く．直していなければ nil
        public var corrected: Range<Int>?
        /// コマンドの候補なら，その種類．描く側は種類のアイコンを文字の前に添え，札(annotation)をアクセントの色にする
        public var command: LauncherCommand.Kind?

        public init(text: String, annotation: String?, corrected: Range<Int>? = nil, command: LauncherCommand.Kind? = nil) {
            self.text = text
            self.annotation = annotation
            self.corrected = corrected
            self.command = command
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
    public var note: Note?
    /// 連想の一覧を出しているときの見出し(R-18)．ふつうの候補なら nil
    public var association: AssociationHeading?
    /// 選んでいる候補に連想があるときの知らせ(「⌃Tab 連想」)．無ければ nil
    public var associationHint: String?
    /// 窓の左端をそろえる，組み立て中の文字の位置(UTF-16 の数)．nil なら組み立て中の文字の頭．
    /// 打っているあいだに最後の文節だけの候補を出すときは，その文節の頭にそろえる
    public var anchor: Int?
    /// 選んでいる候補の同音異義語の使い分け(R-08)．候補と足元のあいだに出す
    public var homophone: HomophoneNote?

    public init(variants: [Variant], selectedVariant: Int?, entries: [Entry], selectedEntry: Int?, focus: Focus, position: Int, total: Int, note: Note?) {
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
        /// 打ち間違いを直した部分を含む文節か．補正の印を付ける
        public var isCorrected = false
        /// 注目していない迷う文節に薄く添える，次の候補
        public var preview: String?
        /// 注目している文節を 1 文字短く・長くしたときの文節(足元に「⇧← 入れ　⇧→ 入れると」と見せる)
        public var shorter: String?
        public var longer: String?
        /// 選んでいる候補の誤用や文の直し方の注釈(R-08)
        public var usageNote: String?
        /// 選んでいる候補の同音異義語の使い分け(R-08)
        public var homophone: HomophoneNote?
        /// 下の枝の候補ごとの添え書き(alternatives と同じ数)．打ったままの候補は「入力のまま」，直した候補は「修正」，コマンドは「コマンド」
        public var alternativeNotes: [String?] = []
        /// 下の枝の候補ごとのコマンドの種類(alternatives と同じ数)．コマンドでない候補は nil
        public var alternativeCommands: [LauncherCommand.Kind?] = []
        /// 選んでいる候補が取り込んだ辞書の語なら，その辞書の名前(分野)．足元に小さく出す(R-16)
        public var sourceName: String?
        /// 文節を区切っているとき(⇧↓)の，区切れる位置で分けた文節．区切っていなければ nil
        public var split: Split?

        /// 区切れる位置の案内．幹に pieces を並べ，あいだに 1 から番号を振る
        public struct Split: Sendable, Equatable {
            /// 語の切れ目で分けた文節(「問題」「が」「ある」)．変換した語で分けられなければ読みを分けたもの
            public var pieces: [String]

            public init(pieces: [String]) {
                self.pieces = pieces
            }
        }

        public init(text: String, alternatives: [String] = [], selectedAlternative: Int? = nil, variants: [String] = [], selectedVariant: Int? = nil,
                    isFocused: Bool, isUncertain: Bool, isDecided: Bool = false, preview: String? = nil, shorter: String? = nil, longer: String? = nil) {
            self.shorter = shorter
            self.longer = longer
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
    public var note: Note?
    /// 連想の一覧を出しているときの見出し(R-18)．注目している文節の下の枝が連想の語になる．ふつうの分岐図なら nil
    public var association: AssociationHeading?
    /// 注目している文節で選んでいる候補に連想があるときの知らせ(「⌃Tab 連想」)．無ければ nil
    public var associationHint: String?

    public init(columns: [Column], position: Int = 1, total: Int = 0, note: Note? = nil) {
        self.columns = columns
        self.position = position
        self.total = total
        self.note = note
    }
}

/// 連想の一覧の見出し(R-18)．元の語と，今出している意味のまとまり
public struct AssociationHeading: Sendable, Equatable {
    /// 連想の元にした語
    public var headword: String
    /// 今のまとまりの意味の説明．説明の無いまとまりは空
    public var label: String
    /// 今のまとまりの位置(1 から)とまとまりの数
    public var group: Int
    public var groupCount: Int

    public init(headword: String, label: String, group: Int, groupCount: Int) {
        self.headword = headword
        self.label = label
        self.group = group
        self.groupCount = groupCount
    }
}

extension AssociationHeading: CustomStringConvertible, CustomDebugStringConvertible {
    // 元の語は入力内容なので，ログには位置だけを出す
    public var description: String { "AssociationHeading(group: \(group)/\(groupCount))" }
    public var debugDescription: String { description }
}

/// 候補の窓の足元や入力位置の下に出す案内．見た目を作り込めるよう，部品に分けて渡す
/// (「修正」と打ったままの字と戻すキーを，色・取り消し線・キーの札で描き分ける)
public struct Note: Sendable, Equatable {
    public enum Tone: String, Sendable, Equatable {
        /// 打ち間違いを直した
        case correction
        /// 直さずに「もしかして」と示す
        case suggestion
        /// ほかの知らせ(学習から削除した，など)
        case info
    }

    public var tone: Tone
    /// 主な語(「修正」「もしかして」「学習から削除しました」)
    public var title: String
    /// 対象の字．correction では直す前の字(取り消し線で見せる)，suggestion では直した字
    public var subject: String?
    /// キーの名前と，そのキーでできること(「Esc」「戻す」)．キーが割り当てられていなければ nil
    public var key: String?
    public var keyAction: String?

    public init(tone: Tone, title: String, subject: String? = nil, key: String? = nil, keyAction: String? = nil) {
        self.tone = tone
        self.title = title
        self.subject = subject
        self.key = key
        self.keyAction = keyAction
    }

    /// ほかの知らせ
    public static func info(_ text: String) -> Note { Note(tone: .info, title: text) }

    /// 1 行の文として読んだもの(読み上げ，部品を描き分けない画面)
    public var text: String {
        var parts = [title]
        if let subject { parts.append("「\(subject)」") }
        var line = parts.joined()
        if let key, let keyAction { line += (line.isEmpty ? "" : "　") + "\(key) \(keyAction)" }
        return line
    }
}

extension CandidatePanel {
    /// 打ち間違いを直した候補の添え書き．描く側で補正の色の札にする
    public static let correctedAnnotation = "修正"
    /// コマンドの候補の添え書き．描く側でアクセントの色の札にする
    public static let commandAnnotation = "コマンド"
}
