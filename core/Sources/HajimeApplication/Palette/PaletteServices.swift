import Foundation
import HajimeDomain

/// パレットの表と，表から作った検索の仕組み．synonyms はかな漢字変換の候補に足す絵文字の，同じ意味の語の一覧
public struct PaletteIndex: Sendable {
    public let catalog: PaletteCatalog
    public let search: PaletteSearch

    public init(catalog: PaletteCatalog, synonyms: EmojiSynonyms = EmojiSynonyms()) {
        self.catalog = catalog
        self.search = PaletteSearch(catalog: catalog, synonyms: synonyms)
    }
}

/// パレットの表を渡すポート．表は裏で読み込み，読み終わるまでは nil．OS が描けない絵文字は除いて渡す
@MainActor
public protocol PaletteCatalogProviding: AnyObject {
    var index: PaletteIndex? { get }
}

/// パレットに使うもの(R-26)．パレットを描けるアプリだけが組み立てて InputSession に渡す．
/// 渡さなければパレットのキーは何もしない(キーを奪って何も見せない，ということを起こさない)
@MainActor
public final class PaletteServices {
    let catalog: any PaletteCatalogProviding
    let usage: any PaletteUsageStoring
    let now: () -> Date

    public init(catalog: any PaletteCatalogProviding, usage: any PaletteUsageStoring, now: @escaping () -> Date) {
        self.catalog = catalog
        self.usage = usage
        self.now = now
    }
}
