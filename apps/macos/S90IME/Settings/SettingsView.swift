import S90Domain
import SwiftUI

/// 設定の画面．項目は Google 日本語入力・ATOK などの設定を調べて選んだ(docs/user/reference/settings.md)
struct SettingsView: View {
    static let size = NSSize(width: DesignTokens.Size.Settings.windowWidth, height: DesignTokens.Size.Settings.windowHeight)
    @ObservedObject var model: SettingsModel
    @State private var page: Page? = .input

    /// 左の一覧の項目．システム設定と同じく，左で選んだ項目を右に出す(上のタブには収まらない)
    enum Page: CaseIterable, Hashable {
        case input, conversion, correction, symbols, keys, dictionary, romaji, apps, appearance, usage, backup, about

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
            case .backup: "externaldrive"
            case .about: "info.circle"
            }
        }

        /// 検索で見つけるための言葉．ページの名前に加え，そのページにある項目の名前
        var keywords: [String] {
            switch self {
            case .input: [UIStrings.Choice.inputStyle, UIStrings.Choice.keyboardLayout, UIStrings.Settings.punctuation, UIStrings.Features.keypadDirect,
                          UIStrings.Features.modeKeysSection, UIStrings.Features.eisuKey, UIStrings.Features.kanaKey, UIStrings.Features.hankakuZenkakuKey]
            case .conversion: [UIStrings.Menu.liveConversion, UIStrings.Choice.presentation, UIStrings.Choice.initialFocus, UIStrings.Features.okurigana,
                               UIStrings.Features.calculation, UIStrings.Settings.dateConversion, UIStrings.Settings.emojiConversion]
            case .correction: [UIStrings.Features.exceptions, UIStrings.Features.rules, UIStrings.Features.correctsEnglish, UIStrings.Features.misreadings]
            case .symbols: [UIStrings.Features.sequences, UIStrings.Features.readings]
            case .keys: [UIStrings.Features.preset, UIStrings.Keys.label(for: .openSettings)]
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
        case .keys: KeysTab(model: model)
        case .dictionary: DictionaryTab(model: model)
        case .romaji: RomajiTab(model: model)
        case .apps: ExclusionsPage(model: model)
        case .appearance: AppearancePage(model: model)
        case .usage: UsageTab(model: model)
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
                ChoicePicker(title: UIStrings.Choice.inputStyle, selection: model.binding(\.inputStyle), label: UIStrings.Choice.label(for:))
                ChoicePicker(title: UIStrings.Choice.keyboardLayout, selection: model.binding(\.keyboardLayout), label: UIStrings.Choice.label(for:))
                Text(UIStrings.Choice.keyboardLayoutNote).font(.caption).foregroundStyle(.secondary)
            }
            Section(UIStrings.Settings.characters) {
                ChoicePicker(title: UIStrings.Settings.punctuation, selection: model.binding(\.punctuation), label: UIStrings.Settings.label(for:))
                ChoicePicker(title: UIStrings.Settings.brackets, selection: model.binding(\.brackets), label: UIStrings.Settings.label(for:))
                ChoicePicker(title: UIStrings.Settings.slash, selection: model.binding(\.slash), label: UIStrings.Settings.label(for:))
                ChoicePicker(title: UIStrings.Choice.yenKey, selection: model.binding(\.yenKey), label: UIStrings.Choice.label(for:))
                ChoicePicker(title: UIStrings.Settings.spaceWidth, selection: model.binding(\.spaceWidth), label: UIStrings.Settings.label(for:))
                ChoicePicker(title: UIStrings.Settings.numberWidth, selection: model.binding(\.numberWidth), label: UIStrings.Settings.label(for:))
                ChoicePicker(title: UIStrings.More.alphabetWidth, selection: model.binding(\.alphabetWidth), label: UIStrings.Settings.label(for:))
                Toggle(UIStrings.More.shiftStartsAlphabet, isOn: model.binding(\.shiftStartsAlphabet))
                ResettableToggle(model: model, title: UIStrings.Features.keypadDirect, keyPath: \.keypadDirect)
            }
            Section(UIStrings.Features.modeKeysSection) {
                ResettablePicker(model: model, title: UIStrings.Features.eisuKey, keyPath: \.modeKeys.eisu, label: UIStrings.Features.label(for:))
                ResettablePicker(model: model, title: UIStrings.Features.kanaKey, keyPath: \.modeKeys.kana, label: UIStrings.Features.label(for:))
                ResettablePicker(model: model, title: UIStrings.Features.hankakuZenkakuKey, keyPath: \.modeKeys.hankakuZenkaku, label: UIStrings.Features.label(for:))
                ResettablePicker(model: model, title: UIStrings.Features.henkanKey, keyPath: \.modeKeys.henkan, label: UIStrings.Features.label(for:))
                ResettablePicker(model: model, title: UIStrings.Features.muhenkanKey, keyPath: \.modeKeys.muhenkan, label: UIStrings.Features.label(for:))
            }
            Section(UIStrings.Settings.keys) {
                Toggle(UIStrings.Settings.punctuationCommits, isOn: model.binding(\.punctuationCommits))
                Toggle(UIStrings.Settings.numberKeySelection, isOn: model.binding(\.numberKeySelection))
                Toggle(UIStrings.Settings.showsModeIndicator, isOn: model.binding(\.showsModeIndicator))
                SecondsSlider(title: UIStrings.More.modeIndicatorDuration, value: model.binding(\.modeIndicatorDuration),
                              range: DefaultSettings.modeIndicatorDurationRange)
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
                Toggle(UIStrings.Menu.liveConversion, isOn: model.binding(\.liveConversion))
                ChoicePicker(title: UIStrings.Choice.presentation, selection: model.binding(\.candidatePresentation), label: UIStrings.Choice.label(for:))
                ChoicePicker(title: UIStrings.Choice.initialFocus, selection: model.binding(\.initialFocus), label: UIStrings.Choice.label(for:))
                Toggle(UIStrings.Choice.variantRow, isOn: model.binding(\.showsVariantRow))
                SecondsSlider(title: UIStrings.More.liveConversionDelay, value: model.binding(\.liveConversionDelay),
                              range: DefaultSettings.liveConversionDelayRange)
                    .disabled(!model.settings.liveConversion)
            }
            Section(UIStrings.More.candidates) {
                Stepper(value: model.binding(\.branchCandidatesPerPage), in: DefaultSettings.candidatesPerPageRange) {
                    LabeledContent(UIStrings.More.branchCandidates, value: "\(model.settings.branchCandidatesPerPage)")
                }
                Stepper(value: model.binding(\.listCandidatesPerPage), in: DefaultSettings.candidatesPerPageRange) {
                    LabeledContent(UIStrings.More.listCandidates, value: "\(model.settings.listCandidatesPerPage)")
                }
            }
            Section(UIStrings.More.typo) {
                ChoicePicker(title: UIStrings.Choice.typoCorrection, selection: model.binding(\.typoCorrection), label: UIStrings.Choice.label(for:))
                Group {
                    ChoicePicker(title: UIStrings.More.correctionSensitivity, selection: model.binding(\.correctionSensitivity), label: UIStrings.More.label(for:))
                    Toggle(UIStrings.More.showsSuggestions, isOn: model.binding(\.showsSuggestions))
                    SecondsSlider(title: UIStrings.More.correctionDelay, value: model.binding(\.correctionDelay), range: DefaultSettings.correctionDelayRange)
                }
                .disabled(model.settings.typoCorrection != .standard)
            }
            Section(UIStrings.Features.okurigana) {
                ResettablePicker(model: model, title: UIStrings.Features.okurigana, keyPath: \.okuriganaStyle, label: UIStrings.Features.label(for:))
            }
            Section(UIStrings.Settings.specialConversion) {
                ResettableToggle(model: model, title: UIStrings.Features.calculation, keyPath: \.calculation)
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
                Toggle(UIStrings.Settings.recordsUsage, isOn: model.binding(\.recordsUsage))
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

/// 変換中(分岐図)の操作ごとのキーの割り当て．「追加」を押してからキーを押すと割り当てる
private struct KeysTab: View {
    @ObservedObject var model: SettingsModel
    /// キーを待っている操作
    @State private var recording: ConversionCommand?

    var body: some View {
        Form {
            Section {
                Picker(UIStrings.Features.preset, selection: Binding(
                    get: { KeyPreset.matching(model.settings.conversionKeys) },
                    set: { preset in if let preset { model.update { $0.conversionKeys = preset.bindings } } }
                )) {
                    ForEach(KeyPreset.allCases, id: \.self) { Text(UIStrings.Features.label(for: $0)).tag(KeyPreset?.some($0)) }
                    if KeyPreset.matching(model.settings.conversionKeys) == nil {
                        Text(UIStrings.Features.customPreset).tag(KeyPreset?.none)
                    }
                }
            }
            commandSection(UIStrings.Keys.generalSection, ConversionCommand.allCases.filter(\.isGlobal))
            commandSection(UIStrings.Keys.conversionSection, ConversionCommand.allCases.filter { !$0.isGlobal })
            Section {
                Text(UIStrings.Keys.note).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button(UIStrings.Keys.restore) { model.update { $0.conversionKeys = .standard } }
            }
        }
        .formStyle(.grouped)
    }

    private func commandSection(_ title: String, _ commands: [ConversionCommand]) -> some View {
        Section(title) {
            ForEach(commands, id: \.self) { command in
                    HStack {
                        Text(UIStrings.Keys.label(for: command))
                        Spacer()
                        ForEach(model.settings.conversionKeys.strokes(for: command), id: \.self) { stroke in
                            Button {
                                model.update { $0.conversionKeys.remove(stroke, from: command) }
                            } label: {
                                Text(UIStrings.Keys.name(of: stroke)).monospaced()
                            }
                            .buttonStyle(.bordered)
                            .help(UIStrings.Settings.remove)
                        }
                        if recording == command {
                            KeyCapture { stroke in
                                if let stroke { model.update { $0.conversionKeys.assign(stroke, to: command) } }
                                recording = nil
                            }
                            .frame(width: 140, height: 22)
                            .overlay(Text(UIStrings.Keys.press).font(.caption).foregroundStyle(.secondary).allowsHitTesting(false))
                        } else {
                            Button(UIStrings.Keys.add) { recording = command }
                        }
                    }
            }
        }
    }
}

/// 次に押したキーを受け取る．Escape で取りやめる(nil を渡す)．割り当てられないキーは受け取らずに待つ
private struct KeyCapture: NSViewRepresentable {
    let onCapture: (KeyStroke?) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onCapture = onCapture
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ view: CaptureView, context: Context) {
        view.onCapture = onCapture
    }

    final class CaptureView: NSView {
        var onCapture: ((KeyStroke?) -> Void)?
        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 {
                onCapture?(nil)
                return
            }
            guard let key = NSEventKeyTranslator.translate(event), let stroke = KeyStroke(key) else { return }
            onCapture?(stroke)
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        }
    }
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
