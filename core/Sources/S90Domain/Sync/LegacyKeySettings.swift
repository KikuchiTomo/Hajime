import Foundation

/// バージョン 2 までのキーの設定(conversionKeys と modeKeys)を，キー設定の表(keymap)に移し替える(R-17)．
///
/// 古いバージョンの設定のファイルを読むとき(SettingsSchema のバージョン 2 → 3)と，古いバージョンの Mac が書いた同期のファイルの値を取り込むとき
/// (SettingsCoding.settings(from:))に使う．古い項目を見つけたら，今の表(無ければ既定の表)の該当する行をその値で置き換え，古い項目は消す
public enum LegacyKeySettings {
    public static let conversionKeysField = "conversionKeys"
    public static let modeKeysField = "modeKeys"

    /// 古い項目があれば表に移し替える．無ければ何もしない
    public static func upgrade(_ object: inout [String: JSONValue]) {
        let conversion = object.removeValue(forKey: conversionKeysField)
        let mode = object.removeValue(forKey: modeKeysField)
        guard conversion != nil || mode != nil else { return }
        var keymap = object["keymap"].flatMap { decode(Keymap.self, from: $0) } ?? KeymapPreset.standard.keymap
        if let bindings = conversion.flatMap({ decode(OldBindings.self, from: $0) }) {
            apply(bindings, to: &keymap)
        }
        if let assignments = mode.flatMap({ decode([String: String].self, from: $0) }) {
            apply(assignments, to: &keymap)
        }
        if let value = encode(keymap) { object["keymap"] = value }
    }

    // MARK: 変換中のキー(conversionKeys)

    /// バージョン 2 の KeyBindings の形．{"commands": {"nextSegment": [{"key": {"right": {}}, "shift": false, ...}]}}
    private struct OldBindings: Decodable {
        var commands: [String: [OldStroke]]
    }

    private struct OldStroke: Decodable {
        var key: [String: JSONValue]
        var shift: Bool
        var control: Bool
        var option: Bool

        var stroke: KeyStroke? {
            guard let (name, value) = key.first, key.count == 1 else { return nil }
            let key: KeyStroke.Key
            switch name {
            case "space": key = .space
            case "tab": key = .tab
            case "up": key = .up
            case "down": key = .down
            case "left": key = .left
            case "right": key = .right
            case "character":
                guard case .object(let fields) = value, case .string(let text)? = fields["_0"], text.count == 1, let character = text.first else { return nil }
                // 今の表では，英字でない文字の Shift は文字に含める(KeyStroke.init(_:))
                return KeyStroke(.character(text.lowercased()), shift: shift && character.isLetter, control: control, option: option)
            default: return nil
            }
            return KeyStroke(key, shift: shift, control: control, option: option)
        }
    }

    /// バージョン 2 の操作と，表で置き換える状態とコマンド
    private static let oldCommands: [String: (KeymapState, KeymapCommand)] = [
        "openSettings": (.anywhere, .openSettings),
        "toggleLiveConversion": (.anywhere, .toggleLiveConversion),
        "handwriting": (.anywhere, .handwriting),
        "nextCandidate": (.converting, .nextCandidate),
        "previousCandidate": (.converting, .previousCandidate),
        "nextSegment": (.converting, .nextSegment),
        "previousSegment": (.converting, .previousSegment),
        "nextUncertainSegment": (.converting, .nextUncertainSegment),
        "previousUncertainSegment": (.converting, .previousUncertainSegment),
        "extendSegment": (.converting, .extendSegment),
        "shrinkSegment": (.converting, .shrinkSegment),
        "extendSegmentToWord": (.converting, .extendSegmentToWord),
        "shrinkSegmentToWord": (.converting, .shrinkSegmentToWord),
        "insertBoundary": (.composing, .insertBoundary),
        "splitSegment": (.converting, .splitSegment),
    ]

