import Foundation
import S90Domain

/// 取り込む連想の辞書のファイルを読む(R-18)．1 行が 1 つの意味のまとまり．
///
/// - タブ区切り: 「意味の説明<タブ>語<タブ>語…」．説明は空でよい
/// - タブの無い行: 「語,語,語」(「、」で区切ってもよい)．説明は付けない
/// - 「#」「!」で始まる行と空の行は読まない
///
/// 文字コードは取り込む辞書(DictionaryFileReader)と同じに見分ける．外から来るファイルなので，大きさとまとまりの数に上限を設け，
/// 形の正しいまとまり(AssociationGroup.isValid)だけを使う(docs/dev/SECURITY-MODEL.md)
public enum AssociationFileReader {
    public static func read(from url: URL) throws -> [AssociationGroup] {
        let data: Data
        do {
            data = try ProtectedFile.read(from: url, maximumBytes: DefaultSettings.maximumAssociationFileBytes)
        } catch let error as ProtectedFile.TooLarge {
            throw DictionaryFileReader.FileError.fileTooLarge(maximumBytes: error.maximumBytes)
        }
        let groups = try parse(data)
        guard !groups.isEmpty else { throw DictionaryFileReader.FileError.empty }
        return groups
    }

    public static func parse(_ data: Data) throws -> [AssociationGroup] {
        guard let text = DictionaryFileReader.decode(data) else { throw DictionaryFileReader.FileError.unreadable }
        var groups: [AssociationGroup] = []
        for line in text.split(whereSeparator: \.isNewline) {
            guard let group = parseLine(line) else { continue }
            groups.append(group)
            if groups.count >= DefaultSettings.maximumAssociationGroups { break }
        }
        return groups
    }

    static func parseLine(_ line: Substring) -> AssociationGroup? {
        guard !line.hasPrefix("#"), !line.hasPrefix("!") else { return nil }
        let label: String
        let items: [Substring]
        if line.contains("\t") {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            label = columns[0].trimmingCharacters(in: .whitespaces)
            items = Array(columns.dropFirst())
        } else {
            label = ""
            items = line.split { $0 == "," || $0 == "、" }
        }
        var seen = Set<String>()
        let words = items.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(DefaultSettings.maximumAssociationGroupWords)
        let group = AssociationGroup(label: label, words: Array(words))
        return group.isValid ? group : nil
    }
}
