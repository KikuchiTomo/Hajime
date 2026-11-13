/// 変換中の → を「次の文節」から「候補の先の枝へ移る」(`enterBranch`)に替える(SettingsSchema のバージョン 19 → 20)．
/// 矢印キーで分岐図の木をたどれるようにするため．次の文節へは Tab と，文節へ移るキーで移る．
///
/// - ひな形のまま保存した表は，今のそのひな形の表にする(→ を替えるのは標準・Emacs 風・Vim 風)
/// - 利用者が変えた表は変えない(利用者の決めたキーを変えない)．先の枝へは，連想変換のキーでも移れる
enum BranchKeyUpgrade {
    static func upgrade(_ object: inout [String: JSONValue]) {
        // 表を書いていない設定は，読むときに今の標準の表になる
        guard let value = object["keymap"], let keymap = LegacyKeySettings.decode(Keymap.self, from: value) else { return }
        guard let upgraded = LegacyKeySettings.encode(upgraded(keymap)) else { return }
        object["keymap"] = upgraded
    }

    static func upgraded(_ keymap: Keymap) -> Keymap {
        guard let preset = KeymapPreset.allCases.first(where: { previous($0).entries == keymap.entries }) else { return keymap }
        var current = preset.keymap
        current.unknownEntries = keymap.unknownEntries
        return current
    }

    /// バージョン 19 のひな形の表．今のひな形の表の，先の枝へ移るキーを次の文節に戻したもの
    static func previous(_ preset: KeymapPreset) -> Keymap {
        Keymap(preset.keymap.entries.map { $0.command == .enterBranch ? KeymapEntry($0.state, $0.stroke, .nextSegment) : $0 })
    }
}
