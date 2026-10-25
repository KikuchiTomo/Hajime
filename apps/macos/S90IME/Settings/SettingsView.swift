import S90Domain
import SwiftUI

/// 設定の画面．項目は Google 日本語入力・ATOK などの設定を調べて選んだ(docs/user/settings.md)
struct SettingsView: View {
    static let size = NSSize(width: 620, height: 520)
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            InputTab(model: model).tabItem { Text(UIStrings.Settings.inputTab) }
            ConversionTab(model: model).tabItem { Text(UIStrings.Settings.conversionTab) }
            DictionaryTab(model: model).tabItem { Text(UIStrings.Settings.dictionaryTab) }
            AppearanceTab(model: model).tabItem { Text(UIStrings.Settings.appearanceTab) }
        }
        .padding()
        .frame(width: Self.size.width, height: Self.size.height)
        .alert(model.message ?? "", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button(UIStrings.Settings.ok) { model.message = nil }
        }
    }
}

/// 列挙の値を選ぶ項目
private struct ChoicePicker<Value: Hashable & CaseIterable>: View where Value.AllCases: RandomAccessCollection {
    let title: String
    let selection: Binding<Value>
    let label: (Value) -> String

    var body: some View {
        Picker(title, selection: selection) {
            ForEach(Array(Value.allCases), id: \.self) { Text(label($0)).tag($0) }
        }
    }
}

private struct InputTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section(UIStrings.Settings.inputStyleSection) {
                ChoicePicker(title: UIStrings.Menu.inputStyle, selection: model.binding(\.inputStyle), label: UIStrings.Menu.label(for:))
            }
            Section(UIStrings.Settings.characters) {
                ChoicePicker(title: UIStrings.Settings.punctuation, selection: model.binding(\.punctuation), label: UIStrings.Settings.label(for:))
                ChoicePicker(title: UIStrings.Settings.brackets, selection: model.binding(\.brackets), label: UIStrings.Settings.label(for:))
                ChoicePicker(title: UIStrings.Settings.slash, selection: model.binding(\.slash), label: UIStrings.Settings.label(for:))
                ChoicePicker(title: UIStrings.Menu.yenKey, selection: model.binding(\.yenKey), label: UIStrings.Menu.label(for:))
                ChoicePicker(title: UIStrings.Settings.spaceWidth, selection: model.binding(\.spaceWidth), label: UIStrings.Settings.label(for:))
                ChoicePicker(title: UIStrings.Settings.numberWidth, selection: model.binding(\.numberWidth), label: UIStrings.Settings.label(for:))
            }
            Section(UIStrings.Settings.keys) {
                Toggle(UIStrings.Settings.punctuationCommits, isOn: model.binding(\.punctuationCommits))
                Toggle(UIStrings.Settings.numberKeySelection, isOn: model.binding(\.numberKeySelection))
                Toggle(UIStrings.Settings.showsModeIndicator, isOn: model.binding(\.showsModeIndicator))
            }
        }
        .formStyle(.grouped)
    }
}

private struct ConversionTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section(UIStrings.Settings.conversion) {
                Toggle(UIStrings.Menu.liveConversion, isOn: model.binding(\.liveConversion))
                ChoicePicker(title: UIStrings.Menu.presentation, selection: model.binding(\.candidatePresentation), label: UIStrings.Menu.label(for:))
                Toggle(UIStrings.Menu.variantRow, isOn: model.binding(\.showsVariantRow))
                ChoicePicker(title: UIStrings.Menu.typoCorrection, selection: model.binding(\.typoCorrection), label: UIStrings.Menu.label(for:))
            }
            Section(UIStrings.Settings.specialConversion) {
                Toggle(UIStrings.Settings.dateConversion, isOn: model.binding(\.dateConversion))
                Toggle(UIStrings.Settings.symbolConversion, isOn: model.binding(\.symbolConversion))
                Toggle(UIStrings.Settings.emojiConversion, isOn: model.binding(\.emojiConversion))
            }
            Section(UIStrings.Settings.learning) {
                ChoicePicker(title: UIStrings.Settings.learning, selection: model.binding(\.learning), label: UIStrings.Settings.label(for:))
                Button(UIStrings.Settings.resetLearning, role: .destructive) { model.resetLearning() }
            }
        }
        .formStyle(.grouped)
    }
}

private struct DictionaryTab: View {
    @ObservedObject var model: SettingsModel
    @State private var reading = ""
    @State private var word = ""
    @State private var selection = Set<UserDictionaryEntry>()

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField(UIStrings.Settings.reading, text: $reading)
                TextField(UIStrings.Settings.word, text: $word)
                Button(UIStrings.Settings.add) {
                    if model.addEntry(reading: reading, word: word) {
                        reading = ""
                        word = ""
                    }
                }
                .disabled(reading.isEmpty || word.isEmpty)
            }
            Table(model.settings.userDictionary, selection: $selection) {
                TableColumn(UIStrings.Settings.reading, value: \.reading)
                TableColumn(UIStrings.Settings.word, value: \.word)
            }
            HStack {
                Button(UIStrings.Settings.remove) {
                    model.removeEntries(selection)
                    selection = []
                }
                .disabled(selection.isEmpty)
                Spacer()
                Button(UIStrings.Settings.importDictionary) { model.importDictionary() }
                Button(UIStrings.Settings.exportDictionary) { model.exportDictionary() }
            }
            Text(UIStrings.Settings.dictionaryNote).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct AppearanceTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section(UIStrings.Settings.appearance) {
                ChoicePicker(title: UIStrings.Menu.theme, selection: model.binding(\.theme), label: UIStrings.Menu.label(for:))
                Slider(value: model.binding(\.candidateFontSize), in: Double(DesignTokens.Size.Candidate.fontSizeMin)...Double(DesignTokens.Size.Candidate.fontSizeMax), step: 1) {
                    Text(UIStrings.Settings.fontSize(Int(model.settings.candidateFontSize)))
                }
            }
            Section {
                Button(UIStrings.Settings.restoreDefaults) { model.restoreDefaults() }
            }
        }
        .formStyle(.grouped)
    }
}

extension UserDictionaryEntry: Identifiable {
    public var id: Self { self }
}
