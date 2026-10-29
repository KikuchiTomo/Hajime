/// 設定の画面で決まりの一覧(補正の置き換え・直さない語・ローマ字)を足す・書き換える・読み込むときの決まり．
/// 一覧の中で左(打った英字・入力)は重ならない．同じ左の決まりを足すと上書きする
public enum RuleListEditing {
    /// 決まりを足すか書き換える．replacing は書き換える前の左(新しく足すときは nil)．
    /// 書き換えた決まりは元の位置に置き，新しい決まりは末尾に足す．形が誤っているか上限を超えるなら変えずに false を返す
    @discardableResult
    public static func upsert<Rule>(_ rule: Rule, key: (Rule) -> String, isValid: (Rule) -> Bool, limit: Int,
                                    replacing oldKey: String? = nil, in rules: inout [Rule]) -> Bool {
        guard isValid(rule) else { return false }
        let newKey = key(rule)
        let position = rules.firstIndex { key($0) == oldKey } ?? rules.firstIndex { key($0) == newKey }
        let remaining = rules.filter { key($0) != newKey && (oldKey == nil || key($0) != oldKey) }
        guard position != nil || remaining.count < limit else { return false }
        rules = remaining
        if let position {
            rules.insert(rule, at: min(position, rules.count))
        } else {
            rules.append(rule)
        }
        return true
    }

    /// 読み込んだ決まりを足す．形の誤った決まりと上限を超えた決まりは足さない．足した(上書きを含む)数を返す
    public static func merge<Rule>(_ imported: [Rule], key: (Rule) -> String, isValid: (Rule) -> Bool, limit: Int, into rules: inout [Rule]) -> Int {
        imported.reduce(0) { count, rule in
            upsert(rule, key: key, isValid: isValid, limit: limit, in: &rules) ? count + 1 : count
        }
    }

    /// 置き換えの決まりの形をそろえる(打った英字は小文字で照らし合わせる)
    public static func correctionRule(typed: String, word: String) -> CorrectionRule {
        CorrectionRule(typed: typed.trimmed.lowercased(), word: word.trimmed)
    }

    public static func romajiRule(keys: String, kana: String) -> RomajiRule {
        RomajiRule(keys: keys.trimmed.lowercased(), kana: kana.trimmed)
    }

    /// 直さない語は空でなく 64 文字まで
    public static func isValidException(_ word: String) -> Bool {
        !word.isEmpty && word.count <= DefaultSettings.maximumExceptionLength
    }
}
