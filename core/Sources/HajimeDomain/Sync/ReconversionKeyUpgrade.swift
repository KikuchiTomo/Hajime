/// 再変換のキーを，バージョン 5 までに保存したキー設定の表に足す(SettingsSchema のバージョン 5 → 6)．
///
/// - 標準のひな形のまま保存した表は，今の標準の表にする
/// - 利用者が変えた表は，入力文字なしの状態でそのキーが空いていれば 再変換 を足す．利用者の決めたキーは変えない
enum ReconversionKeyUpgrade {
    static func upgrade(_ object: inout [String: JSONValue]) {
        // 表を書いていない設定は，読むときに今の標準の表になる
        guard let value = object["keymap"], let keymap = LegacyKeySettings.decode(Keymap.self, from: value) else { return }
        guard let upgraded = LegacyKeySettings.encode(upgraded(keymap)) else { return }
        object["keymap"] = upgraded
    }

    static func upgraded(_ keymap: Keymap) -> Keymap {
        if keymap.entries == previousStandard.entries {
            // バージョン 6 の標準の表にし，あとの移し替え(NavigationKeyUpgrade)で今の標準の表にする
            var standard = NavigationKeyUpgrade.previousStandard
            standard.unknownEntries = keymap.unknownEntries
            return standard
        }
        var result = keymap
        guard !keymap.entries.contains(where: { $0.command == .reconvert }) else { return result }
        for entry in added where keymap.command(for: entry.stroke, in: entry.state) == nil {
            result.entries.append(entry)
        }
        return result
    }

    /// バージョン 6 で標準の表に足した行
    static var added: [KeymapEntry] {
        NavigationKeyUpgrade.previousStandard.entries.filter { $0.command == .reconvert }
    }

    /// バージョン 5 の標準の表．バージョン 6 の標準の表から再変換の行を除いたもの
    static var previousStandard: Keymap {
        Keymap(NavigationKeyUpgrade.previousStandard.entries.filter { $0.command != .reconvert })
    }
}
