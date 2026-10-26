import S90Application
import S90Domain

public enum BranchHints {
    public static func make(for panel: LatticePanel, settings: Settings) -> [WireKeyHint] {
        guard settings.showsKeyHints else { return [] }
        let keymap = settings.keymap
        func first(_ command: KeymapCommand) -> String {
            keymap.strokes(for: command, in: .converting).first.map(label(of:)) ?? ""
        }
        // 連想の一覧では，単語を選ぶ・意味を移る・戻るだけを案内する(macOS の UIStrings.Association.hints と同じ)
        if panel.association != nil {
            return [
                WireKeyHint(keys: first(.nextCandidate), label: "選択"),
                WireKeyHint(keys: pair(first(.previousSegment), first(.nextSegment)), label: "意味"),
                WireKeyHint(keys: first(.cancel), label: "戻る"),
            ].filter { !$0.keys.isEmpty }
        }
        let focused = panel.columns.first(where: \.isFocused)
        if let split = focused?.split {
            return splitHints(count: split.pieces.count - 1)
        }
        let length: [WireKeyHint]
        if focused?.shorter == nil, focused?.longer == nil {
            length = [WireKeyHint(keys: pair(first(.shrinkSegment), first(.extendSegment)), label: "文節の長さ")]
        } else {
            length = [
                focused?.shorter.map { WireKeyHint(keys: first(.shrinkSegment), label: $0) },
                focused?.longer.map { WireKeyHint(keys: first(.extendSegment), label: $0) },
            ].compactMap { $0 }
        }
        let hints = [
            WireKeyHint(keys: first(.nextCandidate), label: "候補"),
            WireKeyHint(keys: first(.previousCandidate), label: "文字種"),
            WireKeyHint(keys: pair(first(.previousSegment), first(.nextSegment)), label: "文節"),
            WireKeyHint(keys: first(.nextUncertainSegment), label: "次の文節"),
        ] + length + [
            WireKeyHint(keys: pair(first(.shrinkSegmentToWord), first(.extendSegmentToWord)), label: "単語ごと"),
            WireKeyHint(keys: first(.splitSegment), label: "区切る"),
        ]
        return hints.filter { !$0.keys.isEmpty }
    }

    /// 文節を区切っているとき(区切る位置を番号キーで選ぶ)の案内．枝を出さないので区切る操作だけ
    public static func splitHints(count: Int) -> [WireKeyHint] {
        [WireKeyHint(keys: count > 1 ? "1–\(count)" : "1", label: "区切り"), WireKeyHint(keys: "Esc", label: "取消")]
    }

    /// Windows の候補ウィンドウに出すキーの名前(「Ctrl+Tab」)
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
