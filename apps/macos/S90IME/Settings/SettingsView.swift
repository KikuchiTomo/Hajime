import S90Domain
import SwiftUI

/// 設定の画面．項目の一覧は docs/user/reference/settings.md
struct SettingsView: View {
    static let size = NSSize(width: DesignTokens.Size.Settings.windowWidth, height: DesignTokens.Size.Settings.windowHeight)
    @ObservedObject var model: SettingsModel
    let sync: SyncCoordinator
    /// 開いているページ．窓の外(計測など)からも切り替えられるように持ち出す
    @Bindable var navigation: SettingsNavigation
    private var page: Page? { navigation.page }

    @State private var query = ""

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(query: query, selection: $navigation.page)
                .navigationSplitViewColumnWidth(DesignTokens.Size.Settings.sidebarWidth)
                // 左の一覧を畳むボタンは要らない(見出しに重なる)
                .toolbar(removing: .sidebarToggle)
                .searchable(text: $query, placement: .sidebar, prompt: UIStrings.Features.search)
        } detail: {
            SettingsPageStack(current: page ?? .input) { AnyView(detail(for: $0)) }
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
        case .language: WordLanguagePage(model: model)
        case .symbols: SymbolsPage(model: model)
        case .keys: KeymapPage(model: model)
        case .dictionary: DictionaryPage(model: model)
        case .romaji: RomajiPage(model: model)
        case .apps: ExclusionsPage(model: model)
        case .appearance: AppearancePage(model: model)
        case .usage: UsageTab(model: model)
        case .sync: SyncPage(sync: sync)
        case .backup: BackupPage(model: model)
        case .about: AboutPage(model: model)
        }
    }
}

/// 左の一覧．見出しごとにまとめ，検索の言葉を含むページだけを並べる
struct SettingsSidebar: View {
    let query: String
    @Binding var selection: SettingsView.Page?

    var body: some View {
        List(selection: $selection) {
            ForEach(SettingsView.Group.allCases, id: \.self) { group in
                let pages = pages(in: group)
                if !pages.isEmpty {
                    Section(group.title) {
                        ForEach(pages, id: \.self) { page in
                            Label(page.title, systemImage: page.symbol)
                        }
                    }
                }
            }
        }
    }

    private func pages(in group: SettingsView.Group) -> [SettingsView.Page] {
        guard !query.isEmpty else { return group.pages }
        return group.pages.filter { page in ([page.title] + page.keywords).contains { $0.localizedCaseInsensitiveContains(query) } }
    }
}

/// 設定の画面で開いているページ
@MainActor @Observable
final class SettingsNavigation {
    var page: SettingsView.Page?

    init(page: SettingsView.Page = .input) {
        self.page = page
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
                if model.settings.inputStyle == .englishAuto {
                    Text(UIStrings.Choice.englishAutoNote).font(.caption).foregroundStyle(.secondary)
                }
                ResettableToggle(model: model, title: UIStrings.Choice.englishInputLiveConversion, keyPath: \.englishInputLiveConversion)
                    .disabled(model.settings.inputStyle != .english)
                if model.settings.inputStyle == .english {
                    Text(UIStrings.Choice.englishInputLiveConversionNote).font(.caption).foregroundStyle(.secondary)
                }
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
            Section(UIStrings.Features.notation) {
                ResettablePicker(model: model, title: UIStrings.Features.okurigana, keyPath: \.okuriganaStyle, label: UIStrings.Features.label(for:))
                ResettableToggle(model: model, title: UIStrings.Features.prefersKatakana, keyPath: \.prefersKatakana)
            }
            Section(UIStrings.Settings.specialConversion) {
                ResettableToggle(model: model, title: UIStrings.Features.calculation, keyPath: \.calculation)
                ResettableToggle(model: model, title: UIStrings.Features.postalCode, keyPath: \.postalCodeConversion)
                ResettableToggle(model: model, title: UIStrings.Features.handwriting, keyPath: \.handwriting)
                ResettableToggle(model: model, title: UIStrings.Settings.dateConversion, keyPath: \.dateConversion)
                ResettableToggle(model: model, title: UIStrings.Settings.homophoneNotes, keyPath: \.homophoneNotes)
                ResettableToggle(model: model, title: UIStrings.Settings.misuseNotes, keyPath: \.misuseNotes)
                ResettableToggle(model: model, title: UIStrings.Settings.proofreading, keyPath: \.proofreading)
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

/// 秒で値を選ぶ項目．今の値を右に出す．動かしている間は保存せず，手を離したときに保存する(1 段ごとに設定のファイルを書き直さない)
struct SecondsSlider: View {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    @State private var editing: Double?

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: Binding(get: { editing ?? value.wrappedValue }, set: { editing = $0 }), in: range, step: DefaultSettings.secondsStep) { isEditing in
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
