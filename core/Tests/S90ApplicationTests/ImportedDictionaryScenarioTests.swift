import S90Application
import S90Domain
import S90TestSupport
import Testing

@MainActor
private final class FakeLookup: DictionaryLookup {
    var words: [String: [String: [DictionaryWord]]] = [:]
    func words(reading: String, in dictionary: ImportedDictionary) -> [DictionaryWord] { words[dictionary.id]?[reading] ?? [] }
}

@Suite("取り込んだ辞書を効かせる決まり(R-14)")
struct DictionaryActivationTests {
    private let always = ImportedDictionary(id: "a", name: "一般", wordCount: 1)
    private let law = ImportedDictionary(id: "b", name: "法律", condition: .apps(["com.microsoft.Word"]), wordCount: 1)
    private let electric = ImportedDictionary(id: "c", name: "電気", condition: .context, wordCount: 1)

    @Test("上の辞書ほど優先し，切った辞書は使わない")
    func priority() {
        var off = always
        off.isEnabled = false
        let active = DictionaryActivation.active([always, electric, off], applicationID: nil, recentHits: ["c": 5])
        #expect(active.map(\.dictionary.id) == ["a", "c"])
        #expect(active[0].costOffset > active[1].costOffset)
    }

    @Test("アプリの条件の辞書は，そのアプリでだけ使う")
    func apps() {
        #expect(DictionaryActivation.active([law], applicationID: "com.microsoft.Word", recentHits: [:]).count == 1)
        #expect(DictionaryActivation.active([law], applicationID: "com.apple.TextEdit", recentHits: [:]).isEmpty)
    }

    @Test("文脈の条件の辞書は，最近その辞書の語を確定していなければ優先度を下げる")
    func context() {
        let cold = DictionaryActivation.active([electric], applicationID: nil, recentHits: [:])[0].costOffset
        let warm = DictionaryActivation.active([electric], applicationID: nil, recentHits: ["c": DefaultSettings.importedDictionaryContextHits])[0].costOffset
        #expect(cold < warm)
    }
}

@MainActor
@Suite("取り込んだ辞書の語をエンジンに渡す(R-14)")
struct ImportedDictionaryConverterTests {
    private func make(_ dictionaries: [ImportedDictionary]) -> (SupplementedConverter, FakeConverter, FakeLookup) {
        var settings = Settings()
        settings.importedDictionaries = dictionaries
        let base = FakeConverter(["でんあつをはかる": [("電圧を測る", nil)]])
        let lookup = FakeLookup()
        let converter = SupplementedConverter(base, settings: FakeSettings(settings), calendar: FakeCalendar(), dictionaries: lookup)
        return (converter, base, lookup)
    }

    @Test("読みの中の部分ごとに辞書を引き，見つかった語を渡す")
    func passesWords() {
        let dictionary = ImportedDictionary(id: "e", name: "電気辞書", field: "電気", wordCount: 1)
        let (converter, base, lookup) = make([dictionary])
        lookup.words["e"] = ["でんあつ": [DictionaryWord(reading: "でんあつ", word: "電圧")]]
        _ = converter.candidates(for: "でんあつをはかる")
        #expect(base.auxiliaryWords.map(\.word.word) == ["電圧"])
        #expect(converter.sourceName(of: "電圧を", reading: "でんあつを") == "電気")
    }

    @Test("読み全体と一致する語は，エンジンがたどれない読みでも 2 番目に足す")
    func wholeReading() {
        let dictionary = ImportedDictionary(id: "e", name: "電気", wordCount: 1)
        let (converter, _, lookup) = make([dictionary])
        lookup.words["e"] = ["でんあつをはかる": [DictionaryWord(reading: "でんあつをはかる", word: "電圧計測")]]
        #expect(converter.candidates(for: "でんあつをはかる").map(\.text) == ["電圧を測る", "電圧計測"])
    }

    @Test("アプリの条件に合わなければ渡さない")
    func appCondition() {
        let dictionary = ImportedDictionary(id: "l", name: "法律", condition: .apps(["com.example.word"]), wordCount: 1)
        let (converter, base, lookup) = make([dictionary])
        lookup.words["l"] = ["でんあつ": [DictionaryWord(reading: "でんあつ", word: "電圧")]]
        converter.setApplication("com.apple.TextEdit")
        _ = converter.candidates(for: "でんあつをはかる")
        #expect(base.auxiliaryWords.isEmpty)
        converter.setApplication("com.example.word")
        _ = converter.candidates(for: "でんあつをはかる")
        #expect(base.auxiliaryWords.count == 1)
    }

    @Test("文脈の条件の辞書は，その辞書の語を確定するほど優先度が上がる")
    func contextCondition() {
        let dictionary = ImportedDictionary(id: "c", name: "電気", condition: .context, wordCount: 1)
        let (converter, base, lookup) = make([dictionary])
        lookup.words["c"] = ["でんあつ": [DictionaryWord(reading: "でんあつ", word: "電圧")]]
        _ = converter.candidates(for: "でんあつをはかる")
        let before = base.auxiliaryWords.first?.costOffset ?? 0
        for _ in 0..<DefaultSettings.importedDictionaryContextHits {
            converter.didCommit(Candidate(text: "電圧を測る", readingCount: 8, origin: .combined))
        }
        _ = converter.candidates(for: "でんあつをはかる")
        #expect((base.auxiliaryWords.first?.costOffset ?? 0) > before)
    }
}
