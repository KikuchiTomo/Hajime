import HajimeDomain
import HajimePersistence
import SwiftUI

/// 辞書のページ．登録した単語と，取り込んだ辞書(R-16)と，専門用語の辞書(R-29)を切り替えて出す
struct DictionaryPage: View {
    @ObservedObject var model: SettingsModel
    @State private var tab = Tab.userWords

    private enum Tab: CaseIterable {
        case userWords, imported, terms

        var title: String {
            switch self {
            case .userWords: UIStrings.Dictionaries.userWords
            case .imported: UIStrings.Dictionaries.imported
            case .terms: UIStrings.Dictionaries.terms
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 8)
            switch tab {
            case .userWords: UserWordsView(model: model)
            case .imported: ImportedDictionariesView(model: model)
            case .terms: TermDictionaryView(model: model)
            }
        }
        // 単語の登録とユーザー辞書を開く操作では，登録した単語を出す
        .onAppear(perform: showUserWordsIfAsked)
        .onChange(of: model.showsUserWords) { _, _ in showUserWordsIfAsked() }
    }

    private func showUserWordsIfAsked() {
        guard model.showsUserWords else { return }
        showsImported = false
        model.showsUserWords = false
    }
}

/// 専門用語の辞書(R-29)．使うかと，分野ごとのオン・オフ．既定はすべて使う
private struct TermDictionaryView: View {
    @ObservedObject var model: SettingsModel

    /// 分野と設定の項目(並びは TermField.allCases と同じ)
    private static let fields: [(TermField, WritableKeyPath<HajimeDomain.Settings, Bool>)] = [
        (.computing, \.termFields.computing),
        (.medicine, \.termFields.medicine),
        (.biology, \.termFields.biology),
        (.chemistry, \.termFields.chemistry),
        (.physics, \.termFields.physics),
        (.mathematics, \.termFields.mathematics),
        (.earth, \.termFields.earth),
        (.engineering, \.termFields.engineering),
        (.architecture, \.termFields.architecture),
        (.law, \.termFields.law),
        (.economics, \.termFields.economics),
        (.business, \.termFields.business),
        (.linguistics, \.termFields.linguistics),
        (.philosophy, \.termFields.philosophy),
        (.religion, \.termFields.religion),
        (.music, \.termFields.music),
        (.design, \.termFields.design),
        (.food, \.termFields.food),
        (.sports, \.termFields.sports),
        (.games, \.termFields.games),
        (.military, \.termFields.military),
        (.agriculture, \.termFields.agriculture),
        (.performingArts, \.termFields.performingArts),
        (.history, \.termFields.history),
    ]

    var body: some View {
        Form {
            Section {
                ResettableToggle(model: model, title: UIStrings.Terms.enabled, keyPath: \.termDictionary)
            } footer: {
                Text(UIStrings.Terms.note).font(.caption).foregroundStyle(.secondary)
            }
            Section(UIStrings.Terms.fields) {
                ForEach(Self.fields, id: \.0) { field, keyPath in
                    ResettableToggle(model: model, title: field.name, keyPath: keyPath)
                }
            }
            .disabled(!model.settings.termDictionary)
        }
        .formStyle(.grouped)
    }
}

