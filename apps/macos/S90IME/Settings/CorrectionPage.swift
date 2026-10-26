import S90Domain
import SwiftUI

/// 打ち間違いの補正の決まり(R-02)．直すものの種類，直さない語，置き換えの決まり
struct CorrectionPage: View {
    @ObservedObject var model: SettingsModel
    @State private var exception = ""
    @State private var typed = ""
    @State private var replacement = ""

    var body: some View {
        Form {
            Section(UIStrings.Features.correctionKinds) {
                ResettableToggle(model: model, title: UIStrings.Features.correctsEnglish, keyPath: \.correction.english)
                ResettableToggle(model: model, title: UIStrings.Features.correctsJapanese, keyPath: \.correction.japanese)
                ResettableToggle(model: model, title: UIStrings.Features.correctsRepeatedKeys, keyPath: \.correction.repeatedKeys)
                    .disabled(!model.settings.correction.japanese)
                ResettableToggle(model: model, title: UIStrings.Features.misreadings, keyPath: \.misreadings)
            }
            Section(UIStrings.Features.exceptions) {
                HStack {
                    TextField(UIStrings.Features.exceptionPlaceholder, text: $exception)
                        .onSubmit(addException)
                    Button(UIStrings.Settings.add, action: addException)
                        .disabled(exception.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(model.settings.correction.exceptions, id: \.self) { word in
                    HStack {
                        Text(word)
                        Spacer()
                        removeButton { $0.correction.exceptions.removeAll { $0 == word } }
                    }
                }
            }
            Section(UIStrings.Features.rules) {
                HStack {
                    TextField(UIStrings.Features.typed, text: $typed)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    TextField(UIStrings.Features.replacement, text: $replacement)
                        .onSubmit(addRule)
                    Button(UIStrings.Settings.add, action: addRule)
                        .disabled(typed.isEmpty || replacement.isEmpty)
                }
                ForEach(model.settings.correction.rules, id: \.self) { rule in
                    HStack {
                        Text(rule.typed).monospaced()
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Text(rule.word)
                        Spacer()
                        removeButton { $0.correction.rules.removeAll { $0 == rule } }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func removeButton(_ change: @escaping (inout S90Domain.Settings) -> Void) -> some View {
        Button {
            model.update(change)
        } label: {
            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(UIStrings.Settings.remove)
        .accessibilityLabel(UIStrings.Settings.remove)
    }

    private func addException() {
        let word = exception.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, word.count <= 64 else { return }
        if model.update({ current in
            if !current.correction.exceptions.contains(word) { current.correction.exceptions.append(word) }
        }) {
            exception = ""
        }
    }

    private func addRule() {
        let rule = CorrectionRule(typed: typed.trimmingCharacters(in: .whitespaces).lowercased(), word: replacement.trimmingCharacters(in: .whitespaces))
        guard rule.isValid else {
            model.message = UIStrings.Features.invalidRule
            return
        }
        if model.update({ current in
            current.correction.rules.removeAll { $0.typed == rule.typed }
            current.correction.rules.append(rule)
        }) {
            typed = ""
            replacement = ""
        }
    }
}
