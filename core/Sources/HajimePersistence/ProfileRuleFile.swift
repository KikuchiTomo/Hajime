import Foundation
import HajimeDomain

/// 除外設定(アプリの扱いの規則)を CSV のファイルで読み書きする．形は ProfileRuleCSV
public enum ProfileRuleFile {
    public enum FileError: Error, Equatable {
        case fileTooLarge(maximumBytes: Int)
        case notText
    }

    public static func read(from url: URL) throws -> [ProfileRule] {
        try readCounting(from: url).rules
    }

    /// 読める規則と，読めなかった行(見出し・# で始まる行・空の行を除く)の数
    public static func readCounting(from url: URL) throws -> (rules: [ProfileRule], skipped: Int) {
        let data: Data
        do {
            data = try ProtectedFile.read(from: url, maximumBytes: DefaultSettings.maximumProfileRuleFileBytes)
        } catch let error as ProtectedFile.TooLarge {
            throw FileError.fileTooLarge(maximumBytes: error.maximumBytes)
        }
        guard let text = String(data: data, encoding: .utf8) else { throw FileError.notText }
        let rules = ProfileRuleCSV.parse(text)
        return (rules, max(ProfileRuleCSV.ruleLineCount(text) - rules.count, 0))
    }

    public static func write(_ rules: [ProfileRule], to url: URL) throws {
        try Data(ProfileRuleCSV.write(rules).utf8).write(to: url, options: .atomic)
    }
}
