import S90Domain

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
        public let label: String

        init(_ first: KeymapCommand, _ second: KeymapCommand, _ label: String) {
            self.first = first
            self.second = second
            self.label = label
        }

        init(_ command: KeymapCommand, _ label: String) {
            first = command
            second = nil
            self.label = label
        }
    }

    /// 分岐図の足元の案内
    public static let branchHints: [Hint] = [
        Hint(.nextCandidate, "候補"),
        Hint(.previousCandidate, "文字種"),
        Hint(.previousSegment, .nextSegment, "文節"),
        Hint(.nextUncertainSegment, "誤りやすい文節"),
        Hint(.shrinkSegment, .extendSegment, "区切り調整"),
        Hint(.shrinkSegmentToWord, .extendSegmentToWord, "単語ごと"),
        Hint(.splitSegment, "区切り"),
    ]

    /// 連想の一覧の足元の案内
    public static let associationHints: [Hint] = [
        Hint(.nextCandidate, "選択"),
        Hint(.previousSegment, .nextSegment, "意味"),
        Hint(.cancel, "戻る"),
    ]

    /// 文節を区切っているときの案内(数字で区切る位置を選び，Esc でやめる)．count は区切れる位置の数
    public static func splitHints(count: Int) -> [(key: String, label: String)] {
        [(count > 1 ? "1–\(count)" : "1", "区切り"), ("Esc", "取り消し")]
    }
}
