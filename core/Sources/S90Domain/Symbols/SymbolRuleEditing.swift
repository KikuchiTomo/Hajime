/// 記号の決まり(SymbolRule)を設定の画面で書き換える・読み込むときの決まり．
/// 既定の決まりは変えず，変えた分だけを設定に重ねる．既定と同じに戻した決まりは重ねない
public enum SymbolRuleEditing {
    /// 一覧の 1 行．既定の決まりに利用者の決まりを重ねたもの
    public struct Item: Sendable, Equatable {
        public enum Origin: Sendable, Equatable {
            /// 既定のまま
            case standard
            /// 既定の決まりを利用者が変えた
            case changed
            /// 利用者が足した
            case added
        }

        public var input: String
        public var output: String
        public var isEnabled: Bool
        public var origin: Origin
    }

    /// 既定の決まり(入力と出力)．何度も作り直さないよう，一度だけ作る
    private static let sequenceDefaults = SymbolSequenceSet.defaultRules.map { (input: $0.input, output: $0.symbol) }
    private static let readingDefaults = SymbolDictionary.defaultEntries.map { (input: $0.reading, output: $0.symbols.joined(separator: " ")) }

    public static func defaults(_ kind: SymbolRule.Kind) -> [(input: String, output: String)] {
        kind == .sequence ? sequenceDefaults : readingDefaults
    }

    /// 既定の決まりに利用者の決まりを重ね，利用者が足した決まりを後ろに並べる
    public static func items(_ kind: SymbolRule.Kind, rules: [SymbolRule]) -> [Item] {
        let overrides = Dictionary(rules.filter { $0.kind == kind }.map { ($0.input, $0) }, uniquingKeysWith: { _, last in last })
        let defaults = defaults(kind)
        let defaultInputs = Set(defaults.map(\.input))
        var result = defaults.map { input, output in
            let rule = overrides[input]
            return Item(input: input, output: rule?.output ?? output, isEnabled: rule?.isEnabled ?? true, origin: rule == nil ? .standard : .changed)
        }
        for rule in rules where rule.kind == kind && !defaultInputs.contains(rule.input) {
            result.append(Item(input: rule.input, output: rule.output, isEnabled: rule.isEnabled, origin: .added))
        }
        return result
    }

    /// 決まりを重ねる．replacing は書き換える前の入力．既定と同じに戻ったら重ねている決まりを外す．
    /// 形が誤っているか上限を超えるなら変えずに false を返す
    @discardableResult
    public static func save(_ rule: SymbolRule, replacing old: String? = nil, in rules: inout [SymbolRule]) -> Bool {
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
