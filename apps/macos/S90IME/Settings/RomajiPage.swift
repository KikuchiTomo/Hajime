import S90Domain
import SwiftUI

/// 利用者が足すローマ字の綴り．標準の表に重ね，同じ綴りは利用者のものを使う
struct RomajiPage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                RuleListEditor(model: model, spec: .romaji, labels: .init(
                    key: UIStrings.Settings.romajiKeys, value: UIStrings.Settings.romajiKana,
                    empty: UIStrings.Settings.romajiEmpty, emptyHint: UIStrings.Settings.romajiEmptyHint))
            } footer: {
                Text(UIStrings.Settings.romajiNote).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
