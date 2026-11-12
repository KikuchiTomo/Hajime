import Foundation
import HajimeApplication
import HajimeDomain
import HajimeEngine
import HajimePersistence
import HajimeTestSupport
import Testing

/// Zenzai のモデルの場所(手のずれの直しを確かめるときに要る．make test-zenzai)
private let zenzaiPath = ProcessInfo.processInfo.environment["HAJIME_ZENZAI_MODEL"]
/// 同梱の辞書の場所．あればアプリと同じ辞書で確かめ，無ければ azooKey の辞書で確かめる(make test-zenzai は同梱の辞書で動かす)
private let bundledDictionaryPath = ProcessInfo.processInfo.environment["HAJIME_BUNDLED_DICTIONARY"]

/// 設定の画面で項目名の横に出す候補の見本(DefaultSettings の …Example)が，本物のエンジンで実際に出る候補と同じかを確かめる．
/// 見本が機能の動きとずれないようにするため．英単語の見分けは，アプリの綴りの辞書の代わりに見本の語を知っている FakeLexicon を使う
@Suite("設定の見本の候補(本物の辞書)")
@MainActor
struct SettingsExampleTests {
    /// リポジトリの頭(data/ の表を読む)
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    private struct Setup {
        let engine: AzooKeyConverterEngine
        let converter: SupplementedConverter
        let settings: FakeSettings
        let lexicon: FakeLexicon
    }

