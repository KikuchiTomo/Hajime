/// キー設定の表のひな形．読み込むと表をひな形の行で置き換える．
///
/// 行は「状態<タブ>キー<タブ>コマンド」の形で書く(Keymap.rows(from:))．
/// Windows 風と Mac 風は，Mozc のキー設定の表(BSD 3-Clause．THIRD_PARTY_NOTICES.md)の行をはじめの状態とコマンドに置き換えて作った．
/// はじめに無いコマンドの行(読みの中のカーソル移動・予測・再変換・確定の取り消しなど)は除き，
/// 切り替えのキーと設定を開くなどのキー(common)と，連想変換の Option+↑ を足してある(Ctrl+Tab はアプリのタブの切り替えとぶつかる)
public enum KeymapPreset: String, Sendable, Equatable, CaseIterable {
    /// はじめの既定
    case standard
    case windows
    case mac
    case emacs
    case vim

    public var keymap: Keymap {
        Keymap(Keymap.rows(from: source))
    }

    /// ひな形の行(「状態<タブ>キー<タブ>コマンド」の形)
    public var source: String {
        switch self {
        case .standard: Self.common + "\n" + Self.standardRows
        case .windows: Self.common + "\n" + Self.windowsRows
        case .mac: Self.common + "\n" + Self.macRows
        case .emacs: Self.common + "\n" + Self.standardRows + "\n" + Self.emacsRows
        case .vim: Self.common + "\n" + Self.standardRows + "\n" + Self.vimRows
        }
    }

    /// 今の表がどのひな形と同じか．利用者が変えていれば nil
    public static func matching(_ keymap: Keymap) -> KeymapPreset? {
        allCases.first { $0.keymap.entries == keymap.entries }
    }

    /// どのひな形にも入れる行．日本語と英数の切り替えと，入力の状態によらない IME の機能
    static let common = """
        anywhere\tCtrl Option ,\topenSettings
        anywhere\tCtrl Option l\ttoggleLiveConversion
        anywhere\tCtrl Option h\thandwriting
        anywhere\tEisu\tdirectMode
        anywhere\tKana\tjapaneseMode
        anywhere\tHankaku/Zenkaku\ttoggleMode
        anywhere\tOption Kana\tnextInputStyle
        idle\tCtrl Shift r\treconvert
        idle\tHenkan\treconvert
        """

    /// 既定．↓ と Space で次の候補，Shift+←→ で文節の長さ，Tab と → で次の文節へ，Option+→ で誤りやすい文節へ．
    /// 入力中の Shift+Space と，変換中の Shift+↑ で連想変換(R-18)
    static let standardRows = """
        anywhere\tEnter\tcommit
        anywhere\tEscape\tcancel
        anywhere\tF6\ttoHiragana
        anywhere\tF7\ttoKatakana
        anywhere\tF8\ttoHalfwidthKatakana
        anywhere\tF9\ttoFullwidthAlphanumeric
        anywhere\tF10\ttoHalfwidthAlphanumeric
        anywhere\tCtrl j\ttoHiragana
        anywhere\tCtrl k\ttoKatakana
        anywhere\tCtrl ;\ttoHalfwidthKatakana
        anywhere\tCtrl l\ttoFullwidthAlphanumeric
        anywhere\tCtrl :\ttoHalfwidthAlphanumeric
        anywhere\tCtrl '\ttoHalfwidthAlphanumeric
        anywhere\tMuhenkan\ttoKatakana
        anywhere\tDown\tnextCandidate
        anywhere\tUp\tpreviousCandidate
        idle\tSpace\tinsertSpace
        idle\tShift Space\tinsertAlternateSpace
        composing\tSpace\tconvert
        composing\tShift Space\tassociate
        composing\tHenkan\tconvert
        composing\tBackspace\tdeleteBackward
        composing\tTab\tacceptSuggestion
        composing\tOption Space\tinsertBoundary
        converting\tSpace\tnextCandidate
        converting\tHenkan\tnextCandidate
        converting\tShift Space\tpreviousCandidate
        converting\tRight\tnextSegment
        converting\tLeft\tpreviousSegment
        converting\tTab\tnextSegment
        converting\tShift Tab\tpreviousSegment
        converting\tOption Right\tnextUncertainSegment
        converting\tOption Left\tpreviousUncertainSegment
        converting\tShift Up\tassociate
        converting\tShift Right\textendSegment
        converting\tShift Left\tshrinkSegment
        converting\tCtrl Shift Right\textendSegmentToWord
        converting\tCtrl Shift Left\tshrinkSegmentToWord
        converting\tShift Down\tsplitSegment
        converting\tShift Backspace\teditSegment
        converting\tBackspace\tbackToReading
        converting\tCtrl Backspace\tforgetCandidate
        """

