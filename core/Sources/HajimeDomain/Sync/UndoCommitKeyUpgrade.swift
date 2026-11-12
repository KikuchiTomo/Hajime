/// 確定を取り消すキーを，バージョン 15 までに保存したキー設定の表に足す(SettingsSchema のバージョン 15 → 16)．
///
/// - ひな形のまま保存した表は，今のそのひな形の表にする(どのひな形も入力文字なしの Ctrl+Backspace．
///   Windows 風・ATOK 風は，同じキーで予測の確定だけを取り消していた行を，予測も変換も取り消す行に替える)
/// - 利用者が変えた表は，確定を取り消すキーが無く，入力文字なしで標準のキーが空いていれば足す．利用者の決めたキーは変えない
enum UndoCommitKeyUpgrade {
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
        guard !keymap.entries.contains(where: { $0.command == .undoCommit }) else { return result }
        for entry in added(to: .standard) where keymap.command(for: entry.stroke, in: entry.state) == nil {
            result.entries.append(entry)
        }
        return result
    }

    /// バージョン 16 でひな形に足した行
    static func added(to preset: KeymapPreset) -> [KeymapEntry] {
        preset.keymap.entries.filter { $0.command == .undoCommit }
    }

    /// バージョン 15 のひな形の表．今のひな形の表から足した行を除いたもの．
    /// Windows 風・ATOK 風は，確定を取り消す行のキーで予測の確定だけを取り消していた
    static func previous(_ preset: KeymapPreset) -> Keymap {
        let undidPredictions = [KeymapPreset.windows, .atok].contains(preset)
        return Keymap(preset.keymap.entries.compactMap { entry in
            guard entry.command == .undoCommit else { return entry }
            return undidPredictions ? KeymapEntry(entry.state, entry.stroke, .undoPrediction) : nil
        })
    }
}
