import S90Domain
import SwiftUI

/// 辞書のページ．登録した単語と，取り込んだ辞書(R-16)を切り替えて出す
struct DictionaryPage: View {
    @ObservedObject var model: SettingsModel
    @State private var showsImported = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $showsImported) {
                Text(UIStrings.Dictionaries.userWords).tag(false)
                Text(UIStrings.Dictionaries.imported).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 8)
            if showsImported {
                ImportedDictionariesView(model: model)
            } else {
                UserWordsView(model: model)
            }
        }
    }
}

/// 登録した単語．同じ読みに別の単語を登録できるので，読みと単語の両方が同じものだけを重なりとみなす
private struct UserWordsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                RuleListEditor(
                    labels: .init(key: UIStrings.Settings.reading, value: UIStrings.Settings.word,
                                  empty: UIStrings.Settings.dictionaryEmpty),
                    items: model.settings.userDictionary.map { RuleItem(id: "\($0.reading)\t\($0.word)", key: $0.reading, value: $0.word) },
                    problem: { reading, word in
                        UserDictionaryEntry(reading: reading, word: word).isValid ? nil : UIStrings.Settings.invalidEntry
                    },
                    save: { reading, word, editing in
                        model.saveEntry(replacing: editing.map { UserDictionaryEntry(reading: $0.key, word: $0.value) }, reading: reading, word: word)
                    },
                    remove: { items in
                        model.removeEntries(Set(items.map { UserDictionaryEntry(reading: $0.key, word: $0.value) }))
                    },
                    importFile: model.importDictionary,
                    exportFile: model.exportDictionary,
                    keysAreUnique: false,
                    tableHeight: DesignTokens.Size.Settings.userDictionaryTableHeight
                )
            } footer: {
                Text(UIStrings.Settings.dictionaryNote).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
