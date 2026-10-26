import S90Application
import S90Domain

public enum BranchHints {
    public static func make(for panel: LatticePanel, settings: Settings) -> [WireKeyHint] {
        guard settings.showsKeyHints else { return [] }
        let keymap = settings.keymap
        func first(_ command: KeymapCommand) -> String {
            keymap.strokes(for: command, in: .converting).first.map(label(of:)) ?? ""
        }
        let focused = panel.columns.first(where: \.isFocused)
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
            WireKeyHint(keys: pair(first(.shrinkSegmentToWord), first(.extendSegmentToWord)), label: "語ごと"),
            WireKeyHint(keys: first(.splitSegment), label: "区切る"),
        ]
        return hints.filter { !$0.keys.isEmpty }
    }

    public static func label(of stroke: KeyStroke) -> String {
        var parts: [String] = []
        if stroke.control { parts.append("Ctrl") }
        if stroke.option { parts.append("Alt") }
        if stroke.shift { parts.append("Shift") }
        parts.append(name(of: stroke.key))
        return parts.joined(separator: "+")
    }

    private static func name(of key: KeyStroke.Key) -> String {
        switch key {
        case .character(let text): text.uppercased()
        case .space: "Space"
        case .enter: "Enter"
        case .tab: "Tab"
        case .backspace: "BS"
        case .delete: "Del"
        case .escape: "Esc"
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        case .home: "Home"
        case .end: "End"
        case .pageUp: "PgUp"
        case .pageDown: "PgDn"
        case .function(let number): "F\(number)"
        case .eisu: "英数"
        case .kana: "かな"
        case .hankakuZenkaku: "半角/全角"
        case .henkan: "変換"
        case .muhenkan: "無変換"
        }
    }

    public static func pair(_ first: String, _ second: String) -> String {
        let arrows: Set<Character> = ["←", "→"]
        if let a = first.last, let b = second.last, arrows.contains(a), arrows.contains(b), first.dropLast() == second.dropLast() {
            return String(first.dropLast()) + "←→"
        }
        return [first, second].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
