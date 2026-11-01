import AppKit
import HajimeDomain

/// コマンドの候補(R-22)の頭に置く種類のアイコンを描く．一覧(CandidateView)と分岐図(BranchView)で同じ形にする．
/// 文字を入れる候補と見分けられるよう，形(種類のアイコン)・色(アクセントの色)・言葉(行の右の「コマンド」の札)の 3 つで示す
@MainActor
enum CommandDrawing {
    private typealias Glass = DesignTokens.Size.Glass

    /// 種類ごとのアイコン(SF Symbols)
    static func symbol(for kind: LauncherCommand.Kind) -> String {
        switch kind {
        case .openApplication: "macwindow"
        case .openURL: "globe"
        case .openFile: "doc"
        case .runShortcut: "square.2.layers.3d"
        }
    }

    /// アイコンと，そのあとの文字までの空きを合わせた幅
    static var width: CGFloat { Glass.commandIconSize + Glass.noteGap }

    /// x を左端にアイコンを描く．アクセントの色を薄く敷いた四角(角丸のテーマは角を丸める)にアクセントの色の線画．
    /// selected は選んでいる行の上(アクセント色の地)に描くとき．opacity は出し始めの薄さ
    static func drawIcon(_ kind: LauncherCommand.Kind, x: CGFloat, midY: CGFloat, theme: ResolvedTheme, selected: Bool, opacity: CGFloat = 1) {
        let size = Glass.commandIconSize
        let rect = NSRect(x: x.rounded(), y: (midY - size / 2).rounded(), width: size, height: size)
        let fill = selected ? theme.selectionText.withAlphaComponent(DesignTokens.Opacity.Badge.selected) : theme.commandTint
        fill.withAlphaComponent(fill.alphaComponent * opacity).setFill()
        let radius = theme.isRounded ? Glass.commandIconRadius : 0
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        let color = (selected ? theme.selectionText : theme.selection).withAlphaComponent(opacity)
        guard let image = SymbolImageCache.image(symbol(for: kind), pointSize: Glass.keyFontSize, weight: .semibold, color: color) else { return }
        image.draw(in: NSRect(x: (rect.midX - image.size.width / 2).rounded(), y: (rect.midY - image.size.height / 2).rounded(),
                              width: image.size.width, height: image.size.height))
    }
}
