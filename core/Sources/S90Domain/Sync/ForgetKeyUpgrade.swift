/// 「学習から消す」のキーを，バージョン 7 までに保存したキー設定の表に足す(SettingsSchema のバージョン 7 → 8)．
///
/// 標準の表に学習から消すキーが無く，誤った変換を一度確定すると利用者が消す方法が無かった．変換中の ⌃⌫(Ctrl+Backspace)にする
/// - 標準のひな形のまま保存した表は，今の標準の表にする
/// - 利用者が変えた表は，学習から消すキーが無く，変換中にそのキーが空いていれば足す．利用者の決めたキーは変えない
enum ForgetKeyUpgrade {
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
        guard !keymap.entries.contains(where: { $0.command == .forgetCandidate }) else { return result }
        for entry in added where keymap.command(for: entry.stroke, in: entry.state) == nil {
            result.entries.append(entry)
        }
        return result
    }

    /// バージョン 8 で標準の表に足した行
    static let added: [KeymapEntry] = [KeymapEntry(.converting, KeyStroke(.backspace, control: true), .forgetCandidate)]

    /// バージョン 7 の標準の表．今の標準の表から足した行を除いたもの
    static var previousStandard: Keymap {
        Keymap(KeymapPreset.standard.keymap.entries.filter { !added.contains($0) })
    }
}
