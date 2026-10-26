import S90Domain
import SwiftUI

/// 設定の画面．項目の一覧は docs/user/reference/settings.md
struct SettingsView: View {
    static let size = NSSize(width: DesignTokens.Size.Settings.windowWidth, height: DesignTokens.Size.Settings.windowHeight)
    @ObservedObject var model: SettingsModel
    let sync: SyncCoordinator
    @State private var page: Page? = .input

    /// 左の一覧の項目．システム設定と同じく，左で選んだ項目を右に出す(上のタブには収まらない)
    enum Page: CaseIterable, Hashable {
        case input, conversion, correction, symbols, keys, dictionary, romaji, apps, appearance, usage, sync, backup, about

        var title: String {
            switch self {
            case .input: UIStrings.Settings.inputTab
            case .conversion: UIStrings.Settings.conversionTab
            case .correction: UIStrings.Features.correctionPage
            case .symbols: UIStrings.Features.symbolsPage
            case .keys: UIStrings.Keys.tab
            case .dictionary: UIStrings.Settings.dictionaryTab
            case .romaji: UIStrings.Settings.romajiTab
            case .apps: UIStrings.Settings.appsTab
            case .appearance: UIStrings.Settings.appearanceTab
            case .usage: UIStrings.Settings.usageTab
            case .sync: UIStrings.Sync.page
            case .backup: UIStrings.More.backup
            case .about: UIStrings.More.about
            }
        }

        /// SF Symbols の名前
        var symbol: String {
            switch self {
            case .input: "keyboard"
            case .conversion: "character.book.closed.ja"
            case .correction: "wand.and.stars"
            case .symbols: "arrow.right.square"
            case .keys: "command"
            case .dictionary: "text.book.closed"
            case .romaji: "textformat.abc"
            case .apps: "nosign.app"
            case .appearance: "paintbrush"
            case .usage: "chart.line.uptrend.xyaxis"
            case .sync: "arrow.triangle.2.circlepath"
            case .backup: "externaldrive"
            case .about: "info.circle"
            }
        }

        /// 検索で見つけるための言葉．ページの名前に加え，そのページにある項目の名前
        var keywords: [String] {
            switch self {
            case .input: [UIStrings.Choice.inputStyle, UIStrings.Choice.keyboardLayout, UIStrings.Settings.punctuation, UIStrings.Features.keypadDirect]
            case .conversion: [UIStrings.Menu.liveConversion, UIStrings.Choice.presentation, UIStrings.Choice.initialFocus, UIStrings.Features.okurigana,
                               UIStrings.Features.calculation, UIStrings.Features.postalCode, UIStrings.Features.handwriting,
                               UIStrings.Settings.dateConversion, UIStrings.Settings.emojiConversion]
            case .correction: [UIStrings.Features.exceptions, UIStrings.Features.rules, UIStrings.Features.correctsEnglish, UIStrings.Features.misreadings]
            case .symbols: [UIStrings.Features.sequences, UIStrings.Features.readings]
            // コマンドと状態の名前でも見つける(「全角空白」「英数」「切り替え」で キー設定 を出す)
            case .keys: [UIStrings.Keys.presetMenu] + KeymapCommand.allCases.map(UIStrings.Keys.label(for:))
                + KeymapState.allCases.map(UIStrings.Keys.label(for:)) + KeymapPreset.allCases.map(UIStrings.Keys.label(for:))
            case .sync: [UIStrings.Sync.folder, UIStrings.Sync.scopes, UIStrings.Sync.label(for: .dictionary)]
            default: []
            }
        }
    }

    @State private var query = ""

    /// 検索の言葉を含むページだけを並べる
    private var pages: [Page] {
        guard !query.isEmpty else { return Page.allCases }
        return Page.allCases.filter { page in ([page.title] + page.keywords).contains { $0.localizedCaseInsensitiveContains(query) } }
    }

