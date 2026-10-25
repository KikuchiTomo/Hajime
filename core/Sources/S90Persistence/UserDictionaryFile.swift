import Foundation
import S90Domain

/// ユーザー辞書を「読み<タブ>語」の行のテキストで読み書きする．
/// Google 日本語入力と ATOK が書き出す形(3 列目以降の品詞やコメントは読まない)
public enum UserDictionaryFile {
    public enum FileError: Error, Equatable {
        case fileTooLarge(bytes: Int)
        case notText
    }

    /// 外から来るファイルなので，大きさに上限を設け，読みと語の形を確かめた行だけを使う(docs/dev/SECURITY-MODEL.md)
    public static func read(from url: URL) throws -> [UserDictionaryEntry] {
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= DefaultSettings.maximumUserDictionaryFileBytes else { throw FileError.fileTooLarge(bytes: size) }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { throw FileError.notText }
        return parse(text)
    }

    public static func parse(_ text: String) -> [UserDictionaryEntry] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            guard !line.hasPrefix("!"), !line.hasPrefix("#") else { return nil }
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 2 else { return nil }
            let entry = UserDictionaryEntry(reading: String(columns[0]), word: String(columns[1]))
            return entry.isValid ? entry : nil
        }
    }

    public static func write(_ entries: [UserDictionaryEntry], to url: URL) throws {
        let text = entries.map { "\($0.reading)\t\($0.word)" }.joined(separator: "\n") + "\n"
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}
