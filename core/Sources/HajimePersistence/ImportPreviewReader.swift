import Foundation
import HajimeDomain

/// 辞書のファイルを取り込む前の中身の読み方(ImportPreview)を作る．
/// 行ごとの決まりは，実際に取り込むときの読み方(UserDictionaryFile・DictionaryFileReader・AssociationFileReader)と同じにする．
/// 「#」「!」(SKK は「;」)で始まる行と空の行は，取り込むときと同じく読まずに飛ばし，見せない
public enum ImportPreviewReader {
    public static func preview(_ kind: ImportPreview.Kind, data: Data) throws -> ImportPreview {
        var builder = Builder()
        let (format, columns): (ImportPreview.Format, [ImportPreview.Column])
        switch kind {
        case .association:
            guard let text = DictionaryFileReader.decode(data) else { throw DictionaryFileReader.FileError.unreadable }
            format = association(text, into: &builder)
            columns = [.meaning, .words]
        case .userDictionary, .dictionary:
            // 登録した単語は，plist と SKK の語も登録する単語として読める形かを確かめる(UserDictionaryFile.fromOtherFormat)
            let accepts: (DictionaryWord) -> Bool = kind == .userDictionary
                ? { $0.isValid && UserDictionaryEntry(reading: $0.reading, word: $0.word, wordClass: $0.wordClass).isValid }
                : { $0.isValid }
            if DictionaryFileReader.isPropertyList(data) {
                try propertyList(data, accepts: accepts, into: &builder)
                (format, columns) = (.propertyList, [.reading, .word])
            } else {
                guard let text = DictionaryFileReader.decode(data) else { throw DictionaryFileReader.FileError.unreadable }
                if DictionaryFileReader.detectFormat(text) == .skk {
                    skk(text, accepts: accepts, into: &builder)
                    (format, columns) = (.skk, [.reading, .word])
                } else if kind == .userDictionary {
                    userTabSeparated(text, into: &builder)
                    (format, columns) = (.tabSeparated, [.reading, .word, .wordClass, .comment])
                } else {
                    dictionaryTabSeparated(text, into: &builder)
                    (format, columns) = (.tabSeparated, [.reading, .word, .wordClass])
                }
            }
        }
        return builder.preview(kind: kind, format: format, columns: columns)
    }

    // MARK: - 行の読み方

    /// 登録した単語のタブ区切り(UserDictionaryFile.parse)．読みはそのまま，品詞の列が無ければ名詞，4 列目はコメント
    private static func userTabSeparated(_ text: String, into builder: inout Builder) {
        for (line, content) in lines(text) where !content.hasPrefix("!") && !content.hasPrefix("#") {
            let columns = content.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 2 else {
                builder.add(line, raw(columns), .unreadable)
                continue
            }
            let wordClass = columns.count >= 3 ? WordClass(partOfSpeech: String(columns[2])) : DefaultSettings.userWordClass
            let comment = columns.count >= 4
                ? String(columns[3].trimmingCharacters(in: .whitespaces).prefix(DefaultSettings.maximumUserDictionaryCommentLength)) : ""
            let entry = UserDictionaryEntry(reading: String(columns[0]), word: String(columns[1]), wordClass: wordClass, comment: comment)
            guard entry.isValid else {
                builder.add(line, raw(columns), .unreadable)
                continue
            }
            let status = defaults(columns.count >= 3 ? columns[2] : nil, to: wordClass) ? ImportPreview.Status.defaultedWordClass : .ok
            builder.add(line, [entry.reading, entry.word, wordClass.rawValue, comment], status)
        }
    }

    /// 取り込む辞書のタブ区切り(DictionaryFileReader.parseTabSeparated)．読みはひらがなにそろえ，同じ語は 1 つにする
    private static func dictionaryTabSeparated(_ text: String, into builder: inout Builder) {
        var seen = Set<DictionaryWord>()
        for (line, content) in lines(text) where !content.hasPrefix("!") && !content.hasPrefix("#") {
            let columns = content.split(separator: "\t", omittingEmptySubsequences: false)
            guard let word = DictionaryFileReader.parseTabSeparated(content).first, word.isValid else {
                builder.add(line, raw(columns), .unreadable)
                continue
            }
            guard seen.insert(word).inserted else { continue }
            let status = defaults(columns.count >= 3 ? columns[2] : nil, to: word.wordClass) ? ImportPreview.Status.defaultedWordClass : .ok
            builder.add(line, [word.reading, word.word, word.wordClass.rawValue], status)
        }
    }

