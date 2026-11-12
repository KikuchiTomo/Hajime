import HajimeDomain
import SwiftUI

/// 打ち間違いの補正の決まり(R-02)．直すものの種類，直さない語，置き換えの決まり
struct CorrectionPage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            // 修正の対象は，変換のページの「タイプミスの修正」で選んだ範囲の中でだけ効く(オフなら何も直さず，英単語のみなら日本語は直さない)
            Section(UIStrings.Features.correctionKinds) {
                ResettableToggle(model: model, title: UIStrings.Features.correctsEnglish, keyPath: \.correction.english)
                    .disabled(model.settings.typoCorrection == .off)
                ResettableToggle(model: model, title: UIStrings.Features.correctsJapanese, keyPath: \.correction.japanese)
                    .disabled(model.settings.typoCorrection != .standard)
                ResettableToggle(model: model, title: UIStrings.Features.correctsRepeatedKeys, keyPath: \.correction.repeatedKeys)
                    .disabled(!correctsJapanese)
                if model.settings.typoCorrection != .standard {
                    Text(UIStrings.Features.correctionKindsNote).font(.caption).foregroundStyle(.secondary)
                }
                ResettableToggle(model: model, title: UIStrings.Features.misreadings, keyPath: \.misreadings)
                ResettableToggle(model: model, title: UIStrings.Extras.looseReadings, keyPath: \.looseReadings, help: UIStrings.Extras.looseReadingsNote)
                ResettableToggle(model: model, title: UIStrings.Extras.phoneticSpelling, keyPath: \.phoneticSpelling,
                                 help: UIStrings.Extras.phoneticSpellingNote)
            }
            Section {
                ResettableToggle(model: model, title: UIStrings.Extras.handShift, keyPath: \.handShiftCorrection)
                    .disabled(!correctsJapanese)
            } footer: {
                Text(UIStrings.Extras.handShiftNote).font(.caption).foregroundStyle(.secondary)
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

    /// 日本語のタイプミスを直すか(同じキーの重なりと手のずれは，その中の種類)
    private var correctsJapanese: Bool {
        model.settings.typoCorrection == .standard && model.settings.correction.japanese
    }
}