    var body: some View {
        NavigationSplitView {
            List(pages, id: \.self, selection: $page) { page in
                Label(page.title, systemImage: page.symbol)
            }
            .navigationSplitViewColumnWidth(DesignTokens.Size.Settings.sidebarWidth)
            // 左の一覧を畳むボタンは要らない(見出しに重なる)
            .toolbar(removing: .sidebarToggle)
            .searchable(text: $query, placement: .sidebar, prompt: UIStrings.Features.search)
        } detail: {
            detail(for: page ?? .input)
                .navigationTitle((page ?? .input).title)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .alert(model.message ?? "", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button(UIStrings.Settings.ok) { model.message = nil }
        }
    }

    @ViewBuilder
    private func detail(for page: Page) -> some View {
        switch page {
        case .input: InputTab(model: model)
        case .conversion: ConversionTab(model: model)
        case .correction: CorrectionPage(model: model)
        case .symbols: SymbolsPage(model: model)
        case .keys: KeymapPage(model: model)
        case .dictionary: DictionaryPage(model: model)
        case .romaji: RomajiTab(model: model)
        case .apps: ExclusionsPage(model: model)
        case .appearance: AppearancePage(model: model)
        case .usage: UsageTab(model: model)
        case .sync: SyncPage(sync: sync)
        case .backup: BackupPage(model: model)
        case .about: AboutPage(model: model)
        }
    }
}

/// 列挙の値を選ぶ項目．values を渡さなければすべての値を並べる
struct ChoicePicker<Value: Hashable & CaseIterable>: View where Value.AllCases: RandomAccessCollection {
    let title: String
    let selection: Binding<Value>
    var values: [Value] = Array(Value.allCases)
    let label: (Value) -> String

