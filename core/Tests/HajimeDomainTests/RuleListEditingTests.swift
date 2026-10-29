import HajimeDomain
import Testing

@Suite("決まりの一覧の編集")
struct RuleListEditingTests {
    private func upsert(_ rule: CorrectionRule, replacing old: String? = nil, limit: Int = 10, in rules: inout [CorrectionRule]) -> Bool {
        RuleListEditing.upsert(rule, key: \.typed, isValid: \.isValid, limit: limit, replacing: old, in: &rules)
    }

    @Test("新しい決まりは末尾に足し，同じ打った英字の決まりは元の位置で上書きする")
    func addAndOverwrite() {
        var rules = [CorrectionRule(typed: "teh", word: "the"), CorrectionRule(typed: "adn", word: "and")]
        #expect(upsert(CorrectionRule(typed: "recieve", word: "receive"), in: &rules))
        #expect(upsert(CorrectionRule(typed: "teh", word: "THE"), in: &rules))
        #expect(rules.map(\.word) == ["THE", "and", "receive"])
    }

    @Test("書き換えで左を変えると，元の決まりの位置に置き，変えた先と重なる決まりは消す")
    func renameKey() {
        var rules = [CorrectionRule(typed: "teh", word: "the"), CorrectionRule(typed: "adn", word: "and"), CorrectionRule(typed: "hte", word: "the")]
        #expect(upsert(CorrectionRule(typed: "hte", word: "the!"), replacing: "teh", in: &rules))
        #expect(rules == [CorrectionRule(typed: "hte", word: "the!"), CorrectionRule(typed: "adn", word: "and")])
    }

    @Test("形の誤った決まりと上限を超える決まりは足さない．上書きは上限に数えない")
    func rejects() {
        var rules = [CorrectionRule(typed: "teh", word: "the")]
        #expect(!upsert(CorrectionRule(typed: "a1", word: "x"), in: &rules))
        #expect(!upsert(CorrectionRule(typed: "adn", word: "and"), limit: 1, in: &rules))
        #expect(upsert(CorrectionRule(typed: "teh", word: "THE"), limit: 1, in: &rules))
        #expect(rules == [CorrectionRule(typed: "teh", word: "THE")])
    }

    @Test("読み込んだ決まりは形の合うものだけを足し，足した数を返す")
    func merge() {
        var rules: [RomajiRule] = []
        let imported = [RuleListEditing.romajiRule(keys: " WYI ", kana: "ゐ"), RomajiRule(keys: "toolong", kana: "x"), RomajiRule(keys: "wye", kana: "ゑ")]
        let added = RuleListEditing.merge(imported, key: \.keys, isValid: \.isValid, limit: DefaultSettings.maximumRomajiRules, into: &rules)
        #expect(added == 2)
        #expect(rules == [RomajiRule(keys: "wyi", kana: "ゐ"), RomajiRule(keys: "wye", kana: "ゑ")])
    }

    @Test("打った英字は小文字にそろえ，前後の空白を除く")
    func normalizes() {
        #expect(RuleListEditing.correctionRule(typed: " Teh ", word: " the ") == CorrectionRule(typed: "teh", word: "the"))
        #expect(RuleListEditing.isValidException("python"))
        #expect(!RuleListEditing.isValidException(""))
        #expect(!RuleListEditing.isValidException(String(repeating: "a", count: DefaultSettings.maximumExceptionLength + 1)))
    }
}
