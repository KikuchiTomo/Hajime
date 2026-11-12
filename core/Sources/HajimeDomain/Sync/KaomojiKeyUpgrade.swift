/// 顔文字のパレットを開くキー(⌃⌥F．F は face)を，バージョン 10 までに保存したキー設定の表に足す(SettingsSchema のバージョン 10 → 11)．
///
/// - 標準のひな形のまま保存した表は，今の標準の表にする
/// - 利用者が変えた表は，顔文字のパレットのキーが無く，どの状態でもそのキーが空いていれば足す．利用者の決めたキーは変えない
enum KaomojiKeyUpgrade {
    static func upgrade(_ object: inout [String: JSONValue]) {
        // 表を書いていない設定は，読むときに今の標準の表になる
        guard let value = object["keymap"], let keymap = LegacyKeySettings.decode(Keymap.self, from: value) else { return }
        guard let upgraded = LegacyKeySettings.encode(upgraded(keymap)) else { return }
        object["keymap"] = upgraded
    }

    static func upgraded(_ keymap: Keymap) -> Keymap {
        PaletteKeyUpgrade.adding(added, to: keymap, previousStandard: previousStandard)
    }

    /// バージョン 11 で標準の表(ひな形のすべてに共通の行)に足した行
    static var added: [KeymapEntry] {
        KeymapPreset.standard.keymap.entries.filter { $0.command == .kaomojiPalette }
    }

    /// バージョン 10 の標準の表．バージョン 11 の標準の表から足した行を除いたもの
    static var previousStandard: Keymap {
        Keymap(HidePredictionKeyUpgrade.previousStandard.entries.filter { !added.contains($0) })
    }
}
