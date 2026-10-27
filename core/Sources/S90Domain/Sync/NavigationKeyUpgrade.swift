/// 変換中の Tab と連想変換のキーを，バージョン 6 までに保存したキー設定の表で変える(SettingsSchema のバージョン 6 → 7)．
///
/// - 変換中の Tab・Shift+Tab を，誤りやすい文節への移動から → ・ ← と同じ文節の移動にする．誤りやすい文節へは Option+→・Option+← で移る
/// - 連想変換の Ctrl+Tab はアプリのタブの切り替えとぶつかるので外し，変換中は Shift+↑ にする(入力中は Shift+Space のまま)
///
/// 標準のひな形のまま保存した表は，今の標準の表にする．利用者が変えた表は，前の標準と同じ行だけを変え，
/// 新しいキーが空いているときだけ足す．利用者の決めたキーは変えない
enum NavigationKeyUpgrade {
    static func upgrade(_ object: inout [String: JSONValue]) {
        // 表を書いていない設定は，読むときに今の標準の表になる
        guard let value = object["keymap"], let keymap = LegacyKeySettings.decode(Keymap.self, from: value) else { return }
        guard let upgraded = LegacyKeySettings.encode(upgraded(keymap)) else { return }
        object["keymap"] = upgraded
    }

    /// 前の行と，置き換える行(nil なら外す)．標準の表での置き換え
    private static let replacements: [(old: KeymapEntry, new: KeymapEntry?)] = [
        (KeymapEntry(.converting, KeyStroke(.tab), .nextUncertainSegment), KeymapEntry(.converting, KeyStroke(.tab), .nextSegment)),
        (KeymapEntry(.converting, KeyStroke(.tab, shift: true), .previousUncertainSegment),
         KeymapEntry(.converting, KeyStroke(.tab, shift: true), .previousSegment)),
        (KeymapEntry(.composing, KeyStroke(.tab, control: true), .associate), nil),
        (KeymapEntry(.converting, KeyStroke(.tab, control: true), .associate), KeymapEntry(.converting, KeyStroke(.up, shift: true), .associate)),
    ]

    private static let optionUp = KeyStroke(.up, option: true)

    /// 新しく足した行(誤りやすい文節へ移るキー)
    private static let added: [KeymapEntry] = [
        KeymapEntry(.converting, KeyStroke(.right, option: true), .nextUncertainSegment),
        KeymapEntry(.converting, KeyStroke(.left, option: true), .previousUncertainSegment),
    ]

    static func upgraded(_ keymap: Keymap) -> Keymap {
        if keymap.entries == previousStandard.entries {
            var standard = KeymapPreset.standard.keymap
            standard.unknownEntries = keymap.unknownEntries
            return standard
        }
        var result = keymap
        for (old, new) in replacements {
            guard let index = result.entries.firstIndex(of: old) else { continue }
            // 新しいキーがふさがっていれば(Windows 風・Mac 風の Shift+↑ など)，ひな形と同じ Option+↑ を試す
            let candidates = [new, old.command == .associate ? KeymapEntry(old.state, optionUp, .associate) : nil].compactMap { $0 }
            if let free = candidates.first(where: { $0.stroke == old.stroke || result.command(for: $0.stroke, in: $0.state) == nil }) {
                result.entries[index] = free
            } else {
                result.entries.remove(at: index)
            }
        }
        for entry in added where result.command(for: entry.stroke, in: entry.state) == nil {
            result.entries.append(entry)
        }
        return result
    }

    /// バージョン 6 の標準の表．今の標準の表の行を前の行に戻し，足した行を除き，外した行(入力中の Ctrl+Tab)を元の位置に戻したもの
    static var previousStandard: Keymap {
        var entries: [KeymapEntry] = []
        for entry in ForgetKeyUpgrade.previousStandard.entries where !added.contains(entry) {
            entries.append(replacements.first { $0.new == entry }?.old ?? entry)
            // 入力中の Ctrl+Tab は，入力中の Shift+Space(連想変換)のすぐあとにあった
            if entry == KeymapEntry(.composing, KeyStroke(.space, shift: true), .associate) {
                entries.append(KeymapEntry(.composing, KeyStroke(.tab, control: true), .associate))
            }
        }
        return Keymap(entries)
    }
}
