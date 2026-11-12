import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

@MainActor
private final class FakeTermLookup: TermDictionaryLookup {
    var words: [String: [TermWord]] = [:]
    func words(reading: String) -> [TermWord] { words[reading] ?? [] }
}

@MainActor
private final class FakeLookup: DictionaryLookup {
    var words: [String: [String: [DictionaryWord]]] = [:]
    func words(reading: String, in dictionary: ImportedDictionary) -> [DictionaryWord] { words[dictionary.id]?[reading] ?? [] }
}

@MainActor
@Suite("専門用語の辞書の語をエンジンに渡す(R-29)")
struct TermDictionaryConverterTests {
    /// 分野ごとに 1 語を持つ専門用語の辞書．読みは「ぶんや」に分野ごとに違うかなを 1 つ付けたもの(ほかの分野の読みを中に含まない)
    private static func reading(of field: TermField) -> String {
        "ぶんや" + String(Array("あいうえおかきくけこさしすせそたちつてとなにぬねの")[TermField.allCases.firstIndex(of: field)!])
    }

    private static func word(of field: TermField) -> String { "専門語\(field.rawValue)" }

    private func make(_ settings: Settings, imported: [ImportedDictionary] = []) -> (SupplementedConverter, FakeConverter, FakeTermLookup, FakeLookup) {
        var settings = settings
        settings.importedDictionaries = imported
        let base = FakeConverter(["かでんあつをけんしゅつ": [("過電圧を検出", nil)]])
        let terms = FakeTermLookup()
        for field in TermField.allCases {
            terms.words[Self.reading(of: field)] = [TermWord(word: DictionaryWord(reading: Self.reading(of: field), word: Self.word(of: field)), field: field)]
        }
        let lookup = FakeLookup()
        let converter = SupplementedConverter(base, settings: FakeSettings(settings), calendar: FakeCalendar(), dictionaries: lookup, terms: terms)
        return (converter, base, terms, lookup)
    }

    @Test("読みの中の部分ごとに引き，見つかった語を取り込んだ辞書の語より低い点数で渡す．分岐図には分野の名前を出す")
    func passesWords() {
        let (converter, base, terms, _) = make(Settings())
        terms.words["かでんあつ"] = [TermWord(word: DictionaryWord(reading: "かでんあつ", word: "過電圧"), field: .engineering)]
        _ = converter.candidates(for: "かでんあつをけんしゅつ")
        #expect(base.auxiliaryWords.map(\.word.word) == ["過電圧"])
        #expect(base.auxiliaryWords[0].costOffset == DefaultSettings.termWordCost - DefaultSettings.importedWordCost)
        #expect(base.auxiliaryWords[0].costOffset < 0)
        #expect(converter.sourceName(of: "過電圧を", reading: "かでんあつを") == TermField.engineering.name)
    }

    @Test("通常の辞書に同じ読みの語がある語は，さらに低い点数で渡し，読み全体と一致しても前に差し込まない")
    func homophones() {
        let (converter, base, terms, _) = make(Settings())
        terms.words["しかん"] = [TermWord(word: DictionaryWord(reading: "しかん", word: "篩管"), field: .biology, hasHomophones: true)]
        base.table["しかん"] = [("士官", nil), ("弛緩", nil)]
        #expect(converter.candidates(for: "しかん").map(\.text) == ["士官", "弛緩"])
        #expect(base.auxiliaryWords.map(\.costOffset) == [DefaultSettings.termHomophoneWordCost - DefaultSettings.importedWordCost])
        #expect(DefaultSettings.termHomophoneWordCost < DefaultSettings.termWordCost)
    }

    @Test("専門用語の辞書を切ると，どの分野の語も渡さない")
    func disabled() {
        var settings = Settings()
        settings.termDictionary = false
        let (converter, base, _, _) = make(settings)
        for field in TermField.allCases {
            _ = converter.candidates(for: Self.reading(of: field))
            #expect(base.auxiliaryWords.isEmpty)
        }
    }

