import Foundation

/// 設定と JSON の変換．読むときは形式のバージョンを移し替えてから読む(SettingsSchema)
public enum SettingsCoding {
    public enum CodingError: Error, Equatable {
        /// 最上位が JSON のオブジェクトでない(設定のファイルではない)
        case notSettings
    }

    /// 設定のファイルの中身を読む．古いバージョンは今のバージョンに移し替え，知らない項目は Settings.unknownFields に残す
    public static func decode(_ data: Data) throws -> Settings {
        guard case .object(var object) = try JSONDecoder().decode(JSONValue.self, from: data) else { throw CodingError.notSettings }
        SettingsSchema.migrate(&object)
        return try settings(from: object)
    }

    public static func encode(_ settings: Settings) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(settings)
    }

    /// 設定を JSON のオブジェクトにする(同期で項目ごとに扱うため)
    public static func object(of settings: Settings) throws -> [String: JSONValue] {
        guard case .object(let object) = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(settings)) else {
            throw CodingError.notSettings
        }
        return object
    }

    /// JSON のオブジェクトから設定を作る．読めない項目と範囲の外の値は既定値にする．
    /// 古いバージョンの Mac が書いた同期のファイルから古いキーの設定を取り込んだときは，キー設定の表に移し替える
    public static func settings(from object: [String: JSONValue]) throws -> Settings {
        var object = object
        LegacyKeySettings.upgrade(&object)
        return try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(JSONValue.object(object)))
    }
}
