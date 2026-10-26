import S90Application
import S90Domain

public enum BranchHints {
    public static func make(for panel: LatticePanel, settings: Settings) -> [WireKeyHint] {
        guard settings.showsKeyHints else { return [] }
        let keymap = settings.keymap
        func first(_ command: KeymapCommand) -> String {
            keymap.strokes(for: command, in: .converting).first.map(label(of:)) ?? ""
        }
        // 文言とコマンドの並びは macOS と同じ表(IndicatorLabels)．連想の一覧では，単語を選ぶ・意味を移る・戻るだけを案内する
        if let split = panel.columns.first(where: \.isFocused)?.split, panel.association == nil {
            return splitHints(count: split.pieces.count - 1)
        }
        let table = panel.association == nil ? IndicatorLabels.branchHints : IndicatorLabels.associationHints
        return table.map { hint in
            WireKeyHint(keys: hint.second.map { pair(first(hint.first), first($0)) } ?? first(hint.first), label: hint.label)
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
        return [first, second].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
