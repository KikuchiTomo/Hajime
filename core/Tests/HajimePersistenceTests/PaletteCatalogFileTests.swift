import Foundation
import HajimeDomain
@testable import HajimePersistence
import Testing

@Suite("同梱のパレットの表のファイル")
@MainActor
struct PaletteCatalogFileTests {
    /// リポジトリの data/palette/palette.tsv
    private var bundledFile: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("data/palette").appendingPathComponent(DefaultSettings.bundledPaletteFileName)
    }

    @Test("R-25: 裏で読み，OS が描けるバージョンまでの絵文字に絞る")
    func limitsToRenderableVersion() async throws {
        let catalog = PaletteCatalog(text: try String(contentsOf: bundledFile, encoding: .utf8))
        let renderable = Set(catalog.versionSamples.filter { $0.version <= EmojiVersion(major: 15, minor: 0) }.map(\.text))
        let file = PaletteCatalogFile(url: bundledFile, canRender: { renderable.contains($0) })
        #expect(file.index == nil)
        let index = try #require(await file.waitForLoad())
        #expect(index.catalog.items.allSatisfy { $0.version.map { $0 <= EmojiVersion(major: 15, minor: 0) } ?? true })
        #expect(index.catalog.items.contains { $0.version == EmojiVersion(major: 15, minor: 0) })
        #expect(index.catalog.items.contains { $0.kind == .symbol })
        #expect(file.index != nil)
    }

    @Test("R-25: 記号に，読みから引く記号の辞書の読みを足す")
    func addsSymbolReadings() async throws {
        let index = try #require(await PaletteCatalogFile(url: bundledFile, canRender: { _ in true }).waitForLoad())
        // 「ならば」は記号の辞書にだけある読み(⇒)
        #expect(index.search.search(PaletteSearch.Query(typed: "", kana: "ならば")).first?.text == "⇒")
    }

    @Test("R-25: 見本をどれも描けなければ絵文字を除かない．ファイルが無ければ表を渡さない")
    func fallbacks() async throws {
        let all = try #require(await PaletteCatalogFile(url: bundledFile, canRender: { _ in false }).waitForLoad())
        #expect(all.catalog.items.contains { $0.version == EmojiVersion(major: 17, minor: 0) })
        let missing = PaletteCatalogFile(url: bundledFile.deletingLastPathComponent().appendingPathComponent("missing.tsv"), canRender: { _ in true })
        #expect(await missing.waitForLoad() == nil)
    }
}