    var body: some View {
        Picker(title, selection: selection) {
            ForEach(values, id: \.self) { Text(label($0)).tag($0) }
        }
    }
}

private struct InputTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section(UIStrings.Settings.inputStyleSection) {
                ResettablePicker(model: model, title: UIStrings.Choice.inputStyle, keyPath: \.inputStyle, label: UIStrings.Choice.label(for:))
                ResettablePicker(model: model, title: UIStrings.Choice.keyboardLayout, keyPath: \.keyboardLayout, label: UIStrings.Choice.label(for:))
                Text(UIStrings.Choice.keyboardLayoutNote).font(.caption).foregroundStyle(.secondary)
            }
            Section(UIStrings.Settings.characters) {
                ResettablePicker(model: model, title: UIStrings.Settings.punctuation, keyPath: \.punctuation, label: UIStrings.Settings.label(for:))
                ResettablePicker(model: model, title: UIStrings.Settings.brackets, keyPath: \.brackets, label: UIStrings.Settings.label(for:))
                ResettablePicker(model: model, title: UIStrings.Settings.slash, keyPath: \.slash, label: UIStrings.Settings.label(for:))
                ResettablePicker(model: model, title: UIStrings.Choice.yenKey, keyPath: \.yenKey, label: UIStrings.Choice.label(for:))
                ResettablePicker(model: model, title: UIStrings.Settings.spaceWidth, keyPath: \.spaceWidth, label: UIStrings.Settings.label(for:))
                ResettablePicker(model: model, title: UIStrings.Settings.numberWidth, keyPath: \.numberWidth, label: UIStrings.Settings.label(for:))
                ResettablePicker(model: model, title: UIStrings.More.alphabetWidth, keyPath: \.alphabetWidth, label: UIStrings.Settings.label(for:))
                ResettableToggle(model: model, title: UIStrings.More.shiftStartsAlphabet, keyPath: \.shiftStartsAlphabet)
                ResettableToggle(model: model, title: UIStrings.Features.keypadDirect, keyPath: \.keypadDirect)
            }
            Section(UIStrings.Settings.keys) {
                ResettableToggle(model: model, title: UIStrings.Settings.punctuationCommits, keyPath: \.punctuationCommits)
                ResettableToggle(model: model, title: UIStrings.Settings.numberKeySelection, keyPath: \.numberKeySelection)
                ResettableToggle(model: model, title: UIStrings.Settings.showsModeIndicator, keyPath: \.showsModeIndicator)
                ResettableRow(model: model, keyPath: \.modeIndicatorDuration) {
                    SecondsSlider(title: UIStrings.More.modeIndicatorDuration, value: model.binding(\.modeIndicatorDuration),
                                  range: DefaultSettings.modeIndicatorDurationRange)
                }
                .disabled(!model.settings.showsModeIndicator)
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
                ResettableToggle(model: model, title: UIStrings.Menu.liveConversion, keyPath: \.liveConversion)
                ResettablePicker(model: model, title: UIStrings.Choice.presentation, keyPath: \.candidatePresentation, label: UIStrings.Choice.label(for:))
                ResettablePicker(model: model, title: UIStrings.Choice.initialFocus, keyPath: \.initialFocus, label: UIStrings.Choice.label(for:))
                ResettablePicker(model: model, title: UIStrings.Choice.suggestionDisplay, keyPath: \.suggestionDisplay, label: UIStrings.Choice.label(for:))
                ResettableToggle(model: model, title: UIStrings.Choice.variantRow, keyPath: \.showsVariantRow)
                ResettableToggle(model: model, title: UIStrings.Choice.keyHints, keyPath: \.showsKeyHints)
                ResettableRow(model: model, keyPath: \.liveConversionDelay) {
                    SecondsSlider(title: UIStrings.More.liveConversionDelay, value: model.binding(\.liveConversionDelay),
                                  range: DefaultSettings.liveConversionDelayRange)
                }
                .disabled(!model.settings.liveConversion)
            }
            Section(UIStrings.More.candidates) {
                ResettableRow(model: model, keyPath: \.branchCandidatesPerPage) {
                    Stepper(value: model.binding(\.branchCandidatesPerPage), in: DefaultSettings.candidatesPerPageRange) {
                        LabeledContent(UIStrings.More.branchCandidates, value: "\(model.settings.branchCandidatesPerPage)")
                    }
                }
                ResettableRow(model: model, keyPath: \.listCandidatesPerPage) {
                    Stepper(value: model.binding(\.listCandidatesPerPage), in: DefaultSettings.candidatesPerPageRange) {
                        LabeledContent(UIStrings.More.listCandidates, value: "\(model.settings.listCandidatesPerPage)")
                    }
                }
            }
            Section(UIStrings.More.typo) {
                ResettablePicker(model: model, title: UIStrings.Choice.typoCorrection, keyPath: \.typoCorrection, label: UIStrings.Choice.label(for:))
                Group {
                    ResettablePicker(model: model, title: UIStrings.More.correctionSensitivity, keyPath: \.correctionSensitivity, label: UIStrings.More.label(for:))
                    ResettableToggle(model: model, title: UIStrings.More.showsSuggestions, keyPath: \.showsSuggestions)
                    ResettableRow(model: model, keyPath: \.correctionDelay) {
                        SecondsSlider(title: UIStrings.More.correctionDelay, value: model.binding(\.correctionDelay), range: DefaultSettings.correctionDelayRange)
                    }
                }
                .disabled(model.settings.typoCorrection != .standard)
            }
            Section(UIStrings.Features.okurigana) {
                ResettablePicker(model: model, title: UIStrings.Features.okurigana, keyPath: \.okuriganaStyle, label: UIStrings.Features.label(for:))
            }
            Section(UIStrings.Settings.specialConversion) {
                ResettableToggle(model: model, title: UIStrings.Features.calculation, keyPath: \.calculation)
                ResettableToggle(model: model, title: UIStrings.Features.postalCode, keyPath: \.postalCodeConversion)
                ResettableToggle(model: model, title: UIStrings.Features.handwriting, keyPath: \.handwriting)
                ResettableToggle(model: model, title: UIStrings.Settings.dateConversion, keyPath: \.dateConversion)
                ResettableToggle(model: model, title: UIStrings.Settings.homophoneNotes, keyPath: \.homophoneNotes)
                ResettableToggle(model: model, title: UIStrings.Settings.misuseNotes, keyPath: \.misuseNotes)
                ResettableToggle(model: model, title: UIStrings.Settings.symbolConversion, keyPath: \.symbolConversion)
                ResettableToggle(model: model, title: UIStrings.Settings.emojiConversion, keyPath: \.emojiConversion)
            }
            Section(UIStrings.Settings.learning) {
                ResettablePicker(model: model, title: UIStrings.Settings.learning, keyPath: \.learning, label: UIStrings.Settings.label(for:))
                Button(UIStrings.Settings.resetLearning, role: .destructive) { model.resetLearning() }
            }
        }
        .formStyle(.grouped)
    }
}

