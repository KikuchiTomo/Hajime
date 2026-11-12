import AppKit

/// 候補の文字のすぐあとに添える控えめな説明(絵文字の名前．CandidatePanel.Entry.detail，LatticePanel.Column.alternativeDetails)．
/// 一覧(CandidateView)と分岐図(BranchView)で同じに描く．
/// 説明は札と同じ小さい文字で薄い色にする．候補の文字と 1 行の文字列にして描くので，文字の大きさが違ってもベースラインがそろう
@MainActor
enum CandidateDetailDrawing {
    private typealias Size = DesignTokens.Size.Candidate

    /// 説明の幅(候補の文字とのあいだを含む)．説明が無ければ 0
    static func width(_ detail: String?, font: NSFont) -> CGFloat {
        guard let detail, !detail.isEmpty else { return 0 }
        return Size.detailGap + detail.size(withAttributes: [.font: font]).width.rounded(.up)
    }

    /// 候補の文字と説明を 1 行の文字列にする．あいだは候補の最後の字の後ろの空き(字間)で取る
    static func line(_ text: String, attributes: [NSAttributedString.Key: Any], detail: String?,
                     detailAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let line = NSMutableAttributedString(string: text, attributes: attributes)
        guard let detail, !detail.isEmpty, !text.isEmpty else { return line }
        let last = (text as NSString).rangeOfComposedCharacterSequence(at: (text as NSString).length - 1)
        line.addAttribute(.kern, value: Size.detailGap, range: last)
        line.append(NSAttributedString(string: detail, attributes: detailAttributes))
        return line
    }

    /// 行の高さの真ん中に描く(候補の文字だけを描くときと同じベースラインになる)
    static func draw(_ line: NSAttributedString, x: CGFloat, in rect: NSRect) {
        TextFitting.draw(line, x: x, midY: rect.midY)
    }
}
