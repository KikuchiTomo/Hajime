import S90Domain
import SwiftUI

/// 変換のページの連想変換(R-18)の項目．連想変換のオン・オフ，候補数，案内と，取り込んだ連想の辞書の一覧
struct AssociationSection: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Section {
            ResettableToggle(model: model, title: UIStrings.Association.enabled, keyPath: \.association)
            Group {
                ResettableRow(model: model, keyPath: \.associationLimit) {
                    Stepper(value: model.binding(\.associationLimit), in: DefaultSettings.associationLimitRange, step: 10) {
                        LabeledContent(UIStrings.Association.limit, value: "\(model.settings.associationLimit)")
                    }
                }
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
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button(UIStrings.Association.importFile) { model.importAssociationFile() }
                        .disabled(model.isImportingDictionary || model.associations == nil)
                    if model.isImportingDictionary { ProgressView().controlSize(.small) }
                    Spacer()
                }
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
        DisclosureGroup(isExpanded: $expanded) {
            TextField(UIStrings.Dictionaries.name, text: Binding(get: { dictionary.name },
                                                                 set: { value in model.updateAssociationDictionary(dictionary.id) { $0.name = value } }))
            HStack {
                Button(UIStrings.Dictionaries.reimport) { model.importAssociationFile(replacing: dictionary) }
                    .disabled(model.isImportingDictionary)
                Spacer()
                Button(UIStrings.Settings.remove, role: .destructive) { model.removeAssociationDictionary(dictionary) }
            }
        } label: {
            HStack {
                Toggle(isOn: Binding(get: { dictionary.isEnabled },
                                     set: { value in model.updateAssociationDictionary(dictionary.id) { $0.isEnabled = value } })) {
                    VStack(alignment: .leading) {
                        Text(dictionary.name)
                        Text(UIStrings.Association.summary(dictionary)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                Spacer()
                Button { model.moveAssociationDictionary(dictionary, by: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless).disabled(isFirst).help(UIStrings.Dictionaries.moveUp)
                Button { model.moveAssociationDictionary(dictionary, by: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless).disabled(isLast).help(UIStrings.Dictionaries.moveDown)
            }
        }
    }
}
