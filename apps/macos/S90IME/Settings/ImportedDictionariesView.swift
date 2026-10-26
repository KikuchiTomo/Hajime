import S90Domain
import SwiftUI

/// 取り込んだ辞書の一覧(R-14)．上ほど優先する．辞書ごとにオン・オフ，名前，分野，効かせる条件を決める
struct ImportedDictionariesView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                if model.settings.importedDictionaries.isEmpty {
                    Text(UIStrings.Dictionaries.empty).foregroundStyle(.secondary)
                }
                ForEach(Array(model.settings.importedDictionaries.enumerated()), id: \.element.id) { index, dictionary in
                    DictionaryRow(model: model, dictionary: dictionary, isFirst: index == 0,
                                  isLast: index == model.settings.importedDictionaries.count - 1)
                }
            } footer: {
                HStack {
                    Button(UIStrings.Dictionaries.importFile) { model.importDictionaryFile() }
                        .disabled(model.isImportingDictionary || model.dictionaries == nil)
                    if model.isImportingDictionary { ProgressView().controlSize(.small) }
                    Spacer()
                }
            }
            Section {
                Text(UIStrings.Dictionaries.note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DictionaryRow: View {
    @ObservedObject var model: SettingsModel
    let dictionary: ImportedDictionary
    let isFirst: Bool
    let isLast: Bool
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            TextField(UIStrings.Dictionaries.name, text: binding(\.name))
            TextField(UIStrings.Dictionaries.field, text: binding(\.field), prompt: Text(UIStrings.Dictionaries.fieldPrompt))
            Picker(UIStrings.Dictionaries.condition, selection: conditionKind) {
                ForEach(ConditionKind.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            if case .apps(let apps) = dictionary.condition {
                ForEach(apps, id: \.self) { app in
                    HStack {
                        Text(app).monospaced()
                        Spacer()
                        Button(UIStrings.Settings.remove) {
                            model.updateDictionary(dictionary.id) { $0.condition = .apps(apps.filter { $0 != app }) }
                        }
                    }
                }
                Button(UIStrings.Dictionaries.addApp) {
                    guard let id = model.chooseApplicationID(), !apps.contains(id) else { return }
                    model.updateDictionary(dictionary.id) { $0.condition = .apps(apps + [id]) }
                }
            }
            HStack {
                Button(UIStrings.Dictionaries.reimport) { model.importDictionaryFile(replacing: dictionary) }
                    .disabled(model.isImportingDictionary)
                Spacer()
                Button(UIStrings.Settings.remove, role: .destructive) { model.removeDictionary(dictionary) }
            }
        } label: {
            HStack {
                Toggle(isOn: binding(\.isEnabled)) {
                    VStack(alignment: .leading) {
                        Text(dictionary.name)
                        Text(UIStrings.Dictionaries.summary(dictionary)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                Spacer()
                Button { model.moveDictionary(dictionary, by: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless).disabled(isFirst).help(UIStrings.Dictionaries.moveUp)
                Button { model.moveDictionary(dictionary, by: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless).disabled(isLast).help(UIStrings.Dictionaries.moveDown)
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<ImportedDictionary, Value>) -> Binding<Value> {
        Binding(get: { dictionary[keyPath: keyPath] }, set: { value in model.updateDictionary(dictionary.id) { $0[keyPath: keyPath] = value } })
    }

    private enum ConditionKind: CaseIterable {
        case always, apps, context

        var label: String {
            switch self {
            case .always: UIStrings.Dictionaries.always
            case .apps: UIStrings.Dictionaries.apps
            case .context: UIStrings.Dictionaries.context
            }
        }
    }

    private var conditionKind: Binding<ConditionKind> {
        Binding(get: {
            switch dictionary.condition {
            case .always: .always
            case .apps: .apps
            case .context: .context
            }
        }, set: { kind in
            model.updateDictionary(dictionary.id) { item in
                switch kind {
                case .always: item.condition = .always
                case .apps: if case .apps = item.condition {} else { item.condition = .apps([]) }
                case .context: item.condition = .context
                }
            }
        })
    }
}
