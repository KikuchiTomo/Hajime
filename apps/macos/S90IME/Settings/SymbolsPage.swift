import S90Domain
import SwiftUI

/// 記号の決まり(項目 47)．既定の決まりを一覧にし，書き換え・無効化・追加・既定に戻すができる．
/// 既定の決まりは変えず，変えた分だけを設定に重ねるので，版が上がって既定が増えても変更は残る
struct SymbolsPage: View {
    @ObservedObject var model: SettingsModel
    @State private var query = ""
    @State private var newInput = ""
    @State private var newOutput = ""
    @State private var newKind = SymbolRule.Kind.sequence

    /// 一覧の行．既定の決まりと利用者の決まりを合わせたもの
    private struct Row: Identifiable {
        var kind: SymbolRule.Kind
        var input: String
        var defaultOutput: String?
        var rule: SymbolRule?

        var id: String { "\(kind.rawValue):\(input)" }
        var output: String { rule?.output ?? defaultOutput ?? "" }
        var isEnabled: Bool { rule?.isEnabled ?? true }
    }

    private func rows(_ kind: SymbolRule.Kind) -> [Row] {
        let rules = model.settings.symbolRules.filter { $0.kind == kind }
        let defaults: [(String, String)] = kind == .sequence
            ? SymbolSequenceSet.defaultRules.map { ($0.input, $0.symbol) }
            : SymbolDictionary.defaultEntries.map { ($0.reading, $0.symbols.joined(separator: " ")) }
        var result = defaults.map { input, output in Row(kind: kind, input: input, defaultOutput: output, rule: rules.first { $0.input == input }) }
        for rule in rules where !defaults.contains(where: { $0.0 == rule.input }) {
            result.append(Row(kind: kind, input: rule.input, defaultOutput: nil, rule: rule))
        }
        guard !query.isEmpty else { return result }
        return result.filter { $0.input.localizedCaseInsensitiveContains(query) || $0.output.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Picker("", selection: $newKind) {
                        Text(UIStrings.Features.sequences).tag(SymbolRule.Kind.sequence)
                        Text(UIStrings.Features.readings).tag(SymbolRule.Kind.reading)
                    }
                    .labelsHidden()
                    .fixedSize()
                    TextField(newKind == .sequence ? UIStrings.Features.input : UIStrings.Features.readingInput, text: $newInput)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    TextField(newKind == .sequence ? UIStrings.Features.output : UIStrings.Features.readingOutput, text: $newOutput)
                        .onSubmit(add)
                    Button(UIStrings.Settings.add, action: add)
                        .disabled(newInput.isEmpty || newOutput.isEmpty)
                }
            }
            section(UIStrings.Features.sequences, kind: .sequence)
            section(UIStrings.Features.readings, kind: .reading)
        }
        .formStyle(.grouped)
        .searchable(text: $query, placement: .toolbar, prompt: UIStrings.Features.search)
    }

    private func section(_ title: String, kind: SymbolRule.Kind) -> some View {
        Section(title) {
            ForEach(rows(kind)) { row in
                RowView(row: row, model: model)
            }
        }
    }

    private struct RowView: View {
        let row: Row
        @ObservedObject var model: SettingsModel
        @State private var editing: String?

        var body: some View {
            HStack {
                Toggle("", isOn: Binding(get: { row.isEnabled }, set: { set(enabled: $0) }))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                Text(row.input).monospaced().frame(width: 140, alignment: .leading)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                TextField("", text: Binding(get: { editing ?? row.output }, set: { editing = $0 }))
                    .onSubmit(commit)
                    .disabled(!row.isEnabled)
                if row.rule != nil {
                    Text(row.defaultOutput == nil ? UIStrings.Features.added : UIStrings.Features.changed)
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        model.update { $0.symbolRules.removeAll { $0.kind == row.kind && $0.input == row.input } }
                    } label: {
                        Image(systemName: row.defaultOutput == nil ? "minus.circle.fill" : "arrow.uturn.backward.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help(row.defaultOutput == nil ? UIStrings.Settings.remove : UIStrings.Features.restoreDefault)
                    .accessibilityLabel(row.defaultOutput == nil ? UIStrings.Settings.remove : UIStrings.Features.restoreDefault)
                }
            }
            .opacity(row.isEnabled ? 1 : 0.5)
        }

        private func set(enabled: Bool) {
            save(SymbolRule(kind: row.kind, input: row.input, output: row.output, isEnabled: enabled))
        }

        private func commit() {
            guard let editing else { return }
            save(SymbolRule(kind: row.kind, input: row.input, output: editing.trimmingCharacters(in: .whitespaces), isEnabled: row.isEnabled))
            self.editing = nil
        }

        /// 既定と同じに戻ったら，重ねている決まりを外す
        private func save(_ rule: SymbolRule) {
            model.update { current in
                current.symbolRules.removeAll { $0.kind == rule.kind && $0.input == rule.input }
                if rule.isEnabled, rule.output == row.defaultOutput { return }
                current.symbolRules.append(rule)
            }
        }
    }

    private func add() {
        let rule = SymbolRule(kind: newKind, input: newInput.trimmingCharacters(in: .whitespaces), output: newOutput.trimmingCharacters(in: .whitespaces))
        guard rule.isValid else {
            model.message = UIStrings.Features.invalidSymbol
            return
        }
        if model.update({ current in
            current.symbolRules.removeAll { $0.kind == rule.kind && $0.input == rule.input }
            current.symbolRules.append(rule)
        }) {
            newInput = ""
            newOutput = ""
        }
    }
}
