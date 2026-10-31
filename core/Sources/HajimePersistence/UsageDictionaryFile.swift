import Foundation
import HajimeApplication
import HajimeDomain

/// アプリに同梱した同音異義語の使い分けの辞書(data/usage/usage_dict.txt)を読む(R-08)．
/// 初めて使うときに読み込む(注釈を出さない人には読み込む手間をかけない)．通信しない
@MainActor
public final class UsageDictionaryFile: UsageDictionaryProviding {
    /// 辞書の大きさの上限．同梱の辞書は 220KB ほど．壊れた大きなファイルを読み込まないため
    static let maximumBytes = 8 * 1024 * 1024

    private let url: URL
    private var loaded: UsageDictionary??

    public init(url: URL) {
        self.url = url
    }

    public var usageDictionary: UsageDictionary? {
        if let loaded { return loaded }
        let dictionary = Self.load(url)
        loaded = .some(dictionary)
        return dictionary
    }

    private static func load(_ url: URL) -> UsageDictionary? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? Int, size <= maximumBytes,
            let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return nil }
        let dictionary = UsageDictionary(text: text)
        return dictionary.isEmpty ? nil : dictionary
    }
}
