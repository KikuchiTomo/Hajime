import S90Application
import S90Domain

/// 設定の画面がエンジンに頼む，設定のファイルの外にあるもの(学習・使い方の記録・英語と日本語の「試す」)．
/// どれも具象はエンジンのプロセスの composition root(s90-engine-host)で渡す．渡さなければ何もしない
@MainActor
public struct SettingsServices {
    /// 学習した結果を消す
    public var resetLearning: () -> Void
    /// 使い方の記録
    public var usage: (any UsageReading)?
    /// 打った文を語ごとに英語か日本語か見分けた結果(設定の画面の「試す」．macOS と同じ WordLanguagePreview)
    public var previewLanguage: (_ text: String, _ precedingText: String?) -> [WordLanguagePreview.Word]

    public init(resetLearning: @escaping () -> Void = {}, usage: (any UsageReading)? = nil,
                previewLanguage: @escaping (_ text: String, _ precedingText: String?) -> [WordLanguagePreview.Word] = { _, _ in [] }) {
        self.resetLearning = resetLearning
        self.usage = usage
        self.previewLanguage = previewLanguage
    }
}