    private func setup(words: [String] = [], _ change: (inout Settings) -> Void = { _ in }) async throws -> Setup {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-examples-\(UUID().uuidString)")
        // Zenzai のモデルがあれば，アプリと同じく Zenzai でも変換する(手のずれの直しは Zenzai の訂正を使う)
        let zenzai = try zenzaiPath.map { try ZenzaiModel.verified(at: URL(fileURLWithPath: $0)) }
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "Hajime tests", zenzai: zenzai,
                                                dictionaryDirectory: bundledDictionaryPath.map { URL(fileURLWithPath: $0) })
        var current = DefaultSettings.settings
        change(&current)
        engine.apply(current)
        let settings = FakeSettings(current)
        let lexicon = FakeLexicon(words: Set(words))
        let catalog = PaletteCatalogFile(url: Self.root.appendingPathComponent("data/palette/palette.tsv"), canRender: { _ in true })
        // 表は裏で読むので，読み終わるまで待つ(アプリは起動のときに読み始めておく)
        _ = await catalog.waitForLoad()
        let emoji = PaletteEmojiLookup(catalog: catalog, usage: FakePaletteUsageStore(), settings: settings, now: Date.init)
        let terms = EnglishTerms(bundled: EnglishTermFile(url: Self.root.appendingPathComponent("data/english/\(DefaultSettings.bundledEnglishTermFileName)")),
                                 settings: settings)
        let converter = SupplementedConverter(engine.makeSession(), settings: settings, calendar: FakeCalendar(), emoji: emoji, lexicon: lexicon,
                                              englishTerms: terms)
        return Setup(engine: engine, converter: converter, settings: settings, lexicon: lexicon)
    }

    /// Space で変換したときの一覧の 1 ページ目
    private func firstPage(_ setup: Setup, reading: String) -> [String] {
        Array(setup.converter.listCandidates(for: reading).prefix(DefaultSettings.settings.listCandidatesPerPage).map(\.text))
    }

    /// キーを打って Space で変換し，Enter で確定した文字
    private func committed(_ setup: Setup, keys: String) -> String {
        let session = InputSession(converter: setup.converter, lexicon: setup.lexicon, settings: setup.settings)
        var committed = ""
        for key in keys {
            for case .commit(let text) in session.handle(KeyEvent(.character(key)), context: InputContext()).actions { committed += text }
        }
        for key in [KeyEvent.Key.space, .enter] {
            for case .commit(let text) in session.handle(KeyEvent(key), context: InputContext()).actions { committed += text }
        }
        return committed
    }

    @Test("文節を絵文字に変換: 「びーる」を変換すると候補に 🍺 が出る")
    func emojiConversion() async throws {
        let example = DefaultSettings.emojiConversionExample
        let setup = try await setup { $0.emojiWordConversion = false }
        #expect(firstPage(setup, reading: example.reading).contains(example.candidate))
        withExtendedLifetime(setup.engine) {}
    }

    @Test("語を絵文字に変換: 「ねこが」を変換すると候補に 🐈が が出る")
    func emojiWordConversion() async throws {
        let example = DefaultSettings.emojiWordConversionExample
        let setup = try await setup { $0.emojiConversion = false }
        #expect(firstPage(setup, reading: example.reading).contains(example.candidate))
        withExtendedLifetime(setup.engine) {}
    }

    @Test("うろ覚えのカタカナ語の候補: 「しゃんぶー」を変換すると候補に「シャンプー」が出る．オフなら一覧のどこにも出ない")
    func looseReadings() async throws {
        let example = DefaultSettings.looseReadingsExample
        let on = try await setup { $0.looseReadings = true }
        #expect(firstPage(on, reading: example.reading).contains(example.candidate))
        let off = try await setup { $0.looseReadings = false }
        #expect(!off.converter.listCandidates(for: example.reading).contains { $0.text == example.candidate })
        withExtendedLifetime((on.engine, off.engine)) {}
    }

    @Test("発音どおりに綴った英単語の候補: 「ここあ」を変換すると候補に「cocoa」が出る．オフなら一覧のどこにも出ない")
    func phoneticSpelling() async throws {
        let example = DefaultSettings.phoneticSpellingExample
        let on = try await setup(words: [example.candidate]) { $0.phoneticSpelling = true }
        #expect(firstPage(on, reading: example.reading).contains(example.candidate))
        let off = try await setup(words: [example.candidate]) { $0.phoneticSpelling = false }
        #expect(!off.converter.listCandidates(for: example.reading).contains { $0.text == example.candidate })
        withExtendedLifetime((on.engine, off.engine)) {}
    }

    @Test("手の位置のずれを修正: 両手が 1 キー右にずれたまま打った「stohsypi」を変換して確定すると「ありがとう」になる．オフならならない",
          .enabled(if: zenzaiPath != nil))
    func handShift() async throws {
        let example = DefaultSettings.handShiftExample
        let on = try await setup { $0.handShiftCorrection = true }
        #expect(committed(on, keys: example.reading) == example.candidate)
        let off = try await setup { $0.handShiftCorrection = false }
        #expect(committed(off, keys: example.reading) != example.candidate)
        withExtendedLifetime((on.engine, off.engine)) {}
    }

    @Test("前の単語で判別: 「試合に」のあとの「make」は日本語にする(設定の画面の「試す」と同じ見分け方)")
    func usesContext() async throws {
        let example = DefaultSettings.usesContextExample
        let setup = try await setup(words: ["make"]) { $0.wordLanguage.usesContext = true }
        let preceding = "試合に"
        #expect(example.reading.hasPrefix(preceding) && example.candidate.hasPrefix(preceding))
        let typed = String(example.reading.dropFirst(preceding.count)).trimmingCharacters(in: .whitespaces)
        let preview = WordLanguagePreview(converter: setup.converter, lexicon: setup.lexicon, settings: setup.settings)
        #expect(preview.preview(typed, precedingText: preceding).map(\.shown) == [String(example.candidate.dropFirst(preceding.count))])
        withExtendedLifetime(setup.engine) {}
    }

    @Test("英語の語の辞書を使う: 「api」と打って変換すると，同梱の英語の語の辞書の「API」が候補の先頭に出る")
    func englishTermCandidates() async throws {
        let example = DefaultSettings.englishTermCandidatesExample
        let setup = try await setup { $0.englishTermCandidates = true }
        #expect(committed(setup, keys: example.reading) == example.candidate)
        withExtendedLifetime(setup.engine) {}
    }
}
