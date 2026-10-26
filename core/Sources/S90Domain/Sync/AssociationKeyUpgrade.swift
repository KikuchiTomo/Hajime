/// 連想変換(R-18)のキーを，バージョン 4 までに保存したキー設定の表に足す(SettingsSchema のバージョン 4 → 5)．
///
/// - 標準のひな形のまま保存した表は，今の標準の表にする(入力中の Shift+Space が 変換 から 連想変換 に変わる)
/// - 利用者が変えた表は，入力中と変換中の Ctrl+Tab が空いていれば 連想変換 を足す．利用者の決めたキーは変えない
enum AssociationKeyUpgrade {
    static func upgrade(_ object: inout [String: JSONValue]) {
        // 表を書いていない設定は，読むときに今の標準の表になる
        guard let value = object["keymap"], let keymap = LegacyKeySettings.decode(Keymap.self, from: value) else { return }
        guard let upgraded = LegacyKeySettings.encode(upgraded(keymap)) else { return }
        object["keymap"] = upgraded
    }

    static func upgraded(_ keymap: Keymap) -> Keymap {
        if keymap.entries == previousStandard.entries {
            var standard = KeymapPreset.standard.keymap
            standard.unknownEntries = keymap.unknownEntries
            return standard
        }
        var result = keymap
        guard !keymap.entries.contains(where: { $0.command == .associate }) else { return result }
        for state in [KeymapState.composing, .converting] where keymap.command(for: controlTab, in: state) == nil {
            result.entries.append(KeymapEntry(state, controlTab, .associate))
        }
        return result
    }

    private static let controlTab = KeyStroke(.tab, control: true)

    /// バージョン 4 までの標準の表．今の標準の表から連想変換の行を除き，入力中の Shift+Space を 変換 に戻したもの
    static var previousStandard: Keymap {
        Keymap(KeymapPreset.standard.keymap.entries.compactMap { entry in
            guard entry.command == .associate else { return entry }
            return entry.state == .composing && entry.stroke == KeyStroke(.space, shift: true) ? KeymapEntry(.composing, entry.stroke, .convert) : nil
        })
    }
}
