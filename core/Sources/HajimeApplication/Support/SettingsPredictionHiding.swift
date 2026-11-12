import Foundation
import HajimeDomain

/// 入力中の予測に出した語句を，設定の「予測に表示しない語句」に入れる．入れた語句は設定の画面で消せる
@MainActor
public final class SettingsPredictionHiding: PredictionHiding {
    private let settings: any SettingsStoring

    public init(settings: any SettingsStoring) {
        self.settings = settings
    }

    public func hide(_ text: String) -> Bool {
        guard RuleListEditing.isValidHiddenPrediction(text), !settings.current.hiddenPredictions.contains(text),
            settings.current.hiddenPredictions.count < DefaultSettings.maximumHiddenPredictions else { return false }
        do {
            try settings.update { $0.hiddenPredictions.append(text) }
            return true
        } catch {
            // 書けなくても入力は続ける(この予測は出したまま)
            return false
        }
    }
}
