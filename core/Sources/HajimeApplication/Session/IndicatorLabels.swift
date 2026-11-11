import HajimeDomain

/// モードの札と足元の案内の文言．macOS の候補ウィンドウと Windows のエンジン(BranchHints)が同じ表を使う
public enum IndicatorLabels {
    /// 日本語入力と英数のモードの札
    public static func label(for mode: InputMode) -> String {
        switch mode {
        case .japanese: "あ"
        case .direct: "A"
        }
    }

    /// 入力方式を切り替えたときの札
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
        Hint(.nextUncertainSegment, "誤りやすい文節"),
        Hint(.shrinkSegment, .extendSegment, "区切り調整"),
        Hint(.shrinkSegmentToWord, .extendSegmentToWord, "単語ごと"),
        Hint(.splitSegment, "区切り"),
        Hint(.editSegment, "打ち直し"),
    ]

    /// 連想の一覧の足元の案内
    public static let associationHints: [Hint] = [
        Hint(.nextCandidate, "選択"),
        Hint(.previousSegment, .nextSegment, "意味"),
        // 変換中の Esc を直前の変更の取り消しにした表では，そのキーで戻る
        Hint(.cancel, "戻る", fallback: .undoConversionEdit),
    ]

    /// 文節を区切っているときの案内(数字で区切る位置を選び，Esc でやめる)．count は区切れる位置の数
    public static func splitHints(count: Int) -> [(key: String, label: String)] {
        [(count > 1 ? "1–\(count)" : "1", "区切り"), ("Esc", "取り消し")]
    }
}
