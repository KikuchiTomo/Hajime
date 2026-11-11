import Foundation
import HajimeApplication
import HajimeDomain

/// アプリに同梱した語の意味と同音異義語の使い分けの辞書(data/usage/usage_dict.txt と usage_dict_extra.tsv と usage_dict_words.tsv)を読む(R-08)．
/// 複数のファイルは続けて 1 つの辞書として読む．読めないファイルは飛ばす．通信しない．
/// 合わせて数 MB あり，読むのに 0.5 秒ほどかかるので裏で読む(打鍵を止めない)．読み終わるまでは辞書が無いものとして扱う．
/// 起動時に preload を呼んでおくと，初めて変換するときにはもう読み終わっている．注釈を出さない人は呼ばなければ読まない
@MainActor
public final class UsageDictionaryFile: UsageDictionaryProviding {
    /// 1 つのファイルの大きさの上限．同梱の辞書は 220KB から 5MB ほど．壊れた大きなファイルを読み込まないため
    nonisolated static let maximumBytes = 8 * 1024 * 1024

    private let urls: [URL]
    private var loaded: UsageDictionary??
    private var loading: Task<UsageDictionary?, Never>?

    public convenience init(url: URL) {
        self.init(urls: [url])
    }

    public init(urls: [URL]) {
        self.urls = urls
    }

    /// 読み終わった辞書．まだなら裏で読み始めて nil を返す
    public var usageDictionary: UsageDictionary? {
        if let loaded { return loaded }
        preload()
        return nil
    }

    /// 辞書を裏で読み始める
    public func preload() {
        guard loaded == nil, loading == nil else { return }
        let urls = urls
        let task = Task.detached(priority: .utility) { Self.load(urls) }
        loading = task
        Task { [weak self] in
            let dictionary = await task.value
            self?.loaded = .some(dictionary)
        }
    }

    /// 読み終わるまで待って辞書を返す(試す道具とテストのため)
    public func waitForLoad() async -> UsageDictionary? {
        if let loaded { return loaded }
        preload()
        let dictionary = await loading?.value ?? nil
        loaded = .some(dictionary)
        return dictionary
    }

    nonisolated private static func load(_ urls: [URL]) -> UsageDictionary? {
        let texts = urls.compactMap(read)
        guard !texts.isEmpty else { return nil }
        let dictionary = UsageDictionary(text: texts.joined(separator: "\n"))
        return dictionary.isEmpty ? nil : dictionary
    }

    nonisolated private static func read(_ url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? Int, size <= maximumBytes,
            let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