/// 辞書のページ．登録した単語と，取り込んだ辞書(R-16)を切り替えて出す
private struct DictionaryPage: View {
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
            .padding(.vertical, 8)
            if showsImported {
                ImportedDictionariesView(model: model)
            } else {
                DictionaryTab(model: model).padding()
            }
        }
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

/// 利用者が足すローマ字の綴り．標準の表に重ね，同じ綴りは利用者のものを使う
private struct RomajiTab: View {
    @ObservedObject var model: SettingsModel
    @State private var keys = ""
    @State private var kana = ""
    @State private var selection = Set<RomajiRule>()

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField(UIStrings.Settings.romajiKeys, text: $keys)
                TextField(UIStrings.Settings.romajiKana, text: $kana)
                Button(UIStrings.Settings.add) {
                    if model.addRomajiRule(keys: keys, kana: kana) {
                        keys = ""
                        kana = ""
                    }
                }
                .disabled(keys.isEmpty || kana.isEmpty)
            }
            Table(model.settings.customRomaji, selection: $selection) {
                TableColumn(UIStrings.Settings.romajiKeys, value: \.keys)
                TableColumn(UIStrings.Settings.romajiKana, value: \.kana)
            }
            HStack {
                Button(UIStrings.Settings.remove) {
                    model.update { $0.customRomaji.removeAll { selection.contains($0) } }
                    selection = []
                }
                .disabled(selection.isEmpty)
                Spacer()
            }
            Text(UIStrings.Settings.romajiNote).font(.caption).foregroundStyle(.secondary)
        }
    }
}

extension RomajiRule: @retroactive Identifiable {
    public var id: Self { self }
}

extension ProfileRule: @retroactive Identifiable {
    public var id: Self { self }
}

/// 使い方の記録．回数だけを端末の中に持つ
private struct UsageTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let counts = model.usageCounts
        Form {
            Section {
                ResettableToggle(model: model, title: UIStrings.Settings.recordsUsage, keyPath: \.recordsUsage)
                Text(UIStrings.Settings.usageNote).font(.caption).foregroundStyle(.secondary)
            }
            Section(UIStrings.Settings.usageTab) {
                LabeledContent(UIStrings.Settings.firstCandidateRate, value: counts.firstCandidateRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "-")
                LabeledContent(UIStrings.Settings.commits, value: "\(counts.commits)")
                LabeledContent(UIStrings.Settings.conversionsOpened, value: "\(counts.conversionsOpened)")
                LabeledContent(UIStrings.Settings.segmentsChanged, value: "\(counts.segmentsChanged)")
                LabeledContent(UIStrings.Settings.readingCorrections, value: "\(counts.readingCorrections) / \(counts.readingCorrectionsUndone)")
                LabeledContent(UIStrings.Settings.englishCorrections, value: "\(counts.englishCorrections) / \(counts.englishCorrectionsUndone)")
            }
            Section {
                Button(UIStrings.Settings.resetUsage, role: .destructive) { model.resetUsage() }
            }
        }
        .formStyle(.grouped)
    }
}

extension UserDictionaryEntry: @retroactive Identifiable {
    public var id: Self { self }
}

/// 秒で値を選ぶ項目．今の値を右に出す．動かしている間は保存せず，手を離したときに保存する(1 段ごとに設定のファイルを書き直さない)
struct SecondsSlider: View {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    @State private var editing: Double?

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: Binding(get: { editing ?? value.wrappedValue }, set: { editing = $0 }), in: range, step: 0.1) { isEditing in
                    guard !isEditing, let editing else { return }
                    value.wrappedValue = editing
                    self.editing = nil
                }
                .frame(width: 180)
                Text(UIStrings.More.seconds(editing ?? value.wrappedValue)).monospacedDigit().frame(width: 52, alignment: .trailing)
            }
        }
    }
}
