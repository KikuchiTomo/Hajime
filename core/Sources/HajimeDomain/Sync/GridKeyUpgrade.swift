/// 候補を表に広げるキーを，バージョン 17 までに保存したキー設定の表に足す(SettingsSchema のバージョン 17 → 18)．
///
/// - ひな形のまま保存した表は，今のそのひな形の表にする(標準は変換中の ⌥↓，Windows 風・Mac 風・ATOK 風は変換中の Tab)
/// - 利用者が変えた表は，表に広げるキーが無く，変換中に標準のキーが空いていれば足す．利用者の決めたキーは変えない
enum GridKeyUpgrade {
    static func upgrade(_ object: inout [String: JSONValue]) {
        // 表を書いていない設定は，読むときに今の標準の表になる
        guard let value = object["keymap"], let keymap = LegacyKeySettings.decode(Keymap.self, from: value) else { return }
        guard let upgraded = LegacyKeySettings.encode(upgraded(keymap)) else { return }
        object["keymap"] = upgraded
    }

    static func upgraded(_ keymap: Keymap) -> Keymap {
        if let preset = KeymapPreset.allCases.first(where: { previous($0).entries == keymap.entries }) {
            var current = preset.keymap
            current.unknownEntries = keymap.unknownEntries
            return current
        }
        var result = keymap
        guard !keymap.entries.contains(where: { $0.command == .expandCandidates }) else { return result }
        for entry in added(to: .standard) where keymap.command(for: entry.stroke, in: entry.state) == nil {
            result.entries.append(entry)
        }
        return result
    }

    /// バージョン 18 でひな形に足した行
    static func added(to preset: KeymapPreset) -> [KeymapEntry] {
        preset.keymap.entries.filter { $0.command == .expandCandidates }
    }

    /// バージョン 17 のひな形の表．今のひな形の表から足した行を除いたもの
    static func previous(_ preset: KeymapPreset) -> Keymap {
        Keymap(SegmentJumpKeyUpgrade.previous(preset).entries.filter { $0.command != .expandCandidates })
    }
}
