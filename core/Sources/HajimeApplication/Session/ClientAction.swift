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
    /// 入力モードを切り替えたことを知らせるタグを出す
    case showModeIndicator(InputMode)
    /// OS の入力メニューの表示を，このモードに合わせる
    case selectMode(InputMode)
    /// 入力方式を切り替える(設定に保存する)．R-05
    case selectInputStyle(InputStyle)
    /// 設定の画面を開く(キーで開くとき)
    case openSettings
    /// 単語の登録を始める(設定のユーザー辞書の画面を開き，語と読みを入力欄に入れる)．
    /// word が nil なら，アプリ側が入力先で選んでいる文字を語にする(入力先を読めるのはアプリ側)．読みが分からなければ reading は nil
    case openWordRegistration(word: String?, reading: String?)
    /// 設定のユーザー辞書の画面を開く
    case openUserDictionary
    /// 入力メニューを入力位置に出す
    case openMenu
    /// ライブ変換を切り替える(設定に保存する)
    case toggleLiveConversion
    /// 手書きで文字を探す窓を出す(R-14)．選んだ文字は commit と同じく入力先に入れる
    case showHandwriting
    /// 絵文字と記号のパレットを出す(出していれば中身を替える．R-26)．窓はフォーカスを奪わず，キーは InputSession が受ける
    case showPalette(PalettePanel)
    /// パレットを閉じる
    case hidePalette
    /// 入力位置の近くに短い案内を出す(打ち間違いを直したこと・「もしかして」)．hideCandidates で一緒に消える
    case showNote(Note)
    /// 組み立て中の文字のすぐ右に，打っている語句に続く予測を出す．変換の候補の窓とは別の小さな窓．nil なら消す．
    /// 候補の窓を出す・消す操作(showCandidates・showLattice・hideCandidates)では消えない．InputSession は予測が変わったときだけ送り，
    /// 打ち終わったときと分岐図・一覧で選び始めたときに nil を送る
    case showPrediction(Prediction?)
    /// 次に出す組み立て中の文字で，入力位置の前の確定済みの文字(UTF-16 で数えた長さ)を置き換える．
    /// 予測の確定を取り消すときに，確定した語句を補う前の読みに戻すのに使う．InputSession は入力位置の前の文字列で確かめてから送る
    case replacePrecedingText(Int)
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
        /// コマンドの候補なら，その種類．描く側は種類のアイコンを文字の前に添え，タグ(annotation)をアクセントの色にする
        public var command: LauncherCommand.Kind?
        /// タグ(annotation)がユーザー辞書の語のコメントか．描く側はタグを押せるようにし，押したら PointerTarget.comment を渡す
        public var hasComment: Bool
        /// 候補の文字のすぐあとに控えめに添える説明(絵文字の名前)．描く側は薄い色の 1 段小さい文字にし，候補の文字とベースラインをそろえる
        public var detail: String?

        public init(text: String, annotation: String?, corrected: Range<Int>? = nil, command: LauncherCommand.Kind? = nil, hasComment: Bool = false,
                    detail: String? = nil) {
            self.text = text
            self.annotation = annotation
            self.corrected = corrected
            self.command = command
            self.hasComment = hasComment
            self.detail = detail
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
    public var associationHint: AssociationHint?
    /// 窓の左端をそろえる，組み立て中の文字の位置(UTF-16 の数)．nil なら組み立て中の文字の頭．
    /// 打っているあいだに最後の文節だけの候補を出すときは，その文節の頭にそろえる
    public var anchor: Int?
    /// 選んでいる候補の語の意味と同音異義語の使い分け(R-08)
    public var homophone: HomophoneNote?
    /// 語の意味を候補の右に出すか，下に出すか(設定)
    public var meaningPlacement = MeaningPlacement.side
    /// 候補に番号を振るか．番号キーで選べない窓(選び始める前の入力中の候補の窓など)では振らない．
    /// 番号キーはそのまま文字になるので，振ると選べるように見えてしまう
    public var showsNumbers = true
    /// 候補を表に広げたとき(KeymapCommand.expandCandidates)の 1 列の候補の数．entries を上から下へ詰め，列を左から右へ並べる．
    /// 広げていなければ nil(1 列)
    public var columnLength: Int?
    /// 文節ごとの一覧で，注目している文節をその場で打ち直している(⇧⌫)．entries は打ち直す前の候補で，
    /// 描く側は薄く出して選んでいる形にしない(selectedEntry は nil)．候補は変換したときに出し直す
    public var isEditing = false

    /// 列の数．広げていなければ 1
    public var columnCount: Int {
        guard let columnLength, columnLength > 0 else { return 1 }
        return max((entries.count + columnLength - 1) / columnLength, 1)
    }

    /// 番号キーで選べる列．表では選んでいる候補の列(字種の行にいるときは先頭の列)だけに番号を振る
    public var numberedColumn: Int {
        guard let columnLength, columnLength > 0, focus == .candidate, let selectedEntry else { return 0 }
        return selectedEntry / columnLength
    }

    /// entries の index 番目の候補の番号の列に出す番号(1 から)と，番号キーで選べるか．
    /// 番号の列はどの候補でも取るので，選べない番号(表のほかの列，選び始める前の入力中の候補の窓)も出して列を空に見せない．
    /// 選べないことは描く側が薄さで示す
    public func displayedNumber(ofEntry index: Int) -> (number: Int, selectable: Bool)? {
        guard entries.indices.contains(index) else { return nil }
        if let number = number(ofEntry: index) { return (number, true) }
        guard let columnLength, columnLength > 0 else { return (index + 1, false) }
        return (index % columnLength + 1, false)
    }

    /// entries の index 番目の候補に振る番号(1 から)．番号を振らない候補なら nil
    public func number(ofEntry index: Int) -> Int? {
        guard showsNumbers, entries.indices.contains(index) else { return nil }
        guard let columnLength, columnLength > 0 else { return index + 1 }
        return index / columnLength == numberedColumn ? index % columnLength + 1 : nil
    }

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
        /// 下の枝の候補ごとに，添え書き(alternativeNotes)がユーザー辞書の語のコメントか(alternatives と同じ数)．コメントのある候補が無ければ空．
        /// 描く側は添え書きを押せるようにし，押したら PointerTarget.comment を渡す
        public var alternativeComments: [Bool] = []
        /// 下の枝の候補ごとに，文字のすぐあとに控えめに添える説明(alternatives と同じ数．絵文字の名前)．添えるものが無いページでは空
        public var alternativeDetails: [String?] = []
        /// 選んでいる候補が取り込んだ辞書の語なら，その辞書の名前(分野)．足元に小さく出す(R-16)
        public var sourceName: String?
        /// 文節を区切っているとき(⇧↓)の，区切れる位置で分けた文節．区切っていなければ nil
        public var split: Split?
        /// この文節へ移るキーの名前(分岐図の丸の上に出す．KeymapCommand.segmentJumps)．キーが割り当てられていない文節と，9 番目からの文節は nil
        public var jumpKey: String?
        /// 上の枝の文字種ごとの，その文字種にするキーの名前(variants と同じ数)．キーの無い文字種は nil．キーを出さないときは空
        public var variantKeys: [String?] = []
        /// その場で打ち直している文節(⇧⌫)．text は打っている読み(変換しない)．枝(alternatives・variants)は打ち直す前の候補で，
        /// 描く側は薄く出して選んでいる形にしない(selectedAlternative・selectedVariant は nil)．候補は変換したときに出し直す
        public var isEditing = false

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
    public var associationHint: AssociationHint?
    /// 語の意味(Column.homophone)を候補の枝の右に出すか，下に出すか(設定)
    public var meaningPlacement = MeaningPlacement.side
    /// 矢印キーで木をたどっていて，今いる所が幹の上(文節)か．描く側は，文節を強い選択にし，選んでいる候補を控えめにする
    public var trunkFocused = false
    /// 候補の 1 ページの数(ページの位置を出すのに使う)．分からなければ 0
    public var pageSize = 0
    /// 選んでいる候補の先の枝(語の意味・連想・変換マクロ)．先の枝を別々の丸として出す作り(InputSession の branchStations)のときだけ入る
    public var detail: BranchDetail?
    /// キーの案内を，修飾キーを押し続けているあいだだけ出すか(設定の「分岐図のキーの案内を常に表示」がオフ)．
    /// 描く側は，案内の場所を空けておき，押し続けている修飾キーを使うキーの案内だけを出す．false なら常に出す
    public var hintsOnHold = false
    /// 表示項目を減らす設定で，注目している文節の文字種の枝を畳んでいるか．畳んでいる枝は中身(Column.variants)を入れない．
    /// 描く側は，続きがある印(端へ向けて透かした線)だけを出す
    public var collapsesVariants = false
    /// 表示項目を減らす設定で，選んでいる候補の先の枝(語の意味・連想)を畳んでいるか．畳んでいる枝は中身(Column.homophone・associationHint)を入れない
    public var collapsesDetail = false

    public init(columns: [Column], position: Int = 1, total: Int = 0, note: Note? = nil) {
        self.columns = columns
        self.position = position
        self.total = total
        self.note = note
    }
}