    /// バージョン 2 の既定の割り当て．既定から変えていない操作は，今の表の行をそのまま使う
    private static let oldDefaults: [String: [KeyStroke]] = [
        "openSettings": [KeyStroke(.character(","), control: true, option: true)],
        "toggleLiveConversion": [KeyStroke(.character("l"), control: true, option: true)],
        "handwriting": [KeyStroke(.character("h"), control: true, option: true)],
        "nextCandidate": [KeyStroke(.down), KeyStroke(.space)],
        "previousCandidate": [KeyStroke(.up), KeyStroke(.space, shift: true)],
        "nextSegment": [KeyStroke(.right)],
        "previousSegment": [KeyStroke(.left)],
        "nextUncertainSegment": [KeyStroke(.tab)],
        "previousUncertainSegment": [KeyStroke(.tab, shift: true)],
        "extendSegment": [KeyStroke(.right, shift: true)],
        "shrinkSegment": [KeyStroke(.left, shift: true)],
        "extendSegmentToWord": [KeyStroke(.right, shift: true, control: true)],
        "shrinkSegmentToWord": [KeyStroke(.left, shift: true, control: true)],
        "insertBoundary": [KeyStroke(.space, option: true)],
        "splitSegment": [KeyStroke(.down, shift: true)],
    ]

    /// 既定から変えた操作ごとに，その状態のそのコマンドの行を古い割り当ての行で置き換える
    private static func apply(_ bindings: OldBindings, to keymap: inout Keymap) {
        for (name, strokes) in bindings.commands.sorted(by: { $0.key < $1.key }) {
            guard let (state, command) = oldCommands[name] else { continue }
            let strokes = strokes.compactMap(\.stroke)
            guard Set(strokes) != Set(oldDefaults[name] ?? []) else { continue }
            // いつでも の行は，移し替える状態のぶんだけを外し，ほかの状態の行に分ける(入力中の ↓ で変換を始める行などを残す)
            keymap.entries = keymap.entries.flatMap { entry -> [KeymapEntry] in
                guard state != .anywhere, entry.state == .anywhere, entry.command == command else { return [entry] }
                return KeymapState.concrete.filter { $0 != state && command.states.contains($0) }.map { KeymapEntry($0, entry.stroke, command) }
            }
            // バージョン 2 では，同じキーは 1 つの操作にしか割り当てられない．表でも同じ状態の同じキーの行は置き換える
            replace(in: &keymap, with: strokes.map { KeymapEntry(state, $0, command) }) { entry in
                entry.state == state && (entry.command == command || strokes.contains(entry.stroke))
            }
        }
    }

    /// shouldRemove に当たる行を消し，最初に消した行の位置に rows を入れる(消した行が無ければ末尾)
    private static func replace(in keymap: inout Keymap, with rows: [KeymapEntry], where shouldRemove: (KeymapEntry) -> Bool) {
        let position = keymap.entries.firstIndex(where: shouldRemove) ?? keymap.entries.count
        let before = keymap.entries[..<position].filter { !shouldRemove($0) }
        let after = keymap.entries[position...].filter { !shouldRemove($0) }
        keymap.entries = Array(before) + rows + Array(after)
    }

    // MARK: 切り替えのキー(modeKeys)

    private static let modeKeyStrokes: [String: KeyStroke.Key] = [
        "eisu": .eisu, "kana": .kana, "hankakuZenkaku": .hankakuZenkaku, "henkan": .henkan, "muhenkan": .muhenkan,
    ]

    /// バージョン 2 の値と，表のコマンド．使わない(none)は nil
    private static let modeCommands: [String: KeymapCommand?] = ["toggle": .toggleMode, "japanese": .japaneseMode, "direct": .directMode, "none": nil]

    /// バージョン 2 の既定．既定から変えていないキーは，今の表の行をそのまま使う
    private static let oldModeDefaults = ["eisu": "direct", "kana": "japanese", "hankakuZenkaku": "toggle", "henkan": "none", "muhenkan": "none"]

    /// 切り替え・日本語・英数 はそのキーの いつでも の行にする．バージョン 2 では切り替えのキーがほかの働きより先に効いたので，
    /// そのキーのほかの行は消す．使わない ならそのキーの切り替えの行を消す(変換・無変換はふつうの働きの行が残る)
    private static func apply(_ assignments: [String: String], to keymap: inout Keymap) {
        for (name, action) in assignments.sorted(by: { $0.key < $1.key }) where oldModeDefaults[name] != action {
            guard let key = modeKeyStrokes[name], let command = modeCommands[action] else { continue }
            let stroke = KeyStroke(key)
            if let command {
                replace(in: &keymap, with: [KeymapEntry(.anywhere, stroke, command)]) { $0.stroke == stroke }
            } else {
                keymap.entries.removeAll { $0.stroke == stroke && $0.command.changesMode }
            }
        }
    }

    // MARK: JSON

    private static func decode<Value: Decodable>(_ type: Value.Type, from value: JSONValue) -> Value? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode(_ keymap: Keymap) -> JSONValue? {
        guard let data = try? JSONEncoder().encode(keymap) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}
