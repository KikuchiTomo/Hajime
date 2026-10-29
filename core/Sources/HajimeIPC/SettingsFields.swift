import Foundation
import HajimeDomain

/// 設定の項目を，設定のファイルと同じ名前と JSON の形で読み書きする．Windows の設定の画面がエンジンに頼むときに使う．
///
/// 項目ごとの型を IPC の定義に写さず，設定のファイルの形(Settings の Codable)をそのまま使う．
/// 項目を足しても IPC の定義を変えずに済み，macOS と同じ項目を同じ値で扱える
public enum SettingsFields {
    public enum Failure: Error, Equatable {
        /// JSON のオブジェクトとして読めない
        case malformed
        /// 設定に無い項目の名前
        case unknownField(String)
    }

    /// names の項目を JSON のオブジェクトにする．names が空ならすべての項目
    public static func read(_ settings: Settings, names: [String]) throws(Failure) -> String {
        let all = try object(of: settings)
        for name in names where !Settings.fieldNames.contains(name) { throw .unknownField(name) }
        // 値の無い項目(選んでいないカスタムテーマなど)は null にして，頼んだ名前をすべて返す
        let wanted = names.isEmpty ? Settings.fieldNames : Set(names)
        return try text(of: Dictionary(uniqueKeysWithValues: wanted.map { ($0, all[$0] ?? .null) }))
    }

    /// values(項目の名前から値への JSON のオブジェクト)を settings に重ねる．
    /// 値は設定のファイルを読むときと同じに読み，範囲の外の値は範囲に収める(Settings.clampToValidRanges)．
    /// 読めない値は今の値のまま．返すのは重ねた設定と，書いた項目の名前
    public static func merge(_ values: String, into settings: Settings) throws(Failure) -> (settings: Settings, names: [String]) {
        guard let data = values.data(using: .utf8),
              let changes = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { throw .malformed }
        for name in changes.keys where !Settings.fieldNames.contains(name) { throw .unknownField(name) }
        var merged = try object(of: settings)
        merged.merge(changes) { _, new in new }
        guard let encoded = try? JSONEncoder().encode(merged),
              let result = try? JSONDecoder().decode(Settings.self, from: encoded) else { throw .malformed }
        return (result, changes.keys.sorted())
    }

    private static func object(of settings: Settings) throws(Failure) -> [String: JSONValue] {
        guard let data = try? JSONEncoder().encode(settings),
              let object = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { throw .malformed }
        return object
    }

    static func text(of object: [String: JSONValue]) throws(Failure) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(object), let text = String(data: data, encoding: .utf8) else { throw .malformed }
        return text
    }
}

extension SettingsFields {
    /// キー設定のひな形を，keymap の項目として返す
    public static func keymapPreset(named name: String) throws(Failure) -> String {
        guard let preset = KeymapPreset(rawValue: name) else { throw .unknownField(name) }
        var settings = DefaultSettings.settings
        settings.keymap = preset.keymap
        return try read(settings, names: ["keymap"])
    }

    /// values の keymap の項目(表)を調べ，使われない行・文字を打てなくなる行・キーの無い確定と取り消しを返す
    public static func keymapReport(_ values: String) throws(Failure) -> WireKeymapReport {
        let keymap = try merge(values, into: DefaultSettings.settings).settings.keymap
        var rows: [WireKeymapRowIssue] = []
        for (index, entry) in keymap.entries.enumerated() {
            var hiddenBy: [Int] = []
            var hiddenStates: [KeymapState] = []
            switch keymap.overlap(at: index) {
            case .hidden(let winners)?:
                hiddenBy = winners
            case .partlyHidden(let states, let winners)?:
                hiddenBy = winners
                hiddenStates = states
            case nil:
                break
            }
            guard !hiddenBy.isEmpty || entry.blocksTyping else { continue }
            rows.append(WireKeymapRowIssue(row: UInt32(clamping: index), hiddenBy: hiddenBy.map { UInt32(clamping: $0) },
                                           hiddenStates: hiddenStates.map(\.rawValue), blocksTyping: entry.blocksTyping))
        }
        let missing = keymap.missingEssentials.map { WireKeymapMissing(state: $0.state.rawValue, command: $0.command.rawValue) }
        return WireKeymapReport(rows: rows, missing: missing)
    }
}
