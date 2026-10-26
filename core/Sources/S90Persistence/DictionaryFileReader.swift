import Foundation
import S90Domain

/// 取り込む辞書のファイルを読む．形式と文字コードはファイルの中身から見分ける．
///
/// - タブ区切り: 「読み<タブ>語<タブ>品詞<タブ>コメント」の行(3 列目以降は無くてよい)．「!」「#」で始まる行は読まない
/// - plist: macOS のユーザ辞書を書き出した形(phrase と shortcut の組の配列)
/// - SKK: 「よみ /語1/語2;注釈/」の行．「;」で始まる行と，送り仮名のある読み(末尾が英字)は読まない
///
/// 文字コードは BOM の付いた UTF-8・UTF-16，UTF-8，BOM の無い UTF-16(1 つおきのバイトが日本語の文字の上位のバイトのもの)，
/// Shift_JIS，EUC-JP の順に試す．外から来るファイルなので，大きさに上限を設け，形の正しい語だけを使う(docs/dev/SECURITY-MODEL.md)
public enum DictionaryFileReader {
    public enum FileError: Error, Equatable {
        case fileTooLarge(maximumBytes: Int)
        case unreadable
        case empty
    }

    public enum Format: Equatable, Sendable {
        case tabSeparated
        case propertyList
        case skk
    }

    public static func read(from url: URL) throws -> [DictionaryWord] {
        let data: Data
        do {
            data = try ProtectedFile.read(from: url, maximumBytes: DefaultSettings.maximumImportedDictionaryBytes)
        } catch let error as ProtectedFile.TooLarge {
            throw FileError.fileTooLarge(maximumBytes: error.maximumBytes)
        }
        let words = try parse(data)
        guard !words.isEmpty else { throw FileError.empty }
        return words
    }

    /// バイト列から語を読む．形式と文字コードを見分ける
    public static func parse(_ data: Data) throws -> [DictionaryWord] {
        if isPropertyList(data) {
            return try parsePropertyList(data)
        }
        guard let text = decode(data) else { throw FileError.unreadable }
        let format = detectFormat(text)
        var words: [DictionaryWord] = []
        var seen = Set<DictionaryWord>()
        for line in text.split(whereSeparator: \.isNewline) {
            for word in format == .skk ? parseSKK(line) : parseTabSeparated(line) where word.isValid && seen.insert(word).inserted {
                words.append(word)
                if words.count >= DefaultSettings.maximumImportedWords { return words }
            }
        }
        return words
    }

    // MARK: - 文字コード

    static func decode(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(4))
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        // UTF-8 として正しく読めれば UTF-8．UTF-16 や Shift_JIS の日本語は，UTF-8 としてはほとんど読めない
        if let text = String(data: data, encoding: .utf8) { return text }
        if let utf16 = bomlessUTF16(data), let text = String(data: data, encoding: utf16) { return text }
        if let text = String(data: data, encoding: .shiftJIS) { return text }
        #if os(Windows)
        // Windows の Foundation は EUC-JP を読めないので，Shift_JIS に並べ替えて読む
        return JapaneseEUC.decode(data)
        #else
        return String(data: data, encoding: .japaneseEUC)
        #endif
    }

    /// BOM の無い UTF-16 か．はじめの部分で，1 つおきのバイト(UTF-16 の上位のバイト)の多くが，
    /// 日本語の辞書に出る文字の上位のバイト(ASCII の 0x00，かなの 0x30，漢字の 0x4E〜0x9F，全角の 0xFF)なら UTF-16 とみなす
    private static func bomlessUTF16(_ data: Data) -> String.Encoding? {
        let sample = [UInt8](data.prefix(4096))
        guard sample.count >= 8 else { return nil }
        func ratio(_ start: Int) -> Double {
            let bytes = stride(from: start, to: sample.count, by: 2).map { sample[$0] }
            let plausible = bytes.filter { $0 == 0x00 || $0 == 0x30 || (0x4E...0x9F).contains($0) || $0 == 0xFF }.count
            return Double(plausible) / Double(bytes.count)
        }
        let low = ratio(1)
        let high = ratio(0)
        if low >= 0.9, low > high { return .utf16LittleEndian }
        if high >= 0.9, high > low { return .utf16BigEndian }
        return nil
    }

    // MARK: - 形式

    static func detectFormat(_ text: String) -> Format {
        var skk = 0
        var tab = 0
        for line in text.split(whereSeparator: \.isNewline).prefix(200) {
            if line.contains("\t") { tab += 1 }
            if line.contains(" /"), line.hasSuffix("/") { skk += 1 }
        }
        return skk > tab ? .skk : .tabSeparated
    }

    static func parseTabSeparated(_ line: Substring) -> [DictionaryWord] {
        guard !line.hasPrefix("!"), !line.hasPrefix("#") else { return [] }
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard columns.count >= 2 else { return [] }
        let wordClass = columns.count >= 3 ? WordClass(partOfSpeech: String(columns[2])) : .noun
        return [DictionaryWord(reading: normalizedReading(columns[0]), word: String(columns[1]), wordClass: wordClass)]
    }

    static func parseSKK(_ line: Substring) -> [DictionaryWord] {
        guard !line.hasPrefix(";"), let space = line.firstIndex(of: " ") else { return [] }
        let reading = line[..<space]
        // 送り仮名のある読み(「おくr」)は，語の続きを決められないので読まない
        guard let last = reading.last, !(last.isASCII && last.isLetter) else { return [] }
        let body = line[line.index(after: space)...].trimmingCharacters(in: .whitespaces)
        return body.split(separator: "/").compactMap { item in
            // 「;」のあとは注釈
            let word = item.split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
            return word.isEmpty ? nil : DictionaryWord(reading: normalizedReading(reading), word: word)
        }
    }

    // MARK: - plist

    private static func isPropertyList(_ data: Data) -> Bool {
        let head = data.prefix(64)
        if head.starts(with: Array("bplist".utf8)) { return true }
        guard let text = String(data: head, encoding: .utf8) else { return false }
        return text.contains("<?xml") || text.contains("<plist")
    }

    private static func parsePropertyList(_ data: Data) throws -> [DictionaryWord] {
        guard let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else {
            throw FileError.unreadable
        }
        var seen = Set<DictionaryWord>()
        return list.compactMap { item -> DictionaryWord? in
            guard let phrase = item["phrase"] as? String, let shortcut = item["shortcut"] as? String else { return nil }
            let word = DictionaryWord(reading: normalizedReading(Substring(shortcut)), word: phrase)
            return word.isValid && seen.insert(word).inserted ? word : nil
        }.prefix(DefaultSettings.maximumImportedWords).map { $0 }
    }

    /// 読みをひらがなにそろえる(カタカナの読みの辞書もあるため)
    private static func normalizedReading(_ reading: Substring) -> String {
        KanaWidth.hiragana(from: reading.trimmingCharacters(in: .whitespaces))
    }
}
