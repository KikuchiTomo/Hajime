import Foundation
import HajimeDomain
import Testing

@Suite("専門用語の辞書の分野の設定(R-29)")
struct TermFieldSettingsTests {
    @Test("既定はすべての分野を使い，分野ごとに切れる")
    func defaults() {
        var fields = TermFieldSettings()
        #expect(fields.enabledFields == Set(TermField.allCases))
        fields[.medicine] = false
        #expect(!fields.medicine)
        #expect(fields.enabledFields == Set(TermField.allCases).subtracting([.medicine]))
    }

    @Test("設定のファイルに無い分野(あとから足した分野)は使う")
    func missingFieldsAreEnabled() throws {
        let fields = try JSONDecoder().decode(TermFieldSettings.self, from: Data(#"{"law": false, "unknown": false}"#.utf8))
        #expect(fields.enabledFields == Set(TermField.allCases).subtracting([.law]))
    }

    @Test("書いて読むと同じになり，項目の名前は分野の id")
    func roundTrip() throws {
        var fields = TermFieldSettings()
        fields[.performingArts] = false
        let data = try JSONEncoder().encode(fields)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Bool])
        #expect(Set(object.keys) == Set(TermField.allCases.map(\.rawValue)))
        #expect(object["performingArts"] == false)
        #expect(try JSONDecoder().decode(TermFieldSettings.self, from: data) == fields)
    }

    @Test("専門用語の辞書の項目の無い古い設定は，専門用語の辞書をすべての分野で使う")
    func oldSettings() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        #expect(settings.termDictionary)
        #expect(settings.termFields == TermFieldSettings())
    }

    @Test("分野の名前は空でなく，重ならない")
    func names() {
        let names = TermField.allCases.map(\.name)
        #expect(!names.contains(""))
        #expect(Set(names).count == names.count)
    }
}
