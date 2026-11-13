/// 分岐図の文節へ移るキー(⌥A・⌥S・⌥D・⌥F・⌥J・⌥K・⌥L・⌥;)を，バージョン 18 までに保存したキー設定の表に足す(SettingsSchema のバージョン 18 → 19)．
///
/// - ひな形のまま保存した表は，今のそのひな形の表にする(Mac 風は変換中の ⌥A・⌥S・⌥K をほかの操作に使うので，⇧⌥ と A・S・D・F・G・H・J・K)
/// - 利用者が変えた表は，文節へ移るキーが 1 つも無く，変換中に 8 つのキーがすべて空いていれば足す(一部だけを足すと，移れる文節と移れない文節ができる)．
///   利用者の決めたキーは変えない
enum SegmentJumpKeyUpgrade {
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
        let added = added(to: .standard)
        guard !keymap.entries.contains(where: { $0.command.segmentJumpIndex != nil }),
              added.allSatisfy({ keymap.command(for: $0.stroke, in: $0.state) == nil }) else { return result }
        result.entries.append(contentsOf: added)
        return result
    }

    /// バージョン 19 でひな形に足した行
    static func added(to preset: KeymapPreset) -> [KeymapEntry] {
        preset.keymap.entries.filter { $0.command.segmentJumpIndex != nil }
    }

    /// バージョン 18 のひな形の表．今のひな形の表から足した行を除いたもの
    static func previous(_ preset: KeymapPreset) -> Keymap {
        Keymap(BranchKeyUpgrade.previous(preset).entries.filter { $0.command.segmentJumpIndex == nil })
    }
}