    /// Emacs 風．標準に加えて Control+N・P で候補，Control+F・B で文節，Control+G で取り消す
    static let emacsRows = """
        anywhere\tCtrl g\tcancel
        anywhere\tCtrl m\tcommit
        composing\tCtrl h\tdeleteBackward
        composing\tCtrl n\tconvert
        converting\tCtrl n\tnextCandidate
        converting\tCtrl p\tpreviousCandidate
        converting\tCtrl f\tnextSegment
        converting\tCtrl b\tpreviousSegment
        converting\tCtrl a\tfirstSegment
        converting\tCtrl e\tlastSegment
        converting\tCtrl h\tbackToReading
        """

    /// Vim 風．標準に加えて，変換中に h・l で文節，j・k で候補，⇧H・⇧L で文節の長さ，⌃[ で取り消す．
    /// 文字のキーは変換中だけに置き，入力中と入力文字なしでは打った文字のままにする．
    /// 入力文字なしの Esc は表に置かないので，「Esc で英数に切り替え」の設定(escapeSwitchesToDirect)がそのまま効く
    static let vimRows = """
        anywhere\tCtrl [\tcancel
        converting\th\tpreviousSegment
        converting\tl\tnextSegment
        converting\tj\tnextCandidate
        converting\tk\tpreviousCandidate
        converting\tShift h\tshrinkSegment
        converting\tShift l\textendSegment
        converting\tShift j\tnextCandidatePage
        converting\tShift k\tpreviousCandidatePage
        converting\tw\tnextUncertainSegment
        converting\tb\tpreviousUncertainSegment
        converting\t0\tfirstSegment
        converting\t$\tlastSegment
        """