    /// 分野ごとに切る設定．設定の項目(termFields.<id>)ごとに，切った分野の語だけが消えることを確かめる
    nonisolated private static let switches: [(TermField, @Sendable (inout Settings) -> Void)] = [
        (.computing, { $0.termFields.computing = false }),
        (.medicine, { $0.termFields.medicine = false }),
        (.biology, { $0.termFields.biology = false }),
        (.chemistry, { $0.termFields.chemistry = false }),
        (.physics, { $0.termFields.physics = false }),
        (.mathematics, { $0.termFields.mathematics = false }),
        (.earth, { $0.termFields.earth = false }),
        (.engineering, { $0.termFields.engineering = false }),
        (.architecture, { $0.termFields.architecture = false }),
        (.law, { $0.termFields.law = false }),
        (.economics, { $0.termFields.economics = false }),
        (.business, { $0.termFields.business = false }),
        (.linguistics, { $0.termFields.linguistics = false }),
        (.philosophy, { $0.termFields.philosophy = false }),
        (.religion, { $0.termFields.religion = false }),
        (.music, { $0.termFields.music = false }),
        (.design, { $0.termFields.design = false }),
        (.food, { $0.termFields.food = false }),
        (.sports, { $0.termFields.sports = false }),
        (.games, { $0.termFields.games = false }),
        (.military, { $0.termFields.military = false }),
        (.agriculture, { $0.termFields.agriculture = false }),
        (.performingArts, { $0.termFields.performingArts = false }),
        (.history, { $0.termFields.history = false }),
    ]

    @Test("すべての分野に，切る設定がある")
    func everyFieldHasSwitch() {
        #expect(Self.switches.map(\.0) == TermField.allCases)
    }

    @Test("分野を切ると，その分野の語だけを渡さない", arguments: switches.indices)
    func fieldSwitch(index: Int) {
        let (field, turnOff) = Self.switches[index]
        var settings = Settings()
        turnOff(&settings)
        #expect(!settings.termFields[field])
        let (converter, base, _, _) = make(settings)
        for other in TermField.allCases {
            _ = converter.candidates(for: Self.reading(of: other))
            #expect(base.auxiliaryWords.map(\.word.word) == (other == field ? [] : [Self.word(of: other)]), "\(other)")
        }
    }

    @Test("設定を変えると，同じ読みでも引き直す")
    func settingsChange() {
        let settings = FakeSettings(Settings())
        let base = FakeConverter([:])
        let terms = FakeTermLookup()
        terms.words["かでんあつ"] = [TermWord(word: DictionaryWord(reading: "かでんあつ", word: "過電圧"), field: .engineering)]
        let converter = SupplementedConverter(base, settings: settings, calendar: FakeCalendar(), terms: terms)
        _ = converter.candidates(for: "かでんあつ")
        #expect(base.auxiliaryWords.count == 1)
        try? settings.update { $0.termFields.engineering = false }
        _ = converter.candidates(for: "かでんあつ")
        #expect(base.auxiliaryWords.isEmpty)
    }

    @Test("同じ語が取り込んだ辞書にもあれば，取り込んだ辞書の点数と名前を使う")
    func importedWins() {
        let dictionary = ImportedDictionary(id: "e", name: "電気", wordCount: 1)
        let (converter, base, terms, lookup) = make(Settings(), imported: [dictionary])
        let word = DictionaryWord(reading: "かでんあつ", word: "過電圧")
        terms.words["かでんあつ"] = [TermWord(word: word, field: .engineering)]
        lookup.words["e"] = ["かでんあつ": [word]]
        _ = converter.candidates(for: "かでんあつをけんしゅつ")
        #expect(base.auxiliaryWords == [AuxiliaryWord(word: word, costOffset: 0)])
        #expect(converter.sourceName(of: "過電圧", reading: "かでんあつ") == "電気")
    }

    @Test("読み全体と一致する語は，取り込んだ辞書の語より下に足す")
    func wholeReading() {
        let dictionary = ImportedDictionary(id: "e", name: "電気", wordCount: 1)
        let (converter, _, terms, lookup) = make(Settings(), imported: [dictionary])
        terms.words["かでんあつをけんしゅつ"] = [TermWord(word: DictionaryWord(reading: "かでんあつをけんしゅつ", word: "過電圧検出"), field: .engineering)]
        lookup.words["e"] = ["かでんあつをけんしゅつ": [DictionaryWord(reading: "かでんあつをけんしゅつ", word: "過電圧ヲ検出")]]
        #expect(converter.candidates(for: "かでんあつをけんしゅつ").map(\.text) == ["過電圧を検出", "過電圧ヲ検出", "過電圧検出"])
    }
}
