import Foundation
import HajimeDomain

/// 決まりの一覧(補正の置き換え・直さない語・ローマ字・記号)を「左<タブ>右」の行のテキストで読み書きする．
/// 1 列だけの一覧(直さない語)は右を空にする．行の形を確かめるのは読み込む側(それぞれの決まりの isValid)
public enum RuleListFile {
    public enum FileError: Error, Equatable {
        case fileTooLarge(maximumBytes: Int)
        case notText
    }

    /// 1 行．左は打つもの(打った英字・入力・読み)，右は出すもの
    public typealias Row = RuleListRow

    /// 外から来るファイルなので，大きさに上限を設ける(docs/dev/SECURITY-MODEL.md)
    public static func read(from url: URL) throws -> [Row] {
        let data: Data
        do {
            data = try ProtectedFile.read(from: url, maximumBytes: DefaultSettings.maximumRuleListFileBytes)
        } catch let error as ProtectedFile.TooLarge {
            throw FileError.fileTooLarge(maximumBytes: error.maximumBytes)
        }
        guard let text = UserDictionaryFile.decode(data) else { throw FileError.notText }
        return parse(text)
    }

    /// 空の行と「#」で始まる行は読まない．3 列目以降は読まない．前後の空白は除く
    public static func parse(_ text: String) -> [Row] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let key = columns.first, !key.isEmpty else { return nil }
            return Row(key: key, value: columns.count > 1 ? columns[1] : "")
        }
    }

    /// タブと改行は区切りに使うので，中身にあれば空白に置き換える
    public static func write(_ rows: [Row], to url: URL) throws {
        func clean(_ text: String) -> String {
            String(text.map { $0 == "\t" || $0.isNewline ? " " : $0 })
        }
        let text = rows.map { $0.value.isEmpty ? clean($0.key) : "\(clean($0.key))\t\(clean($0.value))" }.joined(separator: "\n") + "\n"
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}
