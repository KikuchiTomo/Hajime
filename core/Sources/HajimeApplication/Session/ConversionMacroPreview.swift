import Foundation
import HajimeDomain

/// 設定の画面で変換マクロを試す(R-22)．見本の語に，入力のときと同じ値(日時・乱数)で変換マクロを当てる．
/// macOS の設定の画面と，Windows の設定の画面に頼まれたエンジン(previewMacros)が使う
@MainActor
public struct ConversionMacroPreview {
    private let settings: any SettingsReading
    private let values: TemplateValueSource

    public init(settings: any SettingsReading, calendar: (any CalendarReading)?) {
        self.settings = settings
        self.values = TemplateValueSource(calendar: calendar)
    }

    /// pattern があれば(書いている途中の形)その形だけを当てた結果を 1 つ，無ければ「整形」に並ぶ結果をすべて返す．
    /// text が空なら見本の語(DefaultSettings.macroSampleText)を使い，reading が空なら語をひらがなにしたものを読みにする
    public func preview(text: String, reading: String, pattern: String? = nil) -> [String] {
        var word = text.trimmingCharacters(in: .whitespaces)
        var wordReading = KanaWidth.hiragana(from: reading.trimmingCharacters(in: .whitespaces))
        if word.isEmpty {
            word = DefaultSettings.macroSampleText
            if wordReading.isEmpty { wordReading = DefaultSettings.macroSampleReading }
        } else if wordReading.isEmpty {
            wordReading = KanaWidth.hiragana(from: word)
        }
        if let pattern, !pattern.trimmingCharacters(in: .whitespaces).isEmpty {
            guard pattern.count <= DefaultSettings.maximumMacroPatternLength else { return [] }
            return [ConversionMacro(pattern: pattern).apply(text: word, reading: wordReading, values: values.values())]
        }
        let current = settings.current
        return ConversionMacros.results(text: word, reading: wordReading, macros: current.macros, values: values.values(),
                                        skipsSameReading: current.macroSkipsSameReading)
    }
}
