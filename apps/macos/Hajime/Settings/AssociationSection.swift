import HajimeDomain
import SwiftUI

/// 変換のページの連想変換(R-18)の項目．連想変換のオン・オフ，候補数，案内と，取り込んだ連想の辞書の一覧
struct AssociationSection: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Section {
            ResettableToggle(model: model, title: UIStrings.Association.enabled, keyPath: \.association)
            Group {
                ResettableStepper(model: model, title: UIStrings.Association.limit, keyPath: \.associationLimit, range: DefaultSettings.associationLimitRange, step: DefaultSettings.associationLimitStep,
                                  value: "\(model.settings.associationLimit)")
                ResettableToggle(model: model, title: UIStrings.Association.hint, keyPath: \.showsAssociationHint)
            }
            .disabled(!model.settings.association)
        } header: {
            Text(UIStrings.Association.section)
        }
        Section {
            if model.settings.associationDictionaries.isEmpty {
                Text(UIStrings.Association.empty).foregroundStyle(.secondary)
            }
            ForEach(Array(model.settings.associationDictionaries.enumerated()), id: \.element.id) { index, dictionary in
                AssociationDictionaryRow(model: model, dictionary: dictionary, isFirst: index == 0,
                                         isLast: index == model.settings.associationDictionaries.count - 1)
            }
        } header: {
            Text(UIStrings.Association.dictionaries)
        } footer: {
            VStack(alignment: .leading, spacing: DesignTokens.Size.Space.group) {
                HStack {
                    Button(UIStrings.Association.importFile) { model.importAssociationFile() }
                        .disabled(model.isImportingDictionary || model.associations == nil)
                    if model.isImportingDictionary { ProgressView().controlSize(.small) }
                    Spacer()
                }
                // 読み込めるファイルの書き方は，ファイルの中身の見本で見せる
                FileExample(lines: [UIStrings.Association.fileExample, UIStrings.Association.tabFileExample])
                Text(UIStrings.Association.note).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct AssociationDictionaryRow: View {
    @ObservedObject var model: SettingsModel
    let dictionary: AssociationDictionary
    let isFirst: Bool
    let isLast: Bool
    @State private var expanded = false

    var body: some View {
        DictionaryRowHeader(isExpanded: $expanded,
                            isEnabled: Binding(get: { dictionary.isEnabled },
                                               set: { value in model.updateAssociationDictionary(dictionary.id) { $0.isEnabled = value } }),
                            name: dictionary.name, summary: UIStrings.Association.summary(dictionary), isFirst: isFirst, isLast: isLast) {
            model.moveAssociationDictionary(dictionary, by: $0)
        }
        if expanded {
            TextField(UIStrings.Dictionaries.name, text: Binding(get: { dictionary.name },
                                                                 set: { value in model.updateAssociationDictionary(dictionary.id) { $0.name = value } }))
            HStack {
                Button(UIStrings.Dictionaries.reimport) { model.importAssociationFile(replacing: dictionary) }
                    .disabled(model.isImportingDictionary)
                Spacer()
                Button(UIStrings.Settings.remove, role: .destructive) { model.removeAssociationDictionary(dictionary) }
            }
        }
    }
}

/// 読み込めるファイルの中身の見本．ファイルの行のまま等幅の字で並べる
private struct FileExample: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Size.Space.fine) {
            ForEach(lines, id: \.self) { Text($0) }
        }
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .padding(.horizontal, DesignTokens.Size.Settings.previewChipPaddingX)
        .padding(.vertical, DesignTokens.Size.Settings.previewChipPaddingY)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: DesignTokens.Size.Settings.previewChipRadius))
    }
}