/// 登録した単語．同じ読みに別の単語を登録できるので，読みと単語の両方が同じものだけを重なりとみなす
private struct UserWordsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                ResettableToggle(model: model, title: UIStrings.Extras.dynamicDictionary, keyPath: \.dynamicDictionary)
                Text(UIStrings.Extras.dynamicDictionaryNote)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                TemplateReference()
                VStack(alignment: .leading) {
                    Text(UIStrings.Extras.templateFilters)
                    Text(UIStrings.Extras.dateFormatSymbols)
                }
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section {
                RuleListEditor(
                    labels: .init(key: UIStrings.Settings.reading, value: UIStrings.Settings.word,
                                  empty: UIStrings.Settings.dictionaryEmpty, note: UIStrings.Settings.comment, notePrompt: UIStrings.Settings.commentPrompt),
                    items: model.settings.userDictionary.map {
                        RuleItem(id: "\($0.reading)\t\($0.word)", key: $0.reading, value: $0.word, kind: $0.wordClass.rawValue,
                                 kindTitle: UIStrings.Settings.label(for: $0.wordClass), note: $0.comment)
                    },
                    kinds: Self.wordClasses,
                    problem: { reading, word in
                        UserDictionaryEntry(reading: reading, word: word).isValid ? nil : UIStrings.Settings.invalidEntry
                    },
                    save: { reading, word, kind, comment, editing in
                        model.saveEntry(replacing: editing.map { UserDictionaryEntry(reading: $0.key, word: $0.value) }, reading: reading, word: word,
                                        wordClass: kind.flatMap(WordClass.init(rawValue:)) ?? DefaultSettings.userWordClass, comment: comment ?? "")
                    },
                    remove: { items in
                        model.removeEntries(items.map { UserDictionaryEntry(reading: $0.key, word: $0.value) })
                    },
                    importFile: model.importDictionary,
                    exportFile: model.exportDictionary,
                    keysAreUnique: false,
                    tableHeight: DesignTokens.Size.Settings.userDictionaryTableHeight
                )
                .prefilled($model.userWordDraft)
            } footer: {
                Text(UIStrings.Settings.dictionaryNote).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// 品詞のポップアップ．Microsoft IME の単語の登録と同じ順に並べ，ほかの品詞は「その他」にまとめる
    private static let wordClasses = RuleKinds(
        label: UIStrings.Settings.wordClass,
        groups: [
            .init(options: [option(.noun)]),
            .init(title: UIStrings.Settings.personNameGroup, options: [option(.surname), option(.givenName), option(.personName)]),
            .init(options: [option(.place), option(.abbreviation), option(.symbol)]),
            .init(title: UIStrings.Settings.otherWordClasses,
                  options: [option(.properNoun), option(.organization), option(.suruNoun), option(.adjectivalNoun), option(.adverb), option(.interjection)]),
        ],
        defaultID: DefaultSettings.userWordClass.rawValue,
        note: { $0 == WordClass.abbreviation.rawValue ? UIStrings.Settings.abbreviationNote : nil }
    )

    private static func option(_ wordClass: WordClass) -> RuleKinds.Option {
        .init(id: wordClass.rawValue, title: UIStrings.Settings.label(for: wordClass))
    }
}

/// 単語に書ける書き方(TextTemplate)の表．書き方・入るもの・今入れたときの値を並べ，下に登録の例を添える．
/// 「今入れると」は 1 秒ごとに求め直す．UUID と整数は入れるたびに変わるので，ページを開いたときの例を 1 つ出す
private struct TemplateReference: View {
    @State private var uuid = UUID().uuidString
    @State private var randomSeed = Int.random(in: 0..<Int(UInt16.max))

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let values = values(at: timeline.date)
            VStack(alignment: .leading) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: DesignTokens.Size.Settings.tableColumnSpacing) {
                    GridRow {
                        Text(UIStrings.Extras.templateSyntax)
                        Text(UIStrings.Extras.templateMeaning)
                        Text(UIStrings.Extras.templateNow)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Divider()
                    ForEach(UIStrings.Extras.templateRows, id: \.syntax) { row in
                        GridRow {
                            Text(row.syntax).font(.body.monospaced()).textSelection(.enabled).fixedSize()
                            Text(row.meaning).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            // UUID のような長い値は 1 行にし，間を省く(表が行の幅を超えないように)
                            Text(TextTemplate.expand(row.syntax, values: values)).font(.body.monospacedDigit()).textSelection(.enabled)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                Divider()
                Text(UIStrings.Extras.templateExample(TextTemplate.expand(UIStrings.Extras.templateExampleWord, values: values)))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func values(at date: Date) -> TextTemplate.Values {
        let calendar = SystemCalendar(clock: { date })
        // 呼ぶたびに次の数にする(英数字の乱数が同じ字の繰り返しにならないように)．求め直すたびに同じ並びから始めるので，例は変わらない
        var state = UInt64(randomSeed)
        return TextTemplate.Values(now: calendar.now(), uuid: { uuid }, random: { range in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return range.lowerBound + Int((state >> 33) % UInt64(range.count))
        })
    }
}