/// 分岐図で，選んでいる候補の先に伸ばす枝．語の意味・連想・変換マクロを，それぞれ 1 つの丸として並べる(機能ごとに独立した置き場所)．
/// 矢印キーで，候補 → 丸 → 丸の中身(連想の語・マクロの結果)とたどる
public struct BranchDetail: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case meaning
        case association
        case macro
    }

    public struct Station: Sendable, Equatable {
        public var kind: Kind
        /// 丸の見出し(「意味」「連想」「マクロ」)
        public var title: String

        public init(kind: Kind, title: String) {
            self.kind = kind
            self.title = title
        }
    }

    public var stations: [Station]
    /// 今いる丸の位置．候補にいるあいだは nil
    public var current: Int?
    /// 今いる丸の中身(連想の語・マクロの結果)の今のページ．意味の丸と，候補にいるあいだは空
    public var items: [String] = []
    /// 中身の中で選んでいる位置．丸の上にいるあいだは nil
    public var selectedItem: Int?
    /// 中身の説明(連想のまとまりの意味)．無ければ空
    public var label = ""
    /// 中身のまとまりの位置(1 から)と数．連想は意味ごとにまとまりがある
    public var group = 1
    public var groupCount = 1
    /// 中身の今のページの先頭が何番目か(1 から)と，まとまりの中の全体の数
    public var position = 1
    public var total = 0
    /// 中身の 1 ページの数
    public var pageSize = 0
    /// 中身に入っているあいだの，元の候補(今のページ)と選んでいた位置．候補の列に控えめに出す
    public var candidates: [String] = []
    public var selectedCandidate: Int?

    public init(stations: [Station], current: Int? = nil) {
        self.stations = stations
        self.current = current
    }
}

