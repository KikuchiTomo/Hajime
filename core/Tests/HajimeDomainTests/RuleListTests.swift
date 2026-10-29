import HajimeDomain
import Testing

@Suite("決まりの一覧の書き出しと読み込み")
struct RuleListTests {
    private func rows(_ pairs: [(String, String)]) -> [RuleListRow] {
        pairs.map { RuleListRow(key: $0.0, value: $0.1) }
    }

    @Test("補正の置き換え: 打った英字を小文字にそろえ，形の誤った行は足さず，同じ英字は上書きする")
    func correctionRules() {
        var settings = Settings()
        settings.correction.rules = [CorrectionRule(typed: "teh", word: "the")]
        let added = RuleList.correctionRules.merge(rows([("TEH", "THE"), ("a1", "x"), ("adn", "and")]), into: &settings)
        #expect(added == 2)
        #expect(settings.correction.rules == [CorrectionRule(typed: "teh", word: "THE"), CorrectionRule(typed: "adn", word: "and")])
        #expect(RuleList.correctionRules.rows(in: settings) == rows([("teh", "THE"), ("adn", "and")]))
    }

    @Test("直さない語句・いつも英語・いつも日本語は 1 列．英語と日本語の語は小文字にそろえる")
    func singleColumn() {
        var settings = Settings()
        #expect(RuleList.exceptions.merge(rows([("GitHub", ""), ("", "")]), into: &settings) == 1)
        #expect(RuleList.englishWords.merge(rows([("Swift", ""), ("日本", "")]), into: &settings) == 1)
        #expect(RuleList.japaneseWords.merge(rows([("Kaisha", "")]), into: &settings) == 1)
        #expect(settings.correction.exceptions.contains("GitHub"))
        #expect(settings.wordLanguage.englishWords.contains("swift"))
        #expect(settings.wordLanguage.japaneseWords.contains("kaisha"))
        #expect(RuleList.englishWords.rows(in: settings).contains(RuleListRow(key: "swift", value: "")))
    }

    @Test("ローマ字の綴り")
    func romaji() {
        var settings = Settings()
        #expect(RuleList.romaji.merge(rows([("XKA", "ヵ")]), into: &settings) == 1)
        #expect(RuleList.romaji.rows(in: settings).contains(RuleListRow(key: "xka", value: "ヵ")))
    }

    @Test("記号: 既定と同じ決まりは重ねず，書き出しは既定に利用者の決まりを重ねた有効な行")
    func symbols() {
        var settings = Settings()
        let added = RuleList.symbolSequences.merge(rows([("->", "→"), ("<-", "⇦"), ("~>", "⤳"), ("ab", "x")]), into: &settings)
        #expect(added == 3)
        #expect(settings.symbolRules == [SymbolRule(kind: .sequence, input: "<-", output: "⇦"), SymbolRule(kind: .sequence, input: "~>", output: "⤳")])
        let exported = RuleList.symbolSequences.rows(in: settings)
        #expect(exported.first == RuleListRow(key: "->", value: "→"))
        #expect(exported.contains(RuleListRow(key: "<-", value: "⇦")))
        #expect(exported.last == RuleListRow(key: "~>", value: "⤳"))
        #expect(RuleList.symbolReadings.rows(in: settings).contains { $0.key == "やじるし" })
    }

    @Test("無効にした記号は書き出さない")
    func disabledSymbolsAreNotExported() {
        var settings = Settings()
        SymbolRuleEditing.save(SymbolRule(kind: .sequence, input: "->", output: "→", isEnabled: false), in: &settings.symbolRules)
        #expect(!RuleList.symbolSequences.rows(in: settings).contains { $0.key == "->" })
        #expect(SymbolRuleEditing.items(.sequence, rules: settings.symbolRules).first?.origin == .changed)
    }

    @Test("アプリの扱いの規則は先頭に足し，同じアプリの規則は置き換える")
    func profileRules() {
        var settings = Settings()
        settings.profileRules = [ProfileRule(applicationPrefix: "a.exe", profile: .terminal), ProfileRule(applicationPrefix: "b.exe", profile: .direct)]
        ProfileRuleCSV.merge([ProfileRule(applicationPrefix: "b.exe", profile: .programming), ProfileRule(applicationPrefix: "c.exe", profile: .standard)],
                             into: &settings)
        #expect(settings.profileRules.map(\.applicationPrefix) == ["b.exe", "c.exe", "a.exe"])
        #expect(settings.profileRules.first?.profile == .programming)
    }

    @Test("取り込んだ辞書を一覧に書く: 新しい辞書は末尾に，取り込み直した辞書は語の数とバージョンだけを変える")
    func recordImportedDictionary() {
        let id = "6F1C2B0A-3D4E-4F50-8A9B-0C1D2E3F4A5B"
        var list = [ImportedDictionary(id: id, name: "電気", field: "電気", wordCount: 1)]
        var reimported = ImportedDictionary(id: id, name: "別の名前", wordCount: 5, revision: String(repeating: "a", count: 64))
        #expect(ImportedDictionary.record(reimported, isNew: false, in: &list))
        #expect(list.first?.name == "電気")
        #expect(list.first?.wordCount == 5)
        #expect(list.first?.revision == reimported.revision)
        reimported.id = "7F1C2B0A-3D4E-4F50-8A9B-0C1D2E3F4A5B"
        #expect(!ImportedDictionary.record(reimported, isNew: false, in: &list))
        #expect(ImportedDictionary.record(reimported, isNew: true, in: &list))
        #expect(list.count == 2)
    }
}
