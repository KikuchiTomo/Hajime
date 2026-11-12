import HajimeDomain

/// モード表示と足元の案内の文言．macOS の候補ウィンドウと Windows のエンジン(FooterHints)が同じ表を使う
public enum IndicatorLabels {
    /// 日本語入力と英数のモード表示
    public static func label(for mode: InputMode) -> String {
        switch mode {
        case .japanese: "あ"
        case .direct: "A"
        }
    }

    /// 入力方式を切り替えたときのタグ
    public static func label(for style: InputStyle) -> String {
        switch style {
        case .romaji: "ローマ字"
        case .kana: "かな"
        case .english: "英"
        case .englishAuto: "英自動"
        }
    }

    /// 足元の案内の 1 つ．キーは変換中にそのコマンドに割り当てた最初のキー(second があれば 2 つを「←→」のようにまとめる)
    public struct Hint: Sendable, Equatable {
        public let first: KeymapCommand
        public let second: KeymapCommand?
        /// first にキーが無いときに代わりに案内するコマンド
        public let fallback: KeymapCommand?
        public let label: String

        init(_ first: KeymapCommand, _ second: KeymapCommand, _ label: String) {
            self.first = first
            self.second = second
            self.fallback = nil
            self.label = label
        }

        init(_ command: KeymapCommand, _ label: String, fallback: KeymapCommand? = nil) {
            first = command
            second = nil
            self.fallback = fallback
            self.label = label
        }

        /// 変換中に first(キーが無ければ fallback)と second に割り当てた最初のキー
        public func strokes(in keymap: Keymap) -> (first: KeyStroke?, second: KeyStroke?) {
            func stroke(_ command: KeymapCommand?) -> KeyStroke? { command.flatMap { keymap.strokes(for: $0, in: .converting).first } }
            return (stroke(first) ?? stroke(fallback), stroke(second))
        }
    }

    /// 1 つの案内に複数のキーを並べるときの区切り(「↓ Tab」)．描く側でキーごとのキーキャップに分ける
    public static let keySeparator = " "

    /// 分岐図の足元の案内
    public static let branchHints: [Hint] = [
        Hint(.nextCandidate, "候補"),
        Hint(.previousCandidate, "文字種"),
        Hint(.previousSegment, .nextSegment, "文節"),
        Hint(.nextUncertainSegment, "要確認の文節"),
        Hint(.shrinkSegment, .extendSegment, "区切り調整"),
        Hint(.shrinkSegmentToWord, .extendSegmentToWord, "単語単位"),
        Hint(.splitSegment, "分割"),
        Hint(.editSegment, "再入力"),
        Hint(.expandCandidates, "表形式"),
    ]

    /// 連想の一覧の足元の案内
    public static let associationHints: [Hint] = [
        Hint(.nextCandidate, "選択"),
        Hint(.previousSegment, .nextSegment, "意味の切り替え"),
        // 変換中の Esc を直前の変更の取り消しにした表では，そのキーで戻る
        Hint(.cancel, "戻る", fallback: .undoConversionEdit),
    ]

    /// 一覧で候補を選んでいるときの足元の案内．先頭から前の候補へ進むと文字種の行に移る(R-03)
    public static let candidateHints: [Hint] = [
        Hint(.previousCandidate, "文字種"),
        Hint(.expandCandidates, "表形式"),
    ]

    /// 候補を表に広げているときの足元の案内．文節を移るキーで列を移り，広げるキー(か取り消しのキー)で元に戻す
    public static let gridHints: [Hint] = [
        Hint(.previousSegment, .nextSegment, "列"),
        Hint(.expandCandidates, "戻る", fallback: .cancel),
    ]

    /// 一覧で文字種の行を選んでいるときの足元の案内．左右で字種を選び，次の候補で候補に戻る
    public static let variantHints: [Hint] = [
        Hint(.previousSegment, .nextSegment, "選択"),
        Hint(.nextCandidate, "候補"),
    ]

    /// 一覧の足元の案内．連想の一覧は連想の案内，文字種の行にいれば字種を選ぶ案内，表に広げていれば列を移る案内と戻す案内，
    /// 候補にいれば文字種の行へ移る案内と表に広げる案内．
    /// 文字種の行が無い一覧(文字種の行を出さない設定，入力中の候補の窓)では，文字種の案内を出さない
    public static func listHints(for panel: CandidatePanel) -> [Hint] {
        if panel.association != nil { return associationHints }
        if panel.focus == .variants { return variantHints }
        if panel.columnLength != nil { return gridHints }
        return panel.variants.isEmpty ? [] : candidateHints
    }

    /// 文節を区切っているときの案内(数字で区切る位置を選び，Esc でやめる)．count は区切れる位置の数
    public static func splitHints(count: Int) -> [(key: String, label: String)] {
        [(count > 1 ? "1–\(count)" : "1", "分割"), ("Esc", "キャンセル")]
    }
}
