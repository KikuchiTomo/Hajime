import S90Application
import S90Domain
import SwiftUI

/// 英字で打った語を英語にするか日本語にするかの見分け方(英字入力(自動)とローマ字入力の英単語．R-05，R-02)．
/// 打った文を試して結果を見ながら，いつも英語・いつも日本語にする語と，前の語による決まりを足せる
struct WordLanguagePage: View {
    @ObservedObject var model: SettingsModel
    @State private var sample = ""
    @State private var preceding = ""
    @State private var ruleWord = ""
    @State private var ruleContext = WordLanguageContext.afterJapanese
    @State private var ruleLanguage = WordLanguage.japanese

    private var settings: WordLanguageSettings { model.settings.wordLanguage }

    var body: some View {
        Form {
            Section {
                ResettableToggle(model: model, title: UIStrings.Features.usesContext, keyPath: \.wordLanguage.usesContext)
                ResettableToggle(model: model, title: UIStrings.Features.avoidsOffensive, keyPath: \.wordLanguage.avoidsOffensive)
            } header: {
                Text(UIStrings.Features.languageJudging)
            } footer: {
                Text(UIStrings.Features.usesContextNote).font(.caption).foregroundStyle(.secondary)
            }
            if let preview = model.previewLanguage {
                Section(UIStrings.Features.tryLanguage) {
                    TextField(UIStrings.Features.tryPlaceholder, text: $sample)
                        .textFieldStyle(.roundedBorder)
                    TextField(UIStrings.Features.tryPreceding, text: $preceding)
                        .textFieldStyle(.roundedBorder)
                    let words = sample.isEmpty ? [] : preview(sample, preceding.isEmpty ? nil : preceding)
                    if !words.isEmpty {
                        WrappingStack(spacing: 6) {
                            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                                resultChip(word)
                            }
                        }
                    }
                }
            }
            wordList(title: UIStrings.Features.englishWords, language: .english,
                     empty: UIStrings.Features.englishWordsEmpty)
            wordList(title: UIStrings.Features.japaneseWords, language: .japanese,
                     empty: UIStrings.Features.japaneseWordsEmpty)
            Section {
                HStack {
                    TextField(UIStrings.Features.languageRuleWord, text: $ruleWord)
                        .onSubmit(addRule)
                    Picker(UIStrings.Features.languageRuleContext, selection: $ruleContext) {
                        ForEach(WordLanguageContext.allCases, id: \.self) { Text(UIStrings.Features.label(for: $0)).tag($0) }
                    }
                    .fixedSize()
                    Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
                    Picker(UIStrings.Features.languageRuleResult, selection: $ruleLanguage) {
                        ForEach(WordLanguage.allCases, id: \.self) { Text(UIStrings.Features.label(for: $0)).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button(UIStrings.Settings.add, action: addRule)
                        .disabled(ruleWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(settings.rules, id: \.self) { rule in
                    HStack {
                        Text(rule.word).monospaced()
                        Spacer()
                        Text("\(UIStrings.Features.languageRuleContext)：\(UIStrings.Features.label(for: rule.context))").foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
                        Picker(UIStrings.Features.languageRuleResult, selection: ruleBinding(rule)) {
                            ForEach(WordLanguage.allCases, id: \.self) { Text(UIStrings.Features.label(for: $0)).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        removeButton { $0.wordLanguage.rules.removeAll { $0 == rule } }
                    }
                }
            } header: {
                Text(UIStrings.Features.languageRules)
            } footer: {
                Text(UIStrings.Features.languageNote).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// 試した結果の 1 語．入る文字と，英語か日本語かを並べる
    private func resultChip(_ word: WordLanguagePreview.Word) -> some View {
        VStack(spacing: 2) {
            Text(word.shown)
            Text(UIStrings.Features.label(for: word.language))
                .font(.caption2)
                .foregroundStyle(word.language == .japanese ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .contextMenu {
            // 試した語をそのまま一覧に足せるようにする
            Button(UIStrings.Features.englishWords) { add(word.typed, to: .english) }
            Button(UIStrings.Features.japaneseWords) { add(word.typed, to: .japanese) }
        }
        .accessibilityElement(children: .combine)
    }

    private func wordList(title: String, language: WordLanguage, empty: String) -> some View {
        Section(title) {
            RuleListEditor(model: model, spec: .languageWords(language), labels: .init(
                key: UIStrings.Features.wordPlaceholder, value: nil, empty: empty))
        }
    }

    /// 語を一覧に足す．もう一方の一覧にあれば移す．足せたら true
    @discardableResult
    private func add(_ text: String, to language: WordLanguage) -> Bool {
        let word = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard WordLanguageSettings.isValidWord(word) else {
            model.message = UIStrings.Features.invalidWord
            return false
        }
        let listed = language == .english ? settings.englishWords : settings.japaneseWords
        guard !listed.contains(word) else {
            model.message = UIStrings.Features.alreadyListed
            return false
        }
        return model.update { current in
            current.wordLanguage.englishWords.removeAll { $0 == word }
            current.wordLanguage.japaneseWords.removeAll { $0 == word }
            switch language {
            case .english: current.wordLanguage.englishWords.insert(word, at: 0)
            case .japanese: current.wordLanguage.japaneseWords.insert(word, at: 0)
            }
            current.wordLanguage.clampToValidRanges()
        }
    }

    private func addRule() {
        let rule = WordLanguageRule(word: ruleWord.trimmingCharacters(in: .whitespaces).lowercased(), context: ruleContext, language: ruleLanguage)
        guard rule.isValid else {
            model.message = UIStrings.Features.invalidWord
            return
        }
        if model.update({ current in
            current.wordLanguage.rules.removeAll { $0.word == rule.word && $0.context == rule.context }
            current.wordLanguage.rules.append(rule)
            current.wordLanguage.clampToValidRanges()
        }) {
            ruleWord = ""
        }
    }

    /// 決まりの結果を一覧の中で変える
    private func ruleBinding(_ rule: WordLanguageRule) -> Binding<WordLanguage> {
        Binding(get: { rule.language }, set: { language in
            model.update { current in
                guard let index = current.wordLanguage.rules.firstIndex(of: rule) else { return }
                current.wordLanguage.rules[index].language = language
            }
        })
    }

    private func removeButton(_ change: @escaping (inout S90Domain.Settings) -> Void) -> some View {
        Button {
            model.update(change)
        } label: {
            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(UIStrings.Settings.remove)
        .accessibilityLabel(UIStrings.Settings.remove)
    }
}

/// 子を横に並べ，幅に収まらなければ次の行に送る
private struct WrappingStack: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