    /// SKK の辞書．1 行に並ぶ語を 1 つずつの行にする．送り仮名のある読みの行は取り込まない
    private static func skk(_ text: String, accepts: (DictionaryWord) -> Bool, into builder: inout Builder) {
        var seen = Set<DictionaryWord>()
        for (line, content) in lines(text) where !content.hasPrefix(";") {
            let words = DictionaryFileReader.parseSKK(content)
            guard !words.isEmpty else {
                builder.add(line, [String(content)], .unreadable)
                continue
            }
            for word in words {
                guard accepts(word) else {
                    builder.add(line, [word.reading, word.word], .unreadable)
                    continue
                }
                if seen.insert(word).inserted { builder.add(line, [word.reading, word.word], .ok) }
            }
        }
    }

    /// macOS のユーザ辞書の書き出し(phrase と shortcut の組)
    private static func propertyList(_ data: Data, accepts: (DictionaryWord) -> Bool, into builder: inout Builder) throws {
        guard let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else {
            throw DictionaryFileReader.FileError.unreadable
        }
        var seen = Set<DictionaryWord>()
        for (index, item) in list.enumerated() {
            let phrase = item["phrase"] as? String ?? ""
            let shortcut = item["shortcut"] as? String ?? ""
            let word = DictionaryWord(reading: DictionaryFileReader.normalizedReading(Substring(shortcut)), word: phrase)
            guard accepts(word) else {
                builder.add(index + 1, [shortcut, phrase], .unreadable)
                continue
            }
            if seen.insert(word).inserted { builder.add(index + 1, [word.reading, word.word], .ok) }
        }
    }

    /// 連想の辞書(AssociationFileReader.parseLine)．タブの行は先頭の列が意味の説明，タブの無い行は「,」「、」で区切った語
    private static func association(_ text: String, into builder: inout Builder) -> ImportPreview.Format {
        var tabs = 0
        for (line, content) in lines(text) where !content.hasPrefix("#") && !content.hasPrefix("!") {
            let tabbed = content.contains("\t")
            if tabbed { tabs += 1 }
            guard let group = AssociationFileReader.parseLine(content) else {
                // 読めない行も意味の説明と語の列に分けて見せる
                let columns = tabbed ? content.split(separator: "\t", omittingEmptySubsequences: false) : ["", content]
                builder.add(line, [String(columns[0]), columns.dropFirst().joined(separator: "、")], .unreadable)
                continue
            }
            builder.add(line, [group.label, group.words.joined(separator: "、")], .ok)
        }
        // タブの行が 1 つでもあればタブ区切り(タブの無い行は「,」で区切った語として読む)
        return tabs > 0 ? .tabSeparated : .commaSeparated
    }

    // MARK: - 補助

    /// 空でない行と，その行の番号(1 から)
    private static func lines(_ text: String) -> [(Int, Substring)] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated().compactMap { index, line in
            line.isEmpty ? nil : (index + 1, line)
        }
    }

    private static func raw(_ columns: [Substring]) -> [String] {
        columns.map(String.init)
    }

    /// 品詞の列が無いか，知らない品詞の名前なので名詞にしたか(「名詞」と書いてあれば名詞のまま)
    private static func defaults(_ column: Substring?, to wordClass: WordClass) -> Bool {
        guard let column, !column.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
        return wordClass == .noun && !column.contains("名詞")
    }

    /// 行を数え，見せる行を集める．上限を超えたら，取り込める行より読めない行と名詞にする行を先に残す
    private struct Builder {
        /// 見せる行と，足した順(同じ行の番号の語を並べた順のままにする)
        private var problems: [(Int, ImportPreview.Row)] = []
        private var plain: [(Int, ImportPreview.Row)] = []
        private var added = 0
        private var counts = (importable: 0, defaulted: 0, unreadable: 0)

        mutating func add(_ line: Int, _ cells: [String], _ status: ImportPreview.Status) {
            switch status {
            case .ok: counts.importable += 1
            case .defaultedWordClass: counts.importable += 1; counts.defaulted += 1
            case .unreadable: counts.unreadable += 1
            }
            let row = ImportPreview.Row(line: line, cells: cells, status: status)
            added += 1
            if status == .ok {
                if plain.count < DefaultSettings.maximumImportPreviewRows { plain.append((added, row)) }
            } else if problems.count < DefaultSettings.maximumImportPreviewRows {
                problems.append((added, row))
            }
        }

        func preview(kind: ImportPreview.Kind, format: ImportPreview.Format, columns: [ImportPreview.Column]) -> ImportPreview {
            let room = max(DefaultSettings.maximumImportPreviewRows - problems.count, 0)
            let rows = (problems + plain.prefix(room)).sorted { $0.0 < $1.0 }.map(\.1)
            return ImportPreview(kind: kind, format: format, columns: columns, rows: rows,
                                 importable: counts.importable, defaulted: counts.defaulted, unreadable: counts.unreadable)
        }
    }
}
