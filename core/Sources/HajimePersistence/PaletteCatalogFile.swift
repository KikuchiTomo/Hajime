import Foundation
import HajimeApplication
import HajimeDomain

/// アプリに同梱した絵文字と記号のパレットの表(data/palette/palette.tsv)を裏で読む(R-26)．通信しない．
///
/// 読むときに次のことをする．どれも数十ミリ秒かかるので，打鍵を止めないよう裏で行い，読み終わるまでは表が無いものとして扱う
/// - OS が描けない新しい絵文字を除く．バージョンごとの見本の絵文字を canRender で描けるか確かめ，描ける最も新しいバージョンまでを使う
/// - 記号に，読みから引く記号の辞書(SymbolDictionary)の読みを足す(変換で出る記号はパレットでも同じ読みで探せるように)
/// - 検索の仕組み(PaletteSearch)を作る
@MainActor
public final class PaletteCatalogFile: PaletteCatalogProviding {
    /// OS が描ける絵文字の決め方
    enum Limit: Sendable {
        /// 見本の絵文字を描けるか確かめる(macOS．アプリが OS の書体で確かめる)
        case probe(@Sendable (String) -> Bool)
        /// このバージョンまでを出す(Windows のエンジンのプロセス．書体を確かめられない)
        case upTo(EmojiVersion)
    }

    private let url: URL
    private let limit: Limit
    private var loaded: PaletteIndex??
    private var loading: Task<PaletteIndex?, Never>?

    /// - Parameter canRender: OS がその絵文字を 1 つの字として描けるか．アプリが OS の書体で確かめる
    public init(url: URL, canRender: @escaping @Sendable (String) -> Bool) {
        self.url = url
        self.limit = .probe(canRender)
    }

    /// 書体を確かめられないところ(Windows のエンジンのプロセス)で使う．maximumVersion までの絵文字を出す
    public init(url: URL, maximumVersion: EmojiVersion) {
        self.url = url
        self.limit = .upTo(maximumVersion)
    }

    /// 読み終わった表．まだなら裏で読み始めて nil を返す
    public var index: PaletteIndex? {
        if let loaded { return loaded }
        preload()
        return nil
    }

    /// 表を裏で読み始める
    public func preload() {
        guard loaded == nil, loading == nil else { return }
        let url = url
        let limit = limit
        let task = Task.detached(priority: .utility) { Self.load(url, limit: limit) }
        loading = task
        Task { [weak self] in
            let index = await task.value
            self?.loaded = .some(index)
        }
    }

    /// 読み終わるまで待って表を返す(テストのため)
    public func waitForLoad() async -> PaletteIndex? {
        if let loaded { return loaded }
        preload()
        let index = await loading?.value ?? nil
        loaded = .some(index)
        return index
    }

    nonisolated private static func read(_ url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int, size <= DefaultSettings.maximumPaletteFileBytes,
              let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    nonisolated static func load(_ url: URL, limit: Limit) -> PaletteIndex? {
        guard let text = read(url) else { return nil }
        var catalog = PaletteCatalog(text: text)
        guard !catalog.items.isEmpty else { return nil }
        switch limit {
        case .probe(let canRender):
            if let version = newestRenderableVersion(of: catalog, canRender: canRender) { catalog = catalog.limited(to: version) }
        case .upTo(let version):
            catalog = catalog.limited(to: version)
        }
        catalog = catalog.addingReadings(SymbolDictionary.defaultEntries)
        return PaletteIndex(catalog: catalog)
    }

    /// OS が描ける最も新しい絵文字のバージョン．新しいものから見本を確かめる．どれも描けなければ nil(絵文字を除かない．書体を確かめられない作りでも動くように)
    nonisolated public static func newestRenderableVersion(of catalog: PaletteCatalog, canRender: (String) -> Bool) -> EmojiVersion? {
        catalog.versionSamples.reversed().first { canRender($0.text) }?.version
    }
}
