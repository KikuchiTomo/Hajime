import Foundation
import HajimeApplication

/// アプリに同梱した郵便番号の表(data/postal/postal-codes.tsv)を引く(R-13)．
/// 初めて引くときに読み込む(郵便番号を打たない人には読み込む手間をかけない)．通信しない
@MainActor
public final class PostalCodeFile: PostalCodeLooking {
    /// 表の大きさの上限．同梱の表は 5MB ほど．壊れた大きなファイルを読み込まないため
    static let maximumBytes = 32 * 1024 * 1024

    private let url: URL
    private var table: [Substring: [String]]?

    public init(url: URL) {
        self.url = url
    }

    public func addresses(for code: String) -> [String] {
        if table == nil { table = Self.load(url) }
        return table?[Substring(code)] ?? []
    }

    /// 「郵便番号<タブ>住所<タブ>住所…」の行を読む．# で始まる行と形の誤った行は飛ばす
    static func parse(_ text: String) -> [Substring: [String]] {
        var table: [Substring: [String]] = [:]
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t")
            guard fields.count >= 2, fields[0].count == 7, fields[0].allSatisfy(\.isASCII) else { continue }
            table[fields[0]] = fields.dropFirst().map(String.init)
        }
        return table
    }

    private static func load(_ url: URL) -> [Substring: [String]] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? Int, size <= maximumBytes,
            let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return [:] }
        return parse(text)
    }
}