    /// Windows 風
    static let windowsRows = """
        idle\tCtrl Shift Space\tinsertFullwidthSpace
        idle\tShift Space\tinsertAlternateSpace
        idle\tSpace\tinsertSpace
        composing\tBackspace\tdeleteBackward
        composing\tCtrl Backspace\tdeleteBackward
        composing\tCtrl Enter\tcommit
        composing\tCtrl h\tdeleteBackward
        composing\tCtrl i\ttoKatakana
        composing\tCtrl m\tcommit
        composing\tCtrl o\ttoHalfwidthKatakana
        composing\tCtrl p\ttoFullwidthAlphanumeric
        composing\tCtrl Shift Space\tinsertFullwidthSpace
        composing\tCtrl Space\tinsertHalfwidthSpace
        composing\tCtrl t\ttoHalfwidthAlphanumeric
        composing\tCtrl u\ttoHiragana
        composing\tCtrl z\tcancel
        composing\tEnter\tcommit
        composing\tEscape\tcancel
        composing\tF10\ttoHalfwidthAlphanumeric
        composing\tF2\tconvertWithoutLearning
        composing\tF6\ttoHiragana
        composing\tF7\ttoKatakana
        composing\tF8\ttoHalfwidthKatakana
        composing\tF9\ttoFullwidthAlphanumeric
        composing\tHenkan\tconvert
        composing\tMuhenkan\tswitchKanaType
        composing\tShift Backspace\tdeleteBackward
        composing\tShift Escape\tcancel
        composing\tShift Muhenkan\ttoFullwidthAlphanumeric
        composing\tShift Space\tconvert
        composing\tSpace\tconvert
        converting\tBackspace\tbackToReading
        converting\tCtrl a\tfirstSegment
        converting\tCtrl Backspace\tbackToReading
        converting\tCtrl d\tnextSegment
        converting\tCtrl Down\tcommitFirstSegment
        converting\tCtrl e\tpreviousCandidate
        converting\tCtrl Enter\tcommit
        converting\tCtrl f\tlastSegment
        converting\tCtrl g\tcancel
        converting\tCtrl h\tcancel
        converting\tCtrl i\ttoKatakana
        converting\tCtrl k\tshrinkSegment
        converting\tCtrl l\textendSegment
        converting\tCtrl Left\tfirstSegment
        converting\tCtrl m\tcommit
        converting\tCtrl n\tcommitFirstSegment
        converting\tCtrl o\ttoHalfwidthKatakana
        converting\tCtrl p\ttoFullwidthAlphanumeric
        converting\tCtrl Right\tlastSegment
        converting\tCtrl s\tpreviousSegment
        converting\tCtrl Shift Space\tinsertFullwidthSpace
        converting\tCtrl Space\tinsertHalfwidthSpace
        converting\tCtrl t\ttoHalfwidthAlphanumeric
        converting\tCtrl u\ttoHiragana
        converting\tCtrl Up\tpreviousCandidate
        converting\tCtrl x\tnextCandidate
        converting\tCtrl z\tcancel
        converting\tDelete\tcancel
        converting\tDown\tnextCandidate
        converting\tEnd\tlastSegment
        converting\tEnter\tcommit
        converting\tEscape\tcancel
        converting\tF10\ttoHalfwidthAlphanumeric
        converting\tF6\ttoHiragana
        converting\tF7\ttoKatakana
        converting\tF8\ttoHalfwidthKatakana
        converting\tF9\ttoFullwidthAlphanumeric
        converting\tHenkan\tnextCandidate
        converting\tHome\tfirstSegment
        converting\tLeft\tpreviousSegment
        converting\tMuhenkan\tswitchKanaType
        converting\tPageDown\tnextCandidatePage
        converting\tPageUp\tpreviousCandidatePage
        converting\tRight\tnextSegment
        converting\tShift Backspace\tbackToReading
        converting\tShift Down\tnextCandidatePage
        converting\tShift Escape\tcancel
        converting\tShift Henkan\tpreviousCandidate
        converting\tShift Left\tshrinkSegment
        converting\tShift Muhenkan\ttoFullwidthAlphanumeric
        converting\tShift Right\textendSegment
        converting\tShift Space\tpreviousCandidate
        converting\tShift Tab\tpreviousCandidate
        converting\tShift Up\tassociate
        converting\tSpace\tnextCandidate
        converting\tUp\tpreviousCandidate
        converting\tCtrl Delete\tforgetCandidate
        composing\tOption Space\tinsertBoundary
        composing\tTab\tacceptSuggestion
        composing\tOption Up\tassociate
        converting\tOption Up\tassociate
        """

