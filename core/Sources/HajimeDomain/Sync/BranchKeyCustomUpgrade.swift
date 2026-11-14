/// 利用者が変えた表でも，矢印の行が標準の系統(標準・Emacs 風・Vim 風)のままなら，変換中の → を「候補の先の枝へ移る」(`enterBranch`)に替える
/// (SettingsSchema のバージョン 20 → 21)．
///
/// バージョン 19 → 20(BranchKeyUpgrade)は，ひな形と同じ表だけを替えた．古いバージョンで Emacs 風などを読み込んだ表は，
/// あとからひな形に足した行(変換中の Esc・F6〜F8)を持たないので，どのひな形とも一致せず，→ が次の文節のまま残った．
/// その表では矢印で分岐図の木をたどれず，先の枝の丸が出ているのに → で入れない．
///
/// - 表に `enterBranch` の行が 1 つも無く，変換中の → が次の文節，← が前の文節，Tab が次の文節のときだけ，→ を替える
///   (標準の系統の印．次の文節へは Tab で移れる)
/// - Windows 風・Mac 風・ATOK 風から作った表は，変換中の Tab がほかの操作なので替わらない．→ か ← か Tab を利用者が変えた表も替えない
/// - ほかの行は変えない
enum BranchKeyCustomUpgrade {
    static func upgrade(_ object: inout [String: JSONValue]) {
        // 表を書いていない設定は，読むときに今の標準の表になる
        guard let value = object["keymap"], let keymap = LegacyKeySettings.decode(Keymap.self, from: value) else { return }
        guard let upgraded = LegacyKeySettings.encode(upgraded(keymap)) else { return }
        object["keymap"] = upgraded
    }

    static func upgraded(_ keymap: Keymap) -> Keymap {
        let right = KeyStroke(.right)
        guard !keymap.entries.contains(where: { $0.command == .enterBranch }),
              keymap.command(for: right, in: .converting) == .nextSegment,
              keymap.command(for: KeyStroke(.left), in: .converting) == .previousSegment,
              keymap.command(for: KeyStroke(.tab), in: .converting) == .nextSegment,
              let index = keymap.entries.firstIndex(where: { $0.state == .converting && $0.stroke == right && $0.command == .nextSegment })
        else { return keymap }
        var result = keymap
        result.entries[index] = KeymapEntry(.converting, right, .enterBranch)
        return result
    }
}
