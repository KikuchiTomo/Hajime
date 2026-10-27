import Foundation
import S90Domain

/// 戻した補正を，設定の補正の「直さない語句」に入れる．入れた語句は設定の画面で消せる
@MainActor
public final class SettingsCorrectionRejections: CorrectionRejectionRecording {
    private let settings: any SettingsStoring

    public init(settings: any SettingsStoring) {
        self.settings = settings
    }

    public func recordRejected(phrase: String) -> Bool {
        let phrase = phrase.trimmingCharacters(in: .whitespaces)
        guard !phrase.isEmpty, phrase.count <= DefaultSettings.maximumExceptionLength,
            !settings.current.correction.exceptions.contains(phrase),
            settings.current.correction.exceptions.count < DefaultSettings.maximumCorrectionRules else { return false }
        do {
            try settings.update { $0.correction.exceptions.append(phrase) }
            return true
        } catch {
            // 書けなくても入力は続ける(この入力では戻したまま)
            return false
        }
    }
}
