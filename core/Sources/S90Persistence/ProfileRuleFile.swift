import Foundation
import S90Domain

/// 除外設定(アプリの扱いの規則)を CSV のファイルで読み書きする．形は ProfileRuleCSV
public enum ProfileRuleFile {
    public enum FileError: Error, Equatable {
        case fileTooLarge(maximumBytes: Int)
        case notText
    }

    public static func read(from url: URL) throws -> [ProfileRule] {
        let data: Data
        do {
            data = try ProtectedFile.read(from: url, maximumBytes: DefaultSettings.maximumProfileRuleFileBytes)
        } catch let error as ProtectedFile.TooLarge {
            throw FileError.fileTooLarge(maximumBytes: error.maximumBytes)
        }
        guard let text = String(data: data, encoding: .utf8) else { throw FileError.notText }
        return ProfileRuleCSV.parse(text)
    }

    public static func write(_ rules: [ProfileRule], to url: URL) throws {
        try Data(ProfileRuleCSV.write(rules).utf8).write(to: url, options: .atomic)
    }
}
