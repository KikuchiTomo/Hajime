import Foundation
import HajimeDomain

/// ユーザー辞書を「読み<タブ>語」の行のテキストで読み書きする．
/// 「読み<タブ>単語」の行が並んだタブ区切りのテキスト(3 列目以降の品詞やコメントは読まない)
public enum UserDictionaryFile {
    public enum FileError: Error, Equatable {
        case fileTooLarge(maximumBytes: Int)
        case notText
    }

    /// 外から来るファイルなので，大きさに上限を設け，読みと語の形を確かめた行だけを使う(docs/dev/SECURITY-MODEL.md)
    public static func read(from url: URL) throws -> [UserDictionaryEntry] {
        try readCounting(from: url).entries
    }

    /// 読めた語と，形の誤った行(コメントと空の行を除く)の数
    public static func readCounting(from url: URL) throws -> (entries: [UserDictionaryEntry], skipped: Int) {
        let data: Data
        do {
            data = try ProtectedFile.read(from: url, maximumBytes: DefaultSettings.maximumUserDictionaryFileBytes)
        } catch let error as ProtectedFile.TooLarge {
            throw FileError.fileTooLarge(maximumBytes: error.maximumBytes)
        }
        guard let text = decode(data) else { throw FileError.notText }
        let entries = parse(text)
        return (entries, max(entryLines(text).count - entries.count, 0))
    }

    /// UTF-8 か，BOM の付いた UTF-16(Windows の辞書ツールが書き出す形)だけを読む．
    /// BOM の無い UTF-16 はほとんどどんなバイト列でも読めてしまい，Shift_JIS などを文字化けしたまま読むため
    static func decode(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(2))
        if bytes == [0xFF, 0xFE] || bytes == [0xFE, 0xFF] {
            return String(data: data, encoding: .utf16)
        }
        return String(data: data, encoding: .utf8)
    }

    public static func parse(_ text: String) -> [UserDictionaryEntry] {
        entryLines(text).compactMap { line in
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 2 else { return nil }
            let entry = UserDictionaryEntry(reading: String(columns[0]), word: String(columns[1]))
            return entry.isValid ? entry : nil
        }
    }

    /// 語として読む行(「!」「#」で始まる行と空の行を除く)
    private static func entryLines(_ text: String) -> [Substring] {
        text.split(whereSeparator: \.isNewline).filter { !$0.hasPrefix("!") && !$0.hasPrefix("#") }
    }

    public static func write(_ entries: [UserDictionaryEntry], to url: URL) throws {
        let text = entries.map { "\($0.reading)\t\($0.word)" }.joined(separator: "\n") + "\n"
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}
