import Foundation
import HajimeApplication
import HajimeDomain

/// アプリに同梱した英語の語の辞書(data/english/english-terms.txt)を読む(R-24)．
/// 初めて使うときに読み込む．読めなければ利用者が足した語だけを使う．通信しない
@MainActor
public final class EnglishTermFile: EnglishTermProviding {
    private let url: URL
    private var loaded: EnglishTermDictionary??

    public init(url: URL) {
        self.url = url
    }

    public var englishTerms: EnglishTermDictionary? {
        if let loaded { return loaded }
        let dictionary = Self.load(url)
        loaded = .some(dictionary)
        return dictionary
    }

    private static func load(_ url: URL) -> EnglishTermDictionary? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? Int, size <= DefaultSettings.maximumEnglishTermFileBytes,
            let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return nil }
        let dictionary = EnglishTermDictionary(text: text)
        return dictionary.isEmpty ? nil : dictionary
    }
}
