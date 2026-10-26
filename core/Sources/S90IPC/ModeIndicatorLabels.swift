import S90Domain

/// Windows の候補ウィンドウに出すモードの札の文字(macOS の UIStrings.ModeIndicator と同じ)
public enum ModeIndicatorLabels {
    /// 入力方式を切り替えたときの札
    public static func label(for style: InputStyle) -> String {
        switch style {
        case .romaji: "ローマ字"
        case .kana: "かな"
        case .english: "英"
        case .englishAuto: "英自動"
        }
    }
}
