/// 予測の確定を取り消すキーを，バージョン 12 までに保存したキー設定の表に足す(SettingsSchema のバージョン 12 → 13)．
///
/// - ひな形のまま保存した表は，バージョン 13 のそのひな形の表にする(標準・Mac 風は入力文字なしの Backspace，Windows 風・ATOK 風は Ctrl+Backspace．
///   その先はあとの移し替えが今のひな形の表にする)
/// - 利用者が変えた表は，取り消すキーが無く，入力文字なしで標準のキーが空いていれば足す．利用者の決めたキーは変えない
enum PredictionUndoKeyUpgrade {
    static func upgrade(_ object: inout [String: JSONValue]) {
        // 表を書いていない設定は，読むときに今の標準の表になる
        guard let value = object["keymap"], let keymap = LegacyKeySettings.decode(Keymap.self, from: value) else { return }
        guard let upgraded = LegacyKeySettings.encode(upgraded(keymap)) else { return }
        object["keymap"] = upgraded
    }

    static func upgraded(_ keymap: Keymap) -> Keymap {
        if let preset = KeymapPreset.allCases.first(where: { previous($0).entries == keymap.entries }) {
            var current = UndoCommitKeyUpgrade.previous(preset)
            current.unknownEntries = keymap.unknownEntries
            return current
        }
        var result = keymap
        guard !keymap.entries.contains(where: { $0.command == .undoPrediction }) else { return result }
        for entry in added(to: .standard) where keymap.command(for: entry.stroke, in: entry.state) == nil {
            result.entries.append(entry)
        }
        return result
    }

    /// バージョン 13 でひな形に足した行
    static func added(to preset: KeymapPreset) -> [KeymapEntry] {
        UndoCommitKeyUpgrade.previous(preset).entries.filter { $0.command == .undoPrediction }
    }

    /// バージョン 12 のひな形の表．バージョン 13 のひな形の表から足した行を除いたもの
    static func previous(_ preset: KeymapPreset) -> Keymap {
        Keymap(UndoCommitKeyUpgrade.previous(preset).entries.filter { $0.command != .undoPrediction })
    }
}
