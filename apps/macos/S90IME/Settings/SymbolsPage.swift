import S90Domain
import S90Persistence
import SwiftUI

/// 記号の決まり(項目 47)．既定の決まりを一覧にし，書き換え・無効化・追加・既定に戻すができる．
/// 既定の決まりは変えず，変えた分だけを設定に重ねるので，バージョンが上がって既定が増えても変更は残る
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
                    return model.editRules(failure: UIStrings.RuleList.full) { SymbolRuleEditing.save(rule, replacing: editing?.key, in: &$0.symbolRules) }
                },
                remove: { items in
                    let inputs = Set(items.map(\.key))
                    model.update { $0.symbolRules.removeAll { $0.kind == kind && inputs.contains($0.input) } }
                },
                setEnabled: { item, isEnabled in
                    let rule = SymbolRule(kind: kind, input: item.key, output: item.value, isEnabled: isEnabled)
                    model.update { _ = SymbolRuleEditing.save(rule, in: &$0.symbolRules) }
                },
                importFile: { model.importRuleList(isSequence ? .symbolSequences : .symbolReadings) },
                exportFile: { model.exportRuleList(isSequence ? .symbolSequences : .symbolReadings) },
                tableHeight: isSequence ? DesignTokens.Size.Settings.ruleTableHeight : DesignTokens.Size.Settings.userDictionaryTableHeight
            )
        }
    }

    /// 一覧の行．既定の決まりに利用者の決まりを重ね，利用者が足した決まりを後ろに並べる
    private static func items(_ kind: SymbolRule.Kind, rules: [SymbolRule]) -> [RuleItem] {
        SymbolRuleEditing.items(kind, rules: rules).map { item in
            switch item.origin {
            case .standard:
                RuleItem(id: item.input, key: item.input, value: item.output, isEnabled: item.isEnabled, badge: nil, removal: .none, isKeyFixed: true)
            case .changed:
                RuleItem(id: item.input, key: item.input, value: item.output, isEnabled: item.isEnabled, badge: UIStrings.Features.changed,
                         removal: .restore, isKeyFixed: true)
            case .added:
                RuleItem(id: item.input, key: item.input, value: item.output, isEnabled: item.isEnabled, badge: UIStrings.Features.added)
            }
        }
    }
}
