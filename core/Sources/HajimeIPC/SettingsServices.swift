import HajimeApplication
import HajimeDomain

/// 設定の画面がエンジンに頼む，設定のファイルの外にあるもの(学習・使い方の記録・パレットで使った文字の記録・英語と日本語と変換マクロの「試す」)．
/// どれも具象はエンジンのプロセスの composition root(hajime-engine-host)で渡す．渡さなければ何もしない
@MainActor
public struct SettingsServices {
    /// 学習した結果を消す
    public var resetLearning: () -> Void
    /// 使い方の記録
    public var usage: (any UsageReading)?
    /// パレットで使った文字の記録を消す(R-26．ピン留めと肌の色は残す)
    public var resetPaletteHistory: () -> Void
    /// 打った文を語ごとに英語か日本語か見分けた結果(設定の画面の「試す」．macOS と同じ WordLanguagePreview)
    public var previewLanguage: (_ text: String, _ precedingText: String?) -> [WordLanguagePreview.Word]
    /// 見本の語に変換マクロを当てた結果(設定の画面の「試す」．macOS と同じ ConversionMacroPreview)．pattern は書いている途中の形
    public var previewMacros: (_ text: String, _ reading: String, _ pattern: String?) -> [String]

    public init(resetLearning: @escaping () -> Void = {}, usage: (any UsageReading)? = nil, resetPaletteHistory: @escaping () -> Void = {},
                previewLanguage: @escaping (_ text: String, _ precedingText: String?) -> [WordLanguagePreview.Word] = { _, _ in [] },
                previewMacros: @escaping (_ text: String, _ reading: String, _ pattern: String?) -> [String] = { _, _, _ in [] }) {
        self.resetLearning = resetLearning
        self.usage = usage
        self.resetPaletteHistory = resetPaletteHistory
        self.previewLanguage = previewLanguage
        self.previewMacros = previewMacros
    }
}
