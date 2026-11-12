/// 絵文字と記号のパレットを開くキーを，バージョン 9 までに保存したキー設定の表に足す(SettingsSchema のバージョン 9 → 10)．
///
/// - 標準のひな形のまま保存した表は，今の標準の表にする
/// - 利用者が変えた表は，パレットのキーが無く，いつでも の行でそのキーが空いていれば足す．利用者の決めたキーは変えない
enum PaletteKeyUpgrade {
    static func upgrade(_ object: inout [String: JSONValue]) {
        // 表を書いていない設定は，読むときに今の標準の表になる
        guard let value = object["keymap"], let keymap = LegacyKeySettings.decode(Keymap.self, from: value) else { return }
        guard let upgraded = LegacyKeySettings.encode(upgraded(keymap)) else { return }
        object["keymap"] = upgraded
    }

    static func upgraded(_ keymap: Keymap) -> Keymap {
        adding(added, to: keymap, previousStandard: previousStandard)
    }

    /// 標準のひな形のまま(previousStandard と同じ)なら今の標準の表にし，変えた表には，コマンドが無く
    /// どの状態でもキーが空いている行だけを足す．顔文字のパレットのキー(KaomojiKeyUpgrade)でも使う
    static func adding(_ added: [KeymapEntry], to keymap: Keymap, previousStandard: Keymap) -> Keymap {
        if keymap.entries == previousStandard.entries {
            var standard = KeymapPreset.standard.keymap
            standard.unknownEntries = keymap.unknownEntries
            return standard
        }
        var result = keymap
        for entry in added where !keymap.entries.contains(where: { $0.command == entry.command })
            && KeymapState.concrete.allSatisfy({ keymap.command(for: entry.stroke, in: $0) == nil }) {
            result.entries.append(entry)
        }
        return result
    }

    /// バージョン 10 で標準の表(ひな形のすべてに共通の行)に足した行
    static var added: [KeymapEntry] {
        KeymapPreset.standard.keymap.entries.filter { $0.command == .emojiPalette || $0.command == .symbolPalette }
    }

    /// バージョン 9 の標準の表．バージョン 10 の標準の表から足した行を除いたもの
    static var previousStandard: Keymap {
        Keymap(KaomojiKeyUpgrade.previousStandard.entries.filter { !added.contains($0) })
    }
}
