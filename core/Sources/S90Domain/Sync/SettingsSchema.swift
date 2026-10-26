/// 設定のファイルの形式のバージョンと，古いバージョンから新しいバージョンへの移し替え(TODO 49)．
///
/// - バージョン 1: バージョンを書いていない形(2026-10-26 までの main)
/// - バージョン 2: `schemaVersion` を書くようにした．項目の形はバージョン 1 と同じ
/// - バージョン 3: キーの設定 `conversionKeys`(変換中のキー)と `modeKeys`(切り替えのキー)を，キー設定の表 `keymap` にまとめた(R-17)
/// - バージョン 4: 入力方式 `inputStyle` に英字入力(自動)`englishAuto` を足し，`englishInputLiveConversion` と `wordLanguage` を足した．
///   移し替えは要らない．バージョン 3 までの s90 は `englishAuto` を読めずにローマ字入力として読む
///
/// 項目の名前や形を変えるときは，バージョンを 1 つ上げ，`migrations` に移し替えを足す．移し替えは JSON のまま行い，
/// 読み込む前に古いバージョンから順に当てる．新しいバージョンのファイルを古いバージョンで開いたときは移し替えず，知らない項目を残す(Settings.unknownFields)
public enum SettingsSchema {
    public static let currentVersion = 4
    public static let versionKey = "schemaVersion"

    /// バージョン n から n+1 への移し替え．添字 0 がバージョン 1 → 2
    static let migrations: [@Sendable (inout [String: JSONValue]) -> Void] = [
        { _ in },
        { LegacyKeySettings.upgrade(&$0) },
        { _ in },
    ]

    /// ファイルのバージョンを読み，今のバージョンまで移し替える．今より新しいバージョンはそのまま
    public static func migrate(_ object: inout [String: JSONValue]) {
        var version = Self.version(of: object)
        while version < currentVersion, version >= 1, version - 1 < migrations.count {
            migrations[version - 1](&object)
            version += 1
        }
        if version <= currentVersion { object[versionKey] = .number(Double(max(version, currentVersion))) }
    }

    /// ファイルのバージョン．書いていなければ 1
    public static func version(of object: [String: JSONValue]) -> Int {
        if case .number(let value)? = object[versionKey], value >= 1, value < 10_000 { return Int(value) }
        return 1
    }
}