    /// Mac 風
    static let macRows = """
        idle\tShift Space\tinsertAlternateSpace
        idle\tSpace\tinsertSpace
        composing\tBackspace\tdeleteBackward
        composing\tCtrl ;\ttoHalfwidthKatakana
        composing\tCtrl :\ttoHalfwidthAlphanumeric
        composing\tCtrl '\ttoHalfwidthAlphanumeric
        composing\tCtrl g\tcancel
        composing\tCtrl h\tdeleteBackward
        composing\tCtrl j\ttoHiragana
        composing\tCtrl k\ttoKatakana
        composing\tCtrl l\ttoFullwidthAlphanumeric
        composing\tCtrl m\tcommit
        composing\tEnter\tcommit
        composing\tEscape\tcancel
        composing\tF10\ttoHalfwidthAlphanumeric
        composing\tF2\tconvertWithoutLearning
        composing\tF6\ttoHiragana
        composing\tF7\ttoKatakana
        composing\tF8\ttoHalfwidthKatakana
        composing\tF9\ttoFullwidthAlphanumeric
        composing\tOption a\ttoHalfwidthKatakana
        composing\tOption c\ttoFullwidthAlphanumeric
        composing\tOption F1\ttoHiragana
        composing\tOption F2\ttoKatakana
        composing\tOption F3\ttoFullwidthAlphanumeric
        composing\tOption F4\ttoHalfwidthKatakana
        composing\tOption F5\ttoHalfwidthAlphanumeric
        composing\tOption s\ttoHalfwidthAlphanumeric
        composing\tOption Space\tinsertFullwidthSpace
        composing\tOption x\ttoKatakana
        composing\tOption z\ttoHiragana
        composing\tSpace\tconvert
        converting\tBackspace\tbackToReading
        converting\tCtrl ;\ttoHalfwidthKatakana
        converting\tCtrl :\ttoHalfwidthAlphanumeric
        converting\tCtrl '\ttoHalfwidthAlphanumeric
        converting\tCtrl a\tfirstSegment
        converting\tCtrl b\tpreviousSegment
        converting\tCtrl d\tnextSegment
        converting\tCtrl e\tpreviousCandidate
        converting\tCtrl f\tnextSegment
        converting\tCtrl h\tcancel
        converting\tCtrl i\tshrinkSegment
        converting\tCtrl j\ttoHiragana
        converting\tCtrl k\ttoKatakana
        converting\tCtrl l\ttoFullwidthAlphanumeric
        converting\tCtrl Left\tfirstSegment
        converting\tCtrl m\tcommit
        converting\tCtrl n\tnextCandidate
        converting\tCtrl o\textendSegment
        converting\tCtrl p\tpreviousCandidate
        converting\tCtrl q\tshrinkSegment
        converting\tCtrl Right\tlastSegment
        converting\tCtrl s\tpreviousSegment
        converting\tCtrl w\textendSegment
        converting\tCtrl x\tnextCandidate
        converting\tDown\tnextCandidate
        converting\tEnd\tlastSegment
        converting\tEnter\tcommit
        converting\tEscape\tcancel
        converting\tF10\ttoHalfwidthAlphanumeric
        converting\tF6\ttoHiragana
        converting\tF7\ttoKatakana
        converting\tF8\ttoHalfwidthKatakana
        converting\tF9\ttoFullwidthAlphanumeric
        converting\tHome\tfirstSegment
        converting\tLeft\tpreviousSegment
        converting\tOption a\ttoHalfwidthKatakana
        converting\tOption c\ttoFullwidthAlphanumeric
        converting\tOption F1\ttoHiragana
        converting\tOption F2\ttoKatakana
        converting\tOption F3\ttoFullwidthAlphanumeric
        converting\tOption F4\ttoHalfwidthKatakana
        converting\tOption F5\ttoHalfwidthAlphanumeric
        converting\tOption i\tpreviousCandidate
        converting\tOption k\tnextCandidate
        converting\tOption s\ttoHalfwidthAlphanumeric
        converting\tOption x\ttoKatakana
        converting\tOption z\ttoHiragana
        converting\tPageDown\tnextCandidatePage
        converting\tPageUp\tpreviousCandidatePage
        converting\tRight\tnextSegment
        converting\tShift Down\tnextCandidatePage
        converting\tShift Left\tshrinkSegment
        converting\tShift Right\textendSegment
        converting\tShift Space\tpreviousCandidate
        converting\tShift Tab\tpreviousCandidate
        converting\tShift Up\tpreviousCandidatePage
        converting\tSpace\tnextCandidate
        converting\tUp\tpreviousCandidate
        converting\tCtrl Delete\tforgetCandidate
        composing\tTab\tacceptSuggestion
        composing\tOption Up\tassociate
        converting\tOption Up\tassociate
        """
}

extension Keymap {
    /// 「状態<タブ>キー<タブ>コマンド」の行を読む．読めない行と，状態で効かないコマンドの行は飛ばす
    public static func rows(from text: String) -> [KeymapEntry] {
        text.split(separator: "\n").compactMap { line in
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard columns.count == 3, let state = KeymapState(rawValue: columns[0]), let stroke = KeyStroke(notation: columns[1]),
                let command = KeymapCommand(rawValue: columns[2]), command.isAvailable(in: state) else { return nil }
            return KeymapEntry(state, stroke, command)
        }
    }
}
