import HajimeApplication
import HajimeDomain
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
    /// 一覧に足す先を選んでいる試した語(結果のタグを押したとき)
    @State private var adding: String?

    private var settings: WordLanguageSettings { model.settings.wordLanguage }

    var body: some View {
        Form {
            Section {
                ExampleToggle(model: model, title: UIStrings.Features.usesContext, keyPath: \.wordLanguage.usesContext,
                              example: UIStrings.Features.usesContextExample)
                ResettableToggle(model: model, title: UIStrings.Features.avoidsOffensive, keyPath: \.wordLanguage.avoidsOffensive)
            } header: {
                Text(UIStrings.Features.languageJudging)
            }
            if let preview = model.previewLanguage {
                Section(UIStrings.Features.tryLanguage) {
                    TextField(UIStrings.Features.tryPlaceholder, text: $sample)
                        .textFieldStyle(.roundedBorder)
                    TextField(UIStrings.Features.tryPreceding, text: $preceding)
                        .textFieldStyle(.roundedBorder)
                    let words = sample.isEmpty ? [] : preview(sample, preceding.isEmpty ? nil : preceding)
                    if !words.isEmpty {
                        WrappingStack(spacing: DesignTokens.Size.Settings.previewButtonGap) {
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
                    TextField(UIStrings.Features.languageRuleWord, text: $ruleWord, prompt: Text(UIStrings.Features.languageRuleWord))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addRule)
                    Text(UIStrings.Features.languageRuleContext).foregroundStyle(.secondary)
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
                // ほかの一覧の足す行と同じく，部品の名前は Form の名前の列に出さない(出すと欄が潰れる)．「前」は欄の後ろの文字で示す
                .labelsHidden()
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
            }
            Section {
                ExampleToggle(model: model, title: UIStrings.Extras.englishTermCandidates, keyPath: \.englishTermCandidates,
                              example: UIStrings.Extras.englishTermCandidatesExample)
            } header: {
                Text(UIStrings.Extras.englishTermsSection)
            }
            Section {
                RuleListEditor(model: model, spec: .englishTerms, labels: .init(
                    key: UIStrings.Extras.englishTermPlaceholder, value: nil, keyPrompt: UIStrings.Extras.englishTermPrompt,
                    empty: UIStrings.Extras.englishTermsEmpty))
                    .disabled(model, unless: \.englishTermCandidates)
            } header: {
                Text(UIStrings.Extras.englishTerms)
            }
        }
        .formStyle(.grouped)
    }

    /// 試した結果の 1 語．入る文字と，英語か日本語かを並べる．押すと，その語を常に英語・常に日本語にする一覧に足すボタンを出す
    private func resultChip(_ word: WordLanguagePreview.Word) -> some View {
        Button { adding = word.typed } label: {
            VStack(spacing: DesignTokens.Size.Space.fine) {
                HStack(spacing: DesignTokens.Size.Space.inline) {
                    Text(word.shown)
                    Image(systemName: "chevron.down").imageScale(.small).foregroundStyle(.secondary)
                }
                Text(UIStrings.Features.label(for: word.language))
                    .font(.caption2)
                    .foregroundStyle(word.language == .japanese ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .padding(.horizontal, DesignTokens.Size.Settings.previewChipPaddingX)
            .padding(.vertical, DesignTokens.Size.Settings.previewChipPaddingY)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: DesignTokens.Size.Settings.previewChipRadius))
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Size.Settings.previewChipRadius))
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(get: { adding == word.typed }, set: { if !$0 { adding = nil } }), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: DesignTokens.Size.Space.stack) {
                Button(UIStrings.Features.englishWords) { addFromPopover(word.typed, to: .english) }
                Button(UIStrings.Features.japaneseWords) { addFromPopover(word.typed, to: .japanese) }
            }
            .buttonStyle(.borderless)
            .padding(DesignTokens.Size.Space.section)
        }
        .contextMenu {
            Button(UIStrings.Features.englishWords) { add(word.typed, to: .english) }
            Button(UIStrings.Features.japaneseWords) { add(word.typed, to: .japanese) }
        }
    }

    /// 結果のタグから一覧に足し，足す先のボタンを閉じる
    private func addFromPopover(_ text: String, to language: WordLanguage) {
        add(text, to: language)
        adding = nil
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

    private func removeButton(_ change: @escaping (inout HajimeDomain.Settings) -> Void) -> some View {
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
