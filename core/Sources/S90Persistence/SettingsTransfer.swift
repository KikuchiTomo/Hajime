import Foundation
import S90Domain

/// すべての設定(ユーザー辞書・テーマ・キーの割り当てを含む)を JSON のファイルに書き出し，読み込む．
/// 別の Mac に移したり，控えを取ったりするため．形は設定のファイル(settings.json)と同じ
public enum SettingsTransfer {
    public enum TransferError: Error, Equatable {
        case fileTooLarge(maximumBytes: Int)
        /// JSON として読めない(設定のファイルではない)
        case notSettings
    }

    public static func write(_ settings: Settings, to url: URL) throws {
        try Data(encode(settings)).write(to: url, options: .atomic)
    }

    /// 外から来るファイルなので，大きさに上限を設ける．読めない項目と範囲の外の値は既定値にする(Settings の読み込みの決まり)
    public static func read(from url: URL) throws -> Settings {
        let data: Data
        do {
            data = try ProtectedFile.read(from: url, maximumBytes: DefaultSettings.maximumSettingsFileBytes)
        } catch let error as ProtectedFile.TooLarge {
            throw TransferError.fileTooLarge(maximumBytes: error.maximumBytes)
        }
        return try decode(data)
    }

    static func encode(_ settings: Settings) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(settings)
    }

    static func decode(_ data: Data) throws -> Settings {
        // 最上位が JSON のオブジェクトでなければ，設定のファイルではないとして断る(何でも既定値として読み込まないように)
        guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { throw TransferError.notSettings }
        return try JSONDecoder().decode(Settings.self, from: data)
    }
}
