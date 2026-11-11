import AppKit
import HajimeDomain

/// 語の意味と同音異義語の使い分けの欄(R-08)を描く．一覧(CandidateView)と分岐図(BranchView)で同じ形にする．
/// 意味ごとに 1 行を使い，最初の行の頭に語(強く)を置いて，意味と使い方の例(控えめ)を語の後ろにそろえて並べる．
/// 意味が 2 つ以上なら番号を付ける．同じ読みのほかの語があれば，最後の行に「ほかに」とその札を並べる．
/// 欄の幅は usageMaxWidth までにし，入らない分は例，意味の順に省く(意味が長くても窓を広げすぎない)
@MainActor
enum HomophoneDrawing {
    private typealias Glass = DesignTokens.Size.Glass

    /// 欄の高さ(上下の余白を含む)．意味の行と，ほかの語があればその行
    static func height(_ note: HomophoneNote) -> CGFloat {
        Glass.usageRowHeight * CGFloat(rowCount(note)) + Glass.usagePaddingY * 2
    }

    /// 欄に要る幅(左右の余白を除く)．usageMaxWidth を超えない
    static func width(_ note: HomophoneNote, theme: ResolvedTheme, font: NSFont) -> CGFloat {
        let lead = width(of: note.word, font: emphasis(theme, font)) + Glass.noteGap
        let senses = note.senses.enumerated().map { index, sense in
            lead + numberWidth(note, index: index, font: font) + width(of: sense.meaning, font: font)
                + (sense.example.map { Glass.noteGap + width(of: example($0), font: font) } ?? 0)
        }
        let others = note.others.isEmpty ? 0 : width(of: UIStrings.Candidate.homophoneOthers, font: font)
            + note.others.reduce(0) { $0 + Glass.usageTagGap + NoteDrawing.tagWidth($1, theme: theme) }
        return min(max(senses.max() ?? 0, others), Glass.usageMaxWidth).rounded(.up)
    }

    static func draw(_ note: HomophoneNote, in rect: NSRect, theme: ResolvedTheme, font: NSFont) {
        let strong: [NSAttributedString.Key: Any] = [.font: emphasis(theme, font), .foregroundColor: theme.text]
        let plain: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.text]
        let muted: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.textMuted]
        func row(_ index: Int) -> NSRect {
            NSRect(x: rect.minX, y: rect.minY + Glass.usagePaddingY + Glass.usageRowHeight * CGFloat(index), width: rect.width, height: Glass.usageRowHeight)
        }

        // 意味の行: 語の後ろに番号・意味・例．入らなければ例を省き，それでも入らなければ意味を「…」で切る
        let lead = rect.minX + drawText(note.word, attributes: strong, x: rect.minX, in: row(0)) + Glass.noteGap
        for (index, sense) in note.senses.enumerated() {
            let line = row(index)
            var x = lead
            if note.senses.count > 1 { x += drawText(UIStrings.Candidate.senseNumber(index + 1), attributes: muted, x: x, in: line) + Glass.noteGap }
            let available = line.maxX - x
            let meaningWidth = width(of: sense.meaning, font: font)
            let example = sense.example.map(example)
            let exampleFits = example.map { meaningWidth + Glass.noteGap + width(of: $0, font: font) <= available } ?? false
            x += drawText(truncated(sense.meaning, attributes: plain, width: available), attributes: plain, x: x, in: line)
            if let example, exampleFits { _ = drawText(example, attributes: muted, x: x + Glass.noteGap, in: line) }
        }

        // ほかの語の行: ほかに＋札．入らない札は「+n」にまとめる
        guard !note.others.isEmpty else { return }
        let bottom = row(note.senses.count)
        var x = bottom.minX + drawText(UIStrings.Candidate.homophoneOthers, attributes: muted, x: bottom.minX, in: bottom)
        for (index, word) in note.others.enumerated() {
            let tag = NoteDrawing.tagWidth(word, theme: theme)
            let rest = note.others.count - index - 1
            let reserve = rest > 0 ? Glass.usageTagGap + width(of: UIStrings.Candidate.more(rest), font: font) : 0
            if x + Glass.usageTagGap + tag + reserve > bottom.maxX {
                _ = drawText(UIStrings.Candidate.more(note.others.count - index), attributes: muted, x: x + Glass.usageTagGap, in: bottom)
                break
            }
            x += Glass.usageTagGap + tag
            NoteDrawing.drawTag(word, maxX: x, midY: bottom.midY, theme: theme, selected: false)
        }
    }

    private static func rowCount(_ note: HomophoneNote) -> Int { note.senses.count + (note.others.isEmpty ? 0 : 1) }

    /// 意味の番号と後ろの間の幅．意味が 1 つなら番号を付けない
    private static func numberWidth(_ note: HomophoneNote, index: Int, font: NSFont) -> CGFloat {
        note.senses.count > 1 ? width(of: UIStrings.Candidate.senseNumber(index + 1), font: font) + Glass.noteGap : 0
    }

    private static func emphasis(_ theme: ResolvedTheme, _ font: NSFont) -> NSFont { theme.emphasisFont(size: font.pointSize) }

    private static func example(_ text: String) -> String { "「\(text)」" }

    private static func width(of text: String, font: NSFont) -> CGFloat { text.size(withAttributes: [.font: font]).width }

    /// 縦に中央にそろえて描き，描いた幅を返す．座標は整数に丸め，文字の輪郭をぼかさない
    private static func drawText(_ text: String, attributes: [NSAttributedString.Key: Any], x: CGFloat, in rect: NSRect) -> CGFloat {
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: x.rounded(), y: rect.minY + ((rect.height - size.height) / 2).rounded()), withAttributes: attributes)
        return size.width
    }

    private static func truncated(_ text: String, attributes: [NSAttributedString.Key: Any], width: CGFloat) -> String {
        guard text.size(withAttributes: attributes).width > width else { return text }
        var characters = Array(text)
        while !characters.isEmpty, (String(characters) + "…").size(withAttributes: attributes).width > width { characters.removeLast() }
        return characters.isEmpty ? "" : String(characters) + "…"
    }
}
