/// 単語の登録(Ctrl+F7)と入力メニュー(Ctrl+F10・Ctrl+変換)のキーを，バージョン 16 までに保存したキー設定の表に足す(SettingsSchema のバージョン 16 → 17)．
///
/// - ひな形のまま保存した表は，今のそのひな形の表にする
/// - 利用者が変えた表は，そのコマンドのキーが無く，どの状態でもキーが空いていれば足す．利用者の決めたキーは変えない
enum WordToolKeyUpgrade {
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
        for entry in added(to: .standard) where !keymap.entries.contains(where: { $0.command == entry.command })
            && KeymapState.concrete.allSatisfy({ keymap.command(for: entry.stroke, in: $0) == nil }) {
            result.entries.append(entry)
        }
        return result
    }

    /// バージョン 17 で足したコマンド
    static let commands: Set<KeymapCommand> = [.registerWord, .openMenu]

    /// バージョン 17 でひな形に足した行
    static func added(to preset: KeymapPreset) -> [KeymapEntry] {
        preset.keymap.entries.filter { commands.contains($0.command) }
    }

    /// バージョン 16 のひな形の表．今のひな形の表から足した行を除いたもの
    static func previous(_ preset: KeymapPreset) -> Keymap {
        Keymap(preset.keymap.entries.filter { !commands.contains($0.command) })
    }
}
