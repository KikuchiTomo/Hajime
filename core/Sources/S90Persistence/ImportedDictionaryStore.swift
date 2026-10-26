import Foundation
import S90Application
import S90Domain

/// 取り込んだ辞書の語を，辞書ごとに索引のファイルに置き，読みで引く(R-14)．
///
/// 索引のファイルは「読み<タブ>語<タブ>品詞」の行を読みのバイト順に並べた UTF-8 のテキスト．
/// 引くときはファイルをメモリに写し(mmap)，行の頭の位置の表を作って二分探索する．起動時には読まず，初めて引くときに開く．
/// 数十万語の辞書でも，1 つの読みを引くのは数十回の比較で済む
@MainActor
public final class ImportedDictionaryStore: DictionaryLookup {
    /// 置き場所(Application Support の dictionaries/)
    public let directory: URL
    private var indexes: [String: Index] = [:]

    public init(directory: URL) {
        self.directory = directory
    }

    public func url(for dictionary: ImportedDictionary) -> URL {
        directory.appendingPathComponent(dictionary.indexFileName)
    }

    /// 語を読みで並べて索引のファイルに書く．同じ辞書を開いていれば閉じる(取り込み直し)
    public nonisolated static func write(_ words: [DictionaryWord], to url: URL) throws {
        let lines = words.filter(\.isValid)
            .map { "\($0.reading)\t\($0.word)\t\($0.wordClass.rawValue)" }
            .sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
        var data = Data()
        data.reserveCapacity(lines.reduce(0) { $0 + $1.utf8.count + 1 })
        for line in lines {
            data.append(contentsOf: line.utf8)
            data.append(0x0A)
        }
        try ProtectedFile.write(data, to: url)
    }

    public func reload(_ dictionary: ImportedDictionary) {
        indexes[dictionary.id] = nil
    }

    public func remove(_ dictionary: ImportedDictionary) {
        indexes[dictionary.id] = nil
        try? FileManager.default.removeItem(at: url(for: dictionary))
    }

    public func words(reading: String, in dictionary: ImportedDictionary) -> [DictionaryWord] {
        index(for: dictionary)?.words(reading: reading) ?? []
    }

    private func index(for dictionary: ImportedDictionary) -> Index? {
        if let index = indexes[dictionary.id] { return index }
        guard let index = Index(url: url(for: dictionary)) else { return nil }
        indexes[dictionary.id] = index
        return index
    }

    /// 写したファイルと，行の頭の位置の表
    final class Index {
        private let data: Data
        private let lineStarts: [Int]

        init?(url: URL) {
            guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
            self.data = data
            var starts: [Int] = []
            data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                var start = 0
                for (offset, byte) in buffer.enumerated() where byte == 0x0A {
                    if offset > start { starts.append(start) }
                    start = offset + 1
                }
                if start < buffer.count { starts.append(start) }
            }
            lineStarts = starts
        }

        var count: Int { lineStarts.count }

        /// 読みがちょうど reading の語
        func words(reading: String) -> [DictionaryWord] {
            let key = Array(reading.utf8)
            return data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> [DictionaryWord] in
                // 読み(タブまで)を key と比べる．小さければ負，同じなら 0，大きければ正
                func compare(_ line: Int) -> Int {
                    var position = lineStarts[line]
                    for byte in key {
                        guard position < buffer.count else { return -1 }
                        let current = buffer[position]
                        if current == 0x09 { return -1 }
                        if current != byte { return current < byte ? -1 : 1 }
                        position += 1
                    }
                    return position < buffer.count && buffer[position] == 0x09 ? 0 : 1
                }
                var low = 0
                var high = lineStarts.count
                while low < high {
                    let middle = (low + high) / 2
                    if compare(middle) < 0 { low = middle + 1 } else { high = middle }
                }
                var result: [DictionaryWord] = []
                var line = low
                while line < lineStarts.count, compare(line) == 0 {
                    if let word = parse(line, buffer) { result.append(word) }
                    line += 1
                }
                return result
            }
        }

        private func parse(_ line: Int, _ buffer: UnsafeRawBufferPointer) -> DictionaryWord? {
            let start = lineStarts[line]
            var end = start
            while end < buffer.count, buffer[end] != 0x0A { end += 1 }
            let text = String(decoding: UnsafeRawBufferPointer(rebasing: buffer[start..<end]), as: UTF8.self)
            let columns = text.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 3 else { return nil }
            return DictionaryWord(reading: String(columns[0]), word: String(columns[1]), wordClass: WordClass(rawValue: String(columns[2])) ?? .noun)
        }
    }
}
