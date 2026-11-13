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

    /// 分岐図で，操作する場所に置く案内(macOS の BranchView.hints(for:) と同じ表)．区切りは文節の境目の上，文字種は上の枝の先，
    /// 再入力・表形式は候補の下，展開は先の枝の先に置く．連想の一覧では候補の下に連想の操作，区切っているあいだは境目の上に区切る操作
    public static func placed(for panel: LatticePanel, settings: Settings) -> WireBranchHints? {
        guard settings.showsKeyHints else { return nil }
        if panel.association != nil {
            let hints = make(IndicatorLabels.associationHints, keymap: settings.keymap)
            // 先の枝の丸の中身として出しているときは，中身の下に置く．矢印だけで移る操作(まとまりの切り替え)は案内しない
            // (線のつながりで分かる．矢印は表示の向きに効く)
            if panel.detail != nil {
                return WireBranchHints(boundary: [], candidates: [], items: hints.filter { !isArrowOnly($0.keys) })
            }
            return WireBranchHints(boundary: [], candidates: hints)
        }
        if let split = panel.columns.first(where: \.isFocused)?.split {
            return WireBranchHints(boundary: splitHints(count: split.pieces.count - 1), candidates: [])
        }
        // 先の枝へ入るキー．候補にいるあいだと，先の枝を畳んでいるあいだ(表示項目を減らす設定)は，連想変換のキーを案内する．
        // 矢印だけで入れるときは案内しない(線のつながりで分かる)
        let expand = panel.collapsesDetail || (panel.detail != nil && panel.detail?.current == nil)
            ? make([IndicatorLabels.branchExpandHint], keymap: settings.keymap).first
            : panel.associationHint?.key.map { WireKeyHint(keys: $0, label: IndicatorLabels.branchExpandLabel) }
        return WireBranchHints(boundary: make(IndicatorLabels.branchBoundaryHints, keymap: settings.keymap),
                               variant: make([IndicatorLabels.branchVariantHint], keymap: settings.keymap).first,
                               candidates: make(IndicatorLabels.branchCandidateHints, keymap: settings.keymap),
                               expand: expand.flatMap { isArrowOnly($0.keys) ? nil : $0 })
    }

    /// 矢印だけのキー(修飾キーの付かない ← → ↑ ↓)か
    public static func isArrowOnly(_ keys: String) -> Bool {
        let arrows: Set<Character> = ["←", "→", "↑", "↓", "↔", "↕", " "]
        return !keys.isEmpty && keys.allSatisfy(arrows.contains)
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
