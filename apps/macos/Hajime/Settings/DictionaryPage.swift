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
            .padding(.top, DesignTokens.Size.Space.group)
            .padding(.bottom, DesignTokens.Size.Space.section)
            // 送った中身を切り替えの下で切る(切り替えの下に中身が食い込んで見えないように)
            Group {
                switch tab {
                case .userWords: UserWordsView(model: model)
                case .imported: ImportedDictionariesView(model: model)
                case .terms: TermDictionaryView(model: model)
                }
            }
            .clipped()
        }
        // 単語の登録とユーザー辞書を開く操作では，登録した単語を出す
        .onAppear(perform: showUserWordsIfAsked)
        .onChange(of: model.showsUserWords) { _, _ in showUserWordsIfAsked() }
    }

    private func showUserWordsIfAsked() {
        guard model.showsUserWords else { return }
        tab = .userWords
        model.showsUserWords = false
    }
}

/// 専門用語の辞書(R-29)．使うかと，分野ごとのオン・オフ．既定はすべて使う(見本の画像にも写す．SnapshotRenderer)
struct TermDictionaryView: View {
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
            }
            Section(UIStrings.Terms.fields) {
                ForEach(Self.fields, id: \.0) { field, keyPath in
                    ResettableToggle(model: model, title: field.name, keyPath: keyPath)
                }
            }
            .disabled(model, unless: \.termDictionary)
        }
        .formStyle(.grouped)
    }
}

/// 登録した単語．同じ読みに別の単語を登録できるので，読みと単語の両方が同じものだけを重なりとみなす
private struct UserWordsView: View {
    @ObservedObject var model: SettingsModel
    /// 単語の欄の下の書き方のチップを開いているか(次に開いたときも同じにする)
    @AppStorage("settings.templates.dictionary.open") private var templatesOpen = false

    var body: some View {
        Form {
            Section {
                ResettableToggle(model: model, title: UIStrings.Extras.dynamicDictionary, keyPath: \.dynamicDictionary)
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
                // スイッチがオフなら書き方は値にならないので，書き方のボタンもチップも出さない
                .assistingTemplates(model.settings.dynamicDictionary
                    ? TemplateAssist(reference: UIStrings.Templates.word, target: .value, isOpen: $templatesOpen) : nil)
                .showingResult { _, word in model.settings.dynamicDictionary ? Self.result(of: word) : nil }
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

    /// 単語に書き方があれば，今入れたときの値と，置き換えられない部分(無ければ nil)
    private static func result(of word: String) -> RuleResult? {
        let values = TextTemplate.Values(now: SystemCalendar(clock: Date.init).now(), uuid: { UUID().uuidString }, random: { Int.random(in: $0) })
        let problems = TextTemplate.problems(in: word, values: values)
        guard TextTemplate.containsPlaceholder(word) || !problems.isEmpty else { return nil }
        return RuleResult(text: TextTemplate.expand(word, values: values), problems: problems)
    }

    private static func option(_ wordClass: WordClass) -> RuleKinds.Option {
        .init(id: wordClass.rawValue, title: UIStrings.Settings.label(for: wordClass))
    }
}
