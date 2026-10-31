import Foundation
import HajimeApplication
import HajimeDomain

/// アプリに同梱した同音異義語の使い分けの辞書(data/usage/usage_dict.txt と usage_dict_extra.tsv)を読む(R-08)．
/// 複数のファイルは続けて 1 つの辞書として読む．読めないファイルは飛ばす．
/// 初めて使うときに読み込む(注釈を出さない人には読み込む手間をかけない)．通信しない
@MainActor
public final class UsageDictionaryFile: UsageDictionaryProviding {
    /// 1 つのファイルの大きさの上限．同梱の辞書は 220KB と数 MB ほど．壊れた大きなファイルを読み込まないため
    static let maximumBytes = 8 * 1024 * 1024

    private let urls: [URL]
    private var loaded: UsageDictionary??

    public convenience init(url: URL) {
        self.init(urls: [url])
    }

    public init(urls: [URL]) {
        self.urls = urls
    }

    public var usageDictionary: UsageDictionary? {
        if let loaded { return loaded }
        let dictionary = Self.load(urls)
        loaded = .some(dictionary)
        return dictionary
    }

    private static func load(_ urls: [URL]) -> UsageDictionary? {
        let texts = urls.compactMap(read)
        guard !texts.isEmpty else { return nil }
        let dictionary = UsageDictionary(text: texts.joined(separator: "\n"))
        return dictionary.isEmpty ? nil : dictionary
    }

    private static func read(_ url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? Int, size <= maximumBytes,
            let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
