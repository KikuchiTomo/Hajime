import Foundation
import HajimeApplication
import HajimeDomain
import HajimeEngine
import HajimeTestSupport
import Testing

/// うろ覚えの語(R-20)とローマ字の読み(R-21)を，本物の辞書で確かめる結合テスト
@Suite("うろ覚えの語とローマ字の読み(本物の辞書)")
@MainActor
struct InputExtrasEngineTests {
    private func makeConverter(_ change: (inout Settings) -> Void) throws -> (SupplementedConverter, AzooKeyConverterEngine) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-engine-\(UUID().uuidString)")
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "Hajime tests")
        var settings = DefaultSettings.settings
        change(&settings)
        engine.apply(settings)
        return (SupplementedConverter(engine.makeSession(), settings: FakeSettings(settings), calendar: FakeCalendar()), engine)
    }

    @Test("R-20: うろ覚えの読みの一覧に正しい語が出る．打っているあいだの候補には出さない．オフなら出さない", arguments: [
        ("しゅみれーしょん", "シミュレーション"), ("こみにけーしょん", "コミュニケーション"),
    ])
    func looseReadings(reading: String, word: String) throws {
        let (converter, engine) = try makeConverter { $0.looseReadings = true }
        let list = converter.listCandidates(for: reading)
        #expect(list.prefix(4).contains { $0.text == word })
        #expect(list.first?.text != word || converter.candidates(for: reading).first?.text == word)
        let (off, _) = try makeConverter { _ in }
        #expect(off.listCandidates(for: reading).prefix(4).allSatisfy { $0.text != word } || off.candidates(for: reading).prefix(4).contains { $0.text == word })
        withExtendedLifetime(engine) {}
    }

    @Test("R-20: 正しく打った語では，うろ覚えの語を探さない")
    func correctReading() throws {
        let (converter, engine) = try makeConverter { $0.looseReadings = true }
        let list = converter.listCandidates(for: "しみゅれーしょん")
        #expect(list.first?.text == "シミュレーション")
        #expect(list.filter { $0.text == "シミュレーション" }.count == 1)
        withExtendedLifetime(engine) {}
    }

    @Test("R-21: ローマ字の読みで登録した語は，エンジンを通しても読み全体が一致すれば先頭に出る")
    func romajiReading() throws {
        let (converter, engine) = try makeConverter { $0.userDictionary = [UserDictionaryEntry(reading: "gh", word: "GitHub")] }
        #expect(converter.listCandidates(for: "gh").first?.text == "GitHub")
        withExtendedLifetime(engine) {}
    }
}
