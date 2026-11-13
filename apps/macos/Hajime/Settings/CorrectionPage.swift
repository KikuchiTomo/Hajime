import HajimeDomain
import SwiftUI

/// 打ち間違いの補正の決まり(R-02)．直すものの種類，直さない語，置き換えの決まり
struct CorrectionPage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            // 修正の対象は，変換のページの「タイプミスの修正」で選んだ範囲の中でだけ効く(オフなら何も直さず，英単語のみなら日本語は直さない)
            Section(UIStrings.Features.correctionKinds) {
                // 種類を選べるかは「タイプミスの修正」(変換のページと同じ設定)で決まるので，ここでも切り替えられるようにする
                ResettablePicker(model: model, title: UIStrings.Choice.typoCorrection, keyPath: \.typoCorrection, label: UIStrings.Choice.label(for:))
                ResettableToggle(model: model, title: UIStrings.Features.correctsEnglish, keyPath: \.correction.english)
                    .disabled(model, when: \.typoCorrection, is: .off)
                ResettableToggle(model: model, title: UIStrings.Features.correctsJapanese, keyPath: \.correction.japanese)
                    .disabled(model, unless: \.typoCorrection, is: .standard)
                ResettableToggle(model: model, title: UIStrings.Features.correctsRepeatedKeys, keyPath: \.correction.repeatedKeys)
                    .disabled(model, unless: \.correctsJapaneseTypos)
                ResettableToggle(model: model, title: UIStrings.Features.misreadings, keyPath: \.misreadings)
                ExampleToggle(model: model, title: UIStrings.Extras.looseReadings, keyPath: \.looseReadings,
                              example: UIStrings.Extras.looseReadingsExample, titleWidth: exampleTitleWidth)
                ExampleToggle(model: model, title: UIStrings.Extras.phoneticSpelling, keyPath: \.phoneticSpelling,
                              example: UIStrings.Extras.phoneticSpellingExample, titleWidth: exampleTitleWidth)
            }
            Section {
                ExampleToggle(model: model, title: UIStrings.Extras.handShift, keyPath: \.handShiftCorrection,
                              example: UIStrings.Extras.handShiftExample, titleWidth: exampleTitleWidth)
                    .disabled(model, unless: \.correctsJapaneseTypos)
            }
            BuiltLater(stage: 1) {
                Section(UIStrings.Features.rules) {
                    RuleListEditor(model: model, spec: .correctionRules, labels: .init(
                        key: UIStrings.Features.typed, value: UIStrings.Features.replacement,
                        empty: UIStrings.Features.rulesEmpty))
                }
            }
            BuiltLater(stage: 2) {
                Section(UIStrings.Features.exceptions) {
                    RuleListEditor(model: model, spec: .exceptions, labels: .init(
                        key: UIStrings.Features.exceptionPlaceholder, value: nil,
                        empty: UIStrings.Features.exceptionsEmpty))
                }
            }
        }
        .formStyle(.grouped)
    }

    /// 見本のタグを添える行の名前のうちいちばん長いものの幅(タグの左の端をページの中でそろえる)
    private var exampleTitleWidth: CGFloat {
        ExampleToggle.titleWidth([UIStrings.Extras.looseReadings, UIStrings.Extras.phoneticSpelling, UIStrings.Extras.handShift])
    }
}

private extension HajimeDomain.Settings {
    /// 日本語のタイプミスを直すか(同じキーの重なりと手のずれは，その中の種類)
    var correctsJapaneseTypos: Bool {
        typoCorrection == .standard && correction.japanese
    }
}
