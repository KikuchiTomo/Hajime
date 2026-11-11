/// 変換中のキーを，バージョン 8 までに保存したキー設定の表に足す(SettingsSchema のバージョン 8 → 9)．
///
/// 標準の表に，変換中の次の行を足した
/// - PageDown・PageUp で候補のページを送る，Home・End で先頭・末尾の文節へ移る
/// - F6〜F8 で選んでいる文節だけをひらがな・全角カタカナ・半角カタカナにする(F9・F10 と入力中は全文のまま)
/// - Esc で直前の候補の選択や文節の区切りの変更を取り消す(続けて押すと全文を読みに戻す)
/// - Delete で読みに戻して末尾から打ち続ける
///
/// 標準のひな形のまま保存した表は，今の標準の表にする．利用者が変えた表は，足した行のうち変換中にキーが空いているものだけ足す．
/// 利用者の決めたキーは変えない(F6〜F8 と Esc は いつでも の行で使っているので足さない)
enum ConversionKeysUpgrade {
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
        for entry in added where keymap.command(for: entry.stroke, in: entry.state) == nil {
            result.entries.append(entry)
        }
        return result
    }

    /// バージョン 9 で標準の表に足した行
    static let added: [KeymapEntry] = [
        KeymapEntry(.converting, KeyStroke(.pageDown), .nextCandidatePage),
        KeymapEntry(.converting, KeyStroke(.pageUp), .previousCandidatePage),
        KeymapEntry(.converting, KeyStroke(.home), .firstSegment),
        KeymapEntry(.converting, KeyStroke(.end), .lastSegment),
        KeymapEntry(.converting, KeyStroke(.function(6)), .segmentToHiragana),
        KeymapEntry(.converting, KeyStroke(.function(7)), .segmentToKatakana),
        KeymapEntry(.converting, KeyStroke(.function(8)), .segmentToHalfwidthKatakana),
        KeymapEntry(.converting, KeyStroke(.escape), .undoConversionEdit),
        KeymapEntry(.converting, KeyStroke(.delete), .resumeEditing),
    ]

    /// バージョン 8 の標準の表．今の標準の表から足した行を除いたもの
    static var previousStandard: Keymap {
        Keymap(KeymapPreset.standard.keymap.entries.filter { !added.contains($0) })
    }
}