extension BranchDetail: CustomStringConvertible, CustomDebugStringConvertible {
    // 中身と候補は入力内容なので，ログには数だけを出す
    public var description: String { "BranchDetail(stations: \(stations.count), items: \(items.count))" }
    public var debugDescription: String { description }
}

/// 打っているあいだに，打っている語句に続くと予測した語句．変換の候補とは体験が違うので，候補の窓に混ぜず別の窓に出す．
/// 打った部分(typed)はふつうの文字の色，予測で補う部分(completion)は薄い色で描き，確定のキーをキーキャップで添える
public struct Prediction: Sendable, Equatable {
    /// 予測した語句のうち，打った(組み立て中の文字に見えている)部分．見えている字と頭が重ならなければ空
    public var typed: String
    /// 予測で補う部分
    public var completion: String
    /// 予測を確定するキーの名前．キーの案内を出さない設定なら nil
    public var key: String?

    public init(typed: String, completion: String, key: String?) {
        self.typed = typed
        self.completion = completion
        self.key = key
    }

    /// 予測した語句の全体
    public var text: String { typed + completion }
}

/// 選んでいる候補に連想があるときの知らせ(R-18)．描く側はキーを文字ではなくキーキャップのアイコンで描く
public struct AssociationHint: Sendable, Equatable {
    /// 連想変換のキーの名前．キーが割り当てられていなければ nil(知らせの語だけを出す)
    public var key: String?
    /// 知らせの語(「連想」)
    public var label: String

    public init(key: String?, label: String) {
        self.key = key
        self.label = label
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
/// (「修正」と打ったままの字と戻すキーを，色・取り消し線・キーキャップで描き分ける)
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
    /// 打ち間違いを直した候補の添え書き．描く側で補正の色のタグにする
    public static let correctedAnnotation = "修正"
    /// コマンドの候補の添え書き．描く側でアクセントの色のタグにする
    public static let commandAnnotation = "コマンド"
}
