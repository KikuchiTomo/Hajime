import S90Domain
import S90Persistence
import SwiftUI

/// 記号の決まり(項目 47)．既定の決まりを一覧にし，書き換え・無効化・追加・既定に戻すができる．
/// 既定の決まりは変えず，変えた分だけを設定に重ねるので，版が上がって既定が増えても変更は残る
struct SymbolsPage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            section(.sequence)
            section(.reading)
        }
        .formStyle(.grouped)
    }

    private func section(_ kind: SymbolRule.Kind) -> some View {
        let isSequence = kind == .sequence
        return Section(isSequence ? UIStrings.Features.sequences : UIStrings.Features.readings) {
            RuleListEditor(
                labels: .init(key: isSequence ? UIStrings.Features.input : UIStrings.Features.readingInput,
                              value: isSequence ? UIStrings.Features.output : UIStrings.Features.readingOutput,
                              empty: UIStrings.Features.symbolsEmpty),
                items: Self.items(kind, rules: model.settings.symbolRules),
                problem: { input, output in
                    SymbolRule(kind: kind, input: input, output: output).isValid
                        ? nil : (isSequence ? UIStrings.Features.invalidSymbol : UIStrings.Features.invalidReadingSymbol)
                },
                save: { input, output, editing in
                    let rule = SymbolRule(kind: kind, input: input, output: output, isEnabled: editing?.isEnabled ?? true)
                    return model.editRules(failure: UIStrings.RuleList.full) { Self.save(rule, replacing: editing?.key, in: &$0.symbolRules) }
                },
                remove: { items in
                    let inputs = Set(items.map(\.key))
                    model.update { $0.symbolRules.removeAll { $0.kind == kind && inputs.contains($0.input) } }
                },
                setEnabled: { item, isEnabled in
                    let rule = SymbolRule(kind: kind, input: item.key, output: item.value, isEnabled: isEnabled)
                    model.update { _ = Self.save(rule, replacing: nil, in: &$0.symbolRules) }
                },
                importFile: {
                    model.importRuleList { rows, settings in
                        rows.reduce(0) { count, row in
                            Self.save(SymbolRule(kind: kind, input: row.key, output: row.value), replacing: nil, in: &settings.symbolRules) ? count + 1 : count
                        }
                    }
                },
                exportFile: {
                    let rows = Self.items(kind, rules: model.settings.symbolRules).filter(\.isEnabled).map { RuleListFile.Row(key: $0.key, value: $0.value) }
                    model.exportRuleList(rows, fileName: isSequence ? "symbol-sequences.tsv" : "symbol-readings.tsv")
                },
                tableHeight: isSequence ? DesignTokens.Size.Settings.ruleTableHeight : DesignTokens.Size.Settings.userDictionaryTableHeight
            )
        }
    }

    /// 既定の決まり(入力と出力)．描き直すたびに並べ直さないよう，一度だけ作る
    private static let sequenceDefaults = SymbolSequenceSet.defaultRules.map { (input: $0.input, output: $0.symbol) }
    private static let readingDefaults = SymbolDictionary.defaultEntries.map { (input: $0.reading, output: $0.symbols.joined(separator: " ")) }

    private static func defaults(_ kind: SymbolRule.Kind) -> [(input: String, output: String)] {
        kind == .sequence ? sequenceDefaults : readingDefaults
    }

    /// 一覧の行．既定の決まりに利用者の決まりを重ね，利用者が足した決まりを後ろに並べる
    private static func items(_ kind: SymbolRule.Kind, rules: [SymbolRule]) -> [RuleItem] {
        let overrides = Dictionary(rules.filter { $0.kind == kind }.map { ($0.input, $0) }, uniquingKeysWith: { _, last in last })
        let defaults = defaults(kind)
        let defaultInputs = Set(defaults.map(\.input))
        var result = defaults.map { input, output in
            let rule = overrides[input]
            return RuleItem(id: input, key: input, value: rule?.output ?? output, isEnabled: rule?.isEnabled ?? true,
                            badge: rule == nil ? nil : UIStrings.Features.changed, removal: rule == nil ? .none : .restore, isKeyFixed: true)
        }
        for rule in rules where rule.kind == kind && !defaultInputs.contains(rule.input) {
            result.append(RuleItem(id: rule.input, key: rule.input, value: rule.output, isEnabled: rule.isEnabled, badge: UIStrings.Features.added))
        }
        return result
    }

    /// 決まりを重ねる．既定と同じに戻ったら重ねている決まりを外す．形が誤っているか上限を超えるなら false
    private static func save(_ rule: SymbolRule, replacing old: String?, in rules: inout [SymbolRule]) -> Bool {
        guard rule.isValid else { return false }
        let isNew = !rules.contains { $0.kind == rule.kind && ($0.input == rule.input || $0.input == old) }
        guard !isNew || rules.count < DefaultSettings.maximumSymbolRules else { return false }
        rules.removeAll { $0.kind == rule.kind && ($0.input == rule.input || $0.input == old) }
        let defaultOutput = defaults(rule.kind).first { $0.input == rule.input }?.output
        if rule.isEnabled, rule.output == defaultOutput { return true }
        rules.append(rule)
        return true
    }
}
