import S90Domain
import SwiftUI

/// 打ち間違いの補正の決まり(R-02)．直すものの種類，直さない語，置き換えの決まり
struct CorrectionPage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section(UIStrings.Features.correctionKinds) {
                ResettableToggle(model: model, title: UIStrings.Features.correctsEnglish, keyPath: \.correction.english)
                ResettableToggle(model: model, title: UIStrings.Features.correctsJapanese, keyPath: \.correction.japanese)
                ResettableToggle(model: model, title: UIStrings.Features.correctsRepeatedKeys, keyPath: \.correction.repeatedKeys)
                    .disabled(!model.settings.correction.japanese)
                ResettableToggle(model: model, title: UIStrings.Features.misreadings, keyPath: \.misreadings)
            }
            Section(UIStrings.Features.rules) {
                RuleListEditor(model: model, spec: .correctionRules, labels: .init(
                    key: UIStrings.Features.typed, value: UIStrings.Features.replacement,
                    empty: UIStrings.Features.rulesEmpty))
            }
            Section(UIStrings.Features.exceptions) {
                RuleListEditor(model: model, spec: .exceptions, labels: .init(
                    key: UIStrings.Features.exceptionPlaceholder, value: nil,
                    empty: UIStrings.Features.exceptionsEmpty))
            }
        }
        .formStyle(.grouped)
    }
}
