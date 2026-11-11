import HajimeApplication
import HajimeDomain

/// 候補ウィンドウの足元のキーの案内(Windows)．文言とコマンドの並びは macOS と同じ表(IndicatorLabels)．
/// キーはキー設定の表で，変換中にそのコマンドに割り当てた最初のキー(R-17)．キーの案内を出さない設定なら空
public enum FooterHints {
    /// 分岐図の足元の案内．連想の一覧では，単語を選ぶ・意味を移る・戻るだけを案内する
    public static func make(for panel: LatticePanel, settings: Settings) -> [WireKeyHint] {
        guard settings.showsKeyHints else { return [] }
        if let split = panel.columns.first(where: \.isFocused)?.split, panel.association == nil {
            return splitHints(count: split.pieces.count - 1)
        }
        return make(panel.association == nil ? IndicatorLabels.branchHints : IndicatorLabels.associationHints, keymap: settings.keymap)
    }

    /// 一覧の足元の案内
    public static func make(for panel: CandidatePanel, settings: Settings) -> [WireKeyHint] {
        guard settings.showsKeyHints else { return [] }
        return make(IndicatorLabels.listHints(for: panel), keymap: settings.keymap)
    }

    private static func make(_ table: [IndicatorLabels.Hint], keymap: Keymap) -> [WireKeyHint] {
        table.map { hint in
            let strokes = hint.strokes(in: keymap)
            let first = strokes.first.map(label(of:)) ?? ""
            return WireKeyHint(keys: hint.second == nil ? first : pair(first, strokes.second.map(label(of:)) ?? ""), label: hint.label)
        }
        .filter { !$0.keys.isEmpty }
    }

    /// 文節を区切っているとき(区切る位置を番号キーで選ぶ)の案内．枝を出さないので区切る操作だけ
    public static func splitHints(count: Int) -> [WireKeyHint] {
        IndicatorLabels.splitHints(count: count).map { WireKeyHint(keys: $0.key, label: $0.label) }
    }

    public static func label(of stroke: KeyStroke) -> String {
        stroke.label(style: .windows)
    }

    public static func pair(_ first: String, _ second: String) -> String {
        let arrows: Set<Character> = ["←", "→"]
        if let a = first.last, let b = second.last, arrows.contains(a), arrows.contains(b), first.dropLast() == second.dropLast() {
            return String(first.dropLast()) + "←→"
        }
        return [first, second].filter { !$0.isEmpty }.joined(separator: IndicatorLabels.keySeparator)
    }
}
