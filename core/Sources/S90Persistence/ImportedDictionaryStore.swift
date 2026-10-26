import Foundation
import S90Application
import S90Domain

/// 取り込んだ辞書の語を，辞書ごとに索引のファイルに置き，読みで引く(R-16)．
///
/// 索引のファイルは「読み<タブ>語<タブ>品詞」の行を読みのバイト順に並べた UTF-8 のテキスト(SortedTabFile)．
/// 起動時には読まず，初めて引くときに開く
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
        // 読みが同じ語は語のバイト順に並べる(同じ辞書から同じ索引を作り，同期のバージョンを変えないため)
        let lines = words.filter(\.isValid).map { "\($0.reading)\t\($0.word)\t\($0.wordClass.rawValue)" }
            .sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
        try SortedTabFile.write(lines, to: url)
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

    /// 索引のファイル(SortedTabFile)と，行を語に読む処理
    final class Index {
        private let file: SortedTabFile

        init?(url: URL) {
            guard let file = SortedTabFile(url: url) else { return nil }
            self.file = file
        }

        var count: Int { file.count }

        /// 読みがちょうど reading の語
        func words(reading: String) -> [DictionaryWord] {
            file.lines(withKey: reading).compactMap(Self.parse)
        }

        private static func parse(_ line: String) -> DictionaryWord? {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 3 else { return nil }
            // 同期のフォルダから運んだ索引も読むので，取り込むときと同じ確かめをする
            let word = DictionaryWord(reading: String(columns[0]), word: String(columns[1]), wordClass: WordClass(rawValue: String(columns[2])) ?? .noun)
            return word.isValid ? word : nil
        }
    }
}
